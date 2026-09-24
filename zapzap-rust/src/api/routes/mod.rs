pub mod admin;
pub mod auth;
pub mod bots;
pub mod game;
pub mod health;
pub mod history;
pub mod party;
pub mod players;
pub mod stats;

use std::sync::Arc;

use axum::{
    middleware,
    routing::{delete, get, post},
    Router,
};

use crate::api::middleware::{admin_middleware, auth_middleware, optional_auth_middleware};
use crate::api::AppState;

/// Create the main API router
pub fn create_api_router(state: Arc<AppState>) -> Router<Arc<AppState>> {
    Router::new()
        .nest("/auth", auth::create_auth_router())
        .nest("/party", create_party_router(state.clone()))
        .nest("/game", create_game_router(state.clone()))
        .nest("/stats", create_stats_router(state.clone()))
        .nest("/history", create_history_router(state.clone()))
        .nest("/admin", create_admin_router(state.clone()))
        .route("/bots", get(bots::list_bots))
        .route("/players/connected", get(players::get_connected_players))
        .route("/health", get(health::health_handler))
        .fallback(crate::api::not_found::route_not_found)
        .with_state(state)
}

/// Create party router
fn create_party_router(state: Arc<AppState>) -> Router<Arc<AppState>> {
    Router::new()
        // Public routes (optional auth)
        .route(
            "/",
            get(party::list_parties).layer(middleware::from_fn_with_state(
                state.clone(),
                optional_auth_middleware,
            )),
        )
        // Protected routes (require auth)
        .route(
            "/",
            post(party::create_party).layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            )),
        )
        .route(
            "/:partyId",
            get(party::get_party_details).layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            )),
        )
        .route(
            "/:partyId",
            delete(party::delete_party).layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            )),
        )
        .route(
            "/:partyId/join",
            post(party::join_party).layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            )),
        )
        .route(
            "/:partyId/leave",
            post(party::leave_party).layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            )),
        )
        .route(
            "/:partyId/start",
            post(party::start_party).layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            )),
        )
        .route(
            "/:partyId/bots",
            post(party::add_bot).layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            )),
        )
        .with_state(state)
}

/// Create game router
fn create_game_router(state: Arc<AppState>) -> Router<Arc<AppState>> {
    Router::new()
        .route(
            "/:partyId/state",
            get(game::get_game_state).layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            )),
        )
        .route(
            "/:partyId/selectHandSize",
            post(game::select_hand_size).layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            )),
        )
        .route(
            "/:partyId/play",
            post(game::play_cards).layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            )),
        )
        .route(
            "/:partyId/draw",
            post(game::draw_card).layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            )),
        )
        .route(
            "/:partyId/zapzap",
            post(game::call_zapzap).layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            )),
        )
        .route(
            "/:partyId/nextRound",
            post(game::next_round).layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            )),
        )
        .route(
            "/:partyId/trigger-bot",
            post(game::trigger_bot).layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            )),
        )
        .with_state(state)
}

/// Create stats router
fn create_stats_router(state: Arc<AppState>) -> Router<Arc<AppState>> {
    Router::new()
        .route(
            "/me",
            get(stats::get_my_stats).layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            )),
        )
        .route("/user/:userId", get(stats::get_user_stats))
        .route("/leaderboard", get(stats::get_leaderboard))
        .route("/bots", get(stats::get_bot_stats))
        .with_state(state)
}

/// Create history router
fn create_history_router(state: Arc<AppState>) -> Router<Arc<AppState>> {
    Router::new()
        .route(
            "/",
            get(history::get_history).layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            )),
        )
        .route(
            "/my-games",
            get(history::get_history).layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            )),
        )
        .route("/public", get(history::get_public_history))
        .route(
            "/:partyId",
            get(history::get_game_details).layer(middleware::from_fn_with_state(
                state.clone(),
                auth_middleware,
            )),
        )
        .with_state(state)
}

/// Create admin router: every route behind `auth_middleware` (401), then
/// `admin_middleware` (403 for a non-admin)
fn create_admin_router(state: Arc<AppState>) -> Router<Arc<AppState>> {
    Router::new()
        .route("/users", get(admin::list_users))
        .route("/users/:userId", delete(admin::delete_user))
        .route("/users/:userId/admin", post(admin::set_user_admin))
        .route("/parties", get(admin::list_parties))
        .route("/parties/:partyId/stop", post(admin::stop_party))
        .route("/parties/:partyId", delete(admin::admin_delete_party))
        .route("/statistics", get(admin::get_statistics))
        // The last layer runs first: auth sets the claims admin_middleware reads
        .route_layer(middleware::from_fn_with_state(
            state.clone(),
            admin_middleware,
        ))
        .route_layer(middleware::from_fn_with_state(
            state.clone(),
            auth_middleware,
        ))
        .with_state(state)
}
