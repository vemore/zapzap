use std::collections::HashSet;
use std::convert::Infallible;
use std::sync::Arc;
use std::time::Duration;

use crate::api::middleware::user_exists;
use crate::domain::entities::PartyVisibility;
use crate::domain::repositories::PartyRepository;
use crate::infrastructure::app_state::{AppState, GameEvent};
use axum::{
    extract::{Query, State},
    http::header,
    response::{
        sse::{Event, KeepAlive, Sse},
        IntoResponse,
    },
};
use serde::Deserialize;

#[derive(Deserialize)]
pub struct SseParams {
    token: Option<String>,
}

/// The party actions every stream receives when the party is public: what changes a row
/// of the public party list (seats, status, the party being there at all), which the
/// Flutter `PartyListProvider` reloads on. None carries more than names, indexes and ids.
const PUBLIC_LIFECYCLE_ACTIONS: [&str; 6] = [
    "partyCreated",
    "playerJoined",
    "playerLeft",
    "partyStarted",
    "partyDeleted",
    "gameFinished",
];

/// Whether the party `event` is about is public. A deleted party is gone from the
/// database, so its `partyDeleted` event carries the visibility it had.
async fn is_public_party(state: &AppState, party_id: &str, event: &GameEvent) -> bool {
    if event.action.as_deref() == Some("partyDeleted") {
        return event.data.get("visibility").and_then(|v| v.as_str()) == Some("public");
    }
    match state.party_repo.find_by_id(party_id).await {
        Ok(Some(party)) => party.visibility == PartyVisibility::Public,
        Ok(None) => false,
        Err(e) => {
            tracing::warn!("SSE: party {} lookup failed: {}", party_id, e);
            false
        }
    }
}

/// Whether a client receives `event`.
///
/// - An event without a party (`userConnected`, `userDisconnected`, ...) goes to everyone,
///   as Node sends it.
/// - A public party's lifecycle event (`PUBLIC_LIFECYCLE_ACTIONS`) goes to everyone too.
/// - Any other party event (`gameUpdate` moves, every event of a private party) goes only
///   to an authenticated client that is a player of that party, or whose own action it
///   reports (the player who just left); and a `partyDeleted` to the clients that were
///   players of it when the stream opened or since (the membership rows are gone by the
///   time it goes out). `known_parties` holds those parties, and is kept up to date here.
async fn should_deliver(
    state: &AppState,
    user_id: Option<&str>,
    known_parties: &mut HashSet<String>,
    event: &GameEvent,
) -> bool {
    let Some(party_id) = event.party_id.as_deref() else {
        return true;
    };
    let lifecycle = event
        .action
        .as_deref()
        .is_some_and(|a| PUBLIC_LIFECYCLE_ACTIONS.contains(&a));
    if lifecycle && is_public_party(state, party_id, event).await {
        return true;
    }
    let Some(user_id) = user_id else {
        return false;
    };
    let own_action = event.user_id.as_deref() == Some(user_id);
    match state.party_repo.is_player_in_party(party_id, user_id).await {
        Ok(true) => {
            known_parties.insert(party_id.to_string());
            true
        }
        Ok(false) => {
            // No longer a player: forget the party, but still hear of the own action that
            // ended the membership (leaving) and of the party's deletion
            let was_member = known_parties.remove(party_id);
            own_action || (was_member && event.action.as_deref() == Some("partyDeleted"))
        }
        Err(e) => {
            // Membership unknown: go by what the stream already knew, change nothing
            tracing::warn!(
                "SSE: membership lookup for party {} failed: {}",
                party_id,
                e
            );
            own_action || known_parties.contains(party_id)
        }
    }
}

/// The parties `user_id` plays in, when the stream opens.
async fn parties_of(state: &AppState, user_id: &str) -> HashSet<String> {
    sqlx::query_scalar::<_, String>("SELECT party_id FROM party_players WHERE user_id = ?")
        .bind(user_id)
        .fetch_all(&state.db)
        .await
        .unwrap_or_default()
        .into_iter()
        .collect()
}

pub async fn sse_handler(
    State(state): State<Arc<AppState>>,
    Query(params): Query<SseParams>,
) -> impl IntoResponse {
    // Validate token if provided; a deleted user's token names nobody (Node: ValidateToken.js)
    let claims = match params.token {
        Some(token) => state.jwt_service.verify(&token).ok(),
        None => None,
    };
    let claims = match claims {
        Some(claims) if user_exists(&state, &claims.user_id).await => Some(claims),
        _ => None,
    };
    let user_info = claims.map(|claims| {
        // Connect user to session manager
        state
            .session_manager
            .connect(&claims.user_id, &claims.username);

        // Broadcast user connected event
        let event = GameEvent::new("userConnected", None, Some(claims.user_id.clone())).with_data(
            serde_json::json!({
                "username": claims.username
            }),
        );
        state.broadcast_event(event);

        (claims.user_id, claims.username)
    });

    let mut known_parties = match &user_info {
        Some((user_id, _)) => parties_of(&state, user_id).await,
        None => HashSet::new(),
    };

    // Subscribe to events - use new_receiver() to get an active receiver
    let mut receiver = state.event_sender.new_receiver();
    let session_manager = state.session_manager.clone();
    let event_sender = state.event_sender.clone();
    let user_info_clone = user_info.clone();
    let state_for_stream = state.clone();

    let stream = async_stream::stream! {
        tracing::debug!("SSE stream started");
        let user_id = user_info_clone.as_ref().map(|(id, _)| id.as_str());

        // Send initial connected event
        yield Ok::<_, Infallible>(Event::default()
            .event("connected")
            .data(serde_json::json!({
                "message": "Connected to SSE stream",
                "timestamp": chrono::Utc::now().timestamp_millis()
            }).to_string()));

        let mut heartbeat_interval = tokio::time::interval(Duration::from_secs(20));

        loop {
            tokio::select! {
                _ = heartbeat_interval.tick() => {
                    tracing::trace!("SSE heartbeat");
                    // Send heartbeat comment (not a real event)
                    yield Ok(Event::default().comment("heartbeat"));
                }
                result = receiver.recv() => {
                    match result {
                        Ok(event) => {
                            if !should_deliver(&state_for_stream, user_id, &mut known_parties, &event).await {
                                continue;
                            }
                            tracing::debug!("SSE broadcasting event: {:?}", event.event_type);
                            let json = serde_json::to_string(&event).unwrap_or_default();
                            yield Ok(Event::default()
                                .event("event")
                                .data(json));
                        }
                        Err(e) => {
                            tracing::warn!("SSE receiver error: {:?}, closing stream", e);
                            // Channel closed, reconnect
                            break;
                        }
                    }
                }
            }
        }

        // Cleanup on disconnect
        if let Some((user_id, _username)) = user_info_clone {
            session_manager.disconnect(&user_id);

            let event = GameEvent::new("userDisconnected", None, Some(user_id));
            let _ = event_sender.try_broadcast(event);
        }
    };

    // No proxy buffering (nginx honours X-Accel-Buffering; axum's Sse sets
    // `Cache-Control: no-cache`); the 20 s heartbeat
    // and axum's keep-alive comment keep idle proxies from timing the stream out.
    (
        [(header::HeaderName::from_static("x-accel-buffering"), "no")],
        Sse::new(stream).keep_alive(KeepAlive::default()),
    )
}
