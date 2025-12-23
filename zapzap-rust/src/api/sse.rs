use std::convert::Infallible;
use std::sync::Arc;
use std::time::Duration;

use axum::{
    extract::{Query, State},
    response::sse::{Event, KeepAlive, Sse},
};
use futures::stream::Stream;
use serde::Deserialize;
use crate::infrastructure::app_state::{AppState, GameEvent};

#[derive(Deserialize)]
pub struct SseParams {
    token: Option<String>,
}

pub async fn sse_handler(
    State(state): State<Arc<AppState>>,
    Query(params): Query<SseParams>,
) -> Sse<impl Stream<Item = Result<Event, Infallible>>> {
    // Validate token if provided
    let user_info = params.token.and_then(|token| {
        state.jwt_service.verify(&token).ok().map(|claims| {
            // Connect user to session manager
            state.session_manager.connect(&claims.user_id, &claims.username);

            // Broadcast user connected event
            let event = GameEvent::new("userConnected", None, Some(claims.user_id.clone()))
                .with_data(serde_json::json!({
                    "username": claims.username
                }));
            state.broadcast_event(event);

            (claims.user_id, claims.username)
        })
    });

    // Subscribe to events - use new_receiver() to get an active receiver
    let mut receiver = state.event_sender.new_receiver();
    let session_manager = state.session_manager.clone();
    let event_sender = state.event_sender.clone();
    let user_info_clone = user_info.clone();

    let stream = async_stream::stream! {
        tracing::debug!("SSE stream started");

        // Send initial connected event
        yield Ok(Event::default()
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

    Sse::new(stream).keep_alive(KeepAlive::default())
}
