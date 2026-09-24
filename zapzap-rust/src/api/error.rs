//! Typed API errors: each use-case error variant maps to the status and `code` the Node
//! backend answers for it (`src/api/routes/partyRoutes.js`, `gameRoutes.js`), with no
//! matching on message text. Where Node answers 500 for a client error (a Node bug), the
//! mapping keeps a 4xx; `.llmwiki/Api.md` lists those cases.

use axum::{
    async_trait,
    extract::{rejection::JsonRejection, FromRequest, Request},
    http::StatusCode,
    response::{IntoResponse, Response},
    Json,
};
use serde::{de::DeserializeOwned, Serialize};

use crate::application::game::{
    CallZapZapError, DrawCardError, GetGameStateError, NextRoundError, PlayCardsError,
    SelectHandSizeError,
};
use crate::application::party::{
    AddBotToPartyError, CreatePartyError, DeletePartyError, GetPartyDetailsError, JoinPartyError,
    LeavePartyError, ListPartiesError, StartPartyError,
};

/// An error answered as `{error, code, details?}` with its HTTP status.
#[derive(Debug, thiserror::Error)]
#[error("{status} {code}: {message}")]
pub struct ApiError {
    pub status: StatusCode,
    pub code: &'static str,
    pub message: String,
    pub details: Option<String>,
}

/// The JSON body of every error of the party and game routes.
#[derive(Debug, Serialize)]
pub struct ErrorBody {
    pub error: String,
    pub code: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub details: Option<String>,
}

impl ApiError {
    pub fn new(status: StatusCode, code: &'static str, message: impl Into<String>) -> Self {
        Self {
            status,
            code,
            message: message.into(),
            details: None,
        }
    }

    pub fn bad_request(code: &'static str, message: impl Into<String>) -> Self {
        Self::new(StatusCode::BAD_REQUEST, code, message)
    }

    pub fn forbidden(code: &'static str, message: impl Into<String>) -> Self {
        Self::new(StatusCode::FORBIDDEN, code, message)
    }

    pub fn not_found(code: &'static str, message: impl Into<String>) -> Self {
        Self::new(StatusCode::NOT_FOUND, code, message)
    }

    pub fn conflict(code: &'static str, message: impl Into<String>) -> Self {
        Self::new(StatusCode::CONFLICT, code, message)
    }

    /// A server-side failure, in Node's shape: a generic message, the cause in `details`.
    pub fn internal(code: &'static str, message: &str, cause: impl ToString) -> Self {
        Self {
            details: Some(cause.to_string()),
            ..Self::new(StatusCode::INTERNAL_SERVER_ERROR, code, message)
        }
    }

    pub(crate) fn party_not_found() -> Self {
        Self::not_found("PARTY_NOT_FOUND", "Party not found")
    }

    pub(crate) fn not_in_party() -> Self {
        Self::forbidden("NOT_IN_PARTY", "User is not in this party")
    }

    fn party_not_playing() -> Self {
        Self::bad_request("INVALID_PARTY_STATE", "Party is not in playing state")
    }
}

impl IntoResponse for ApiError {
    fn into_response(self) -> Response {
        if self.status.is_server_error() {
            tracing::error!("{}", self);
        }
        let body = ErrorBody {
            error: self.message,
            code: self.code.to_string(),
            details: self.details,
        };
        (self.status, Json(body)).into_response()
    }
}

// ============================================================================
// Request bodies
// ============================================================================

/// A request body whose unreadable form (malformed JSON, a missing or mistyped field)
/// answers 400 with the code Node gives the same route for a missing field.
pub trait ApiBody: DeserializeOwned {
    const INVALID_CODE: &'static str;
    const INVALID_MESSAGE: &'static str;

    /// That 400: `{error, code}`, the body of the party and game routes. A route whose
    /// Node handler answers another shape (the admin routes) overrides it.
    fn invalid_body() -> Response {
        ApiError::bad_request(Self::INVALID_CODE, Self::INVALID_MESSAGE).into_response()
    }
}

/// `Json<T>` that rejects with `T::invalid_body()` (400, JSON body) instead of axum's 422 plain text.
/// A request without a JSON content type reads as `{}`, as Express does.
pub struct ApiJson<T>(pub T);

#[async_trait]
impl<T, S> FromRequest<S> for ApiJson<T>
where
    T: ApiBody,
    S: Send + Sync,
{
    type Rejection = Response;

    async fn from_request(req: Request, state: &S) -> Result<Self, Self::Rejection> {
        let rejection = match Json::<T>::from_request(req, state).await {
            Ok(Json(value)) => return Ok(ApiJson(value)),
            Err(rejection) => rejection,
        };
        if matches!(rejection, JsonRejection::MissingJsonContentType(_)) {
            if let Ok(value) = serde_json::from_str::<T>("{}") {
                return Ok(ApiJson(value));
            }
        }
        // A body over the limit is no validation failure of the route's
        if rejection.status() == StatusCode::PAYLOAD_TOO_LARGE {
            return Err(ApiError::new(
                StatusCode::PAYLOAD_TOO_LARGE,
                "PAYLOAD_TOO_LARGE",
                "Request body too large",
            )
            .into_response());
        }
        // Node's body for a missing field: `{error, code}`, no parser message in `details`
        tracing::debug!("unreadable request body: {}", rejection.body_text());
        Err(T::invalid_body())
    }
}

// ============================================================================
// Party use cases
// ============================================================================

impl From<CreatePartyError> for ApiError {
    fn from(e: CreatePartyError) -> Self {
        match e {
            CreatePartyError::Validation(msg) => Self::bad_request("VALIDATION_ERROR", msg),
            CreatePartyError::UserNotFound => Self::not_found("USER_NOT_FOUND", "User not found"),
            CreatePartyError::Repository(e) => {
                Self::internal("CREATE_PARTY_ERROR", "Failed to create party", e)
            }
        }
    }
}

impl From<ListPartiesError> for ApiError {
    fn from(e: ListPartiesError) -> Self {
        match e {
            ListPartiesError::Repository(e) => {
                Self::internal("GET_PARTIES_ERROR", "Failed to get parties", e)
            }
        }
    }
}

impl From<GetPartyDetailsError> for ApiError {
    fn from(e: GetPartyDetailsError) -> Self {
        match e {
            GetPartyDetailsError::PartyNotFound => Self::party_not_found(),
            // Node means this refusal too but answers 500 (its message has no branch)
            GetPartyDetailsError::NotInParty => Self::not_in_party(),
            GetPartyDetailsError::Repository(e) => {
                Self::internal("GET_PARTY_ERROR", "Failed to get party details", e)
            }
        }
    }
}

impl From<JoinPartyError> for ApiError {
    fn from(e: JoinPartyError) -> Self {
        match e {
            JoinPartyError::Validation(msg) => Self::bad_request("VALIDATION_ERROR", msg),
            JoinPartyError::UserNotFound => Self::not_found("USER_NOT_FOUND", "User not found"),
            JoinPartyError::PartyNotFound => Self::party_not_found(),
            // Node answers 500 JOIN_PARTY_ERROR for both (no branch): a Node bug
            JoinPartyError::PrivateParty => Self::forbidden(
                "PRIVATE_PARTY",
                "Party is private. Use invite code to join.",
            ),
            JoinPartyError::InvalidInviteCode => {
                Self::forbidden("INVALID_INVITE_CODE", "Invalid invite code")
            }
            JoinPartyError::PartyNotWaiting => {
                Self::conflict("PARTY_STARTED", "Party has already started")
            }
            JoinPartyError::AlreadyInParty => {
                Self::conflict("ALREADY_IN_PARTY", "User is already in this party")
            }
            JoinPartyError::PartyFull => Self::conflict("PARTY_FULL", "Party is full"),
            JoinPartyError::Repository(e) => {
                Self::internal("JOIN_PARTY_ERROR", "Failed to join party", e)
            }
        }
    }
}

impl From<LeavePartyError> for ApiError {
    fn from(e: LeavePartyError) -> Self {
        match e {
            LeavePartyError::PartyNotFound => Self::party_not_found(),
            LeavePartyError::NotInParty => Self::not_in_party(),
            LeavePartyError::PartyPlaying => {
                Self::conflict("PARTY_PLAYING", "Cannot leave party during active game")
            }
            LeavePartyError::Repository(e) => {
                Self::internal("LEAVE_PARTY_ERROR", "Failed to leave party", e)
            }
        }
    }
}

impl From<StartPartyError> for ApiError {
    fn from(e: StartPartyError) -> Self {
        match e {
            StartPartyError::PartyNotFound => Self::party_not_found(),
            StartPartyError::NotOwner => {
                Self::forbidden("NOT_OWNER", "Only the party owner can start the game")
            }
            StartPartyError::PartyPlaying => {
                Self::conflict("PARTY_ALREADY_PLAYING", "Party is already playing")
            }
            // Node's message; Node answers it 500, Rust keeps the 409 of a started party
            StartPartyError::PartyFinished => {
                Self::conflict("PARTY_ALREADY_PLAYING", "Party has finished")
            }
            StartPartyError::NotEnoughPlayers => {
                Self::bad_request("NOT_ENOUGH_PLAYERS", "At least 3 players required to start")
            }
            StartPartyError::Repository(e) => {
                Self::internal("START_PARTY_ERROR", "Failed to start party", e)
            }
        }
    }
}

impl From<DeletePartyError> for ApiError {
    fn from(e: DeletePartyError) -> Self {
        match e {
            DeletePartyError::PartyNotFound => Self::party_not_found(),
            DeletePartyError::NotInParty => Self::not_in_party(),
            DeletePartyError::NotOwner => Self::forbidden(
                "NOT_AUTHORIZED",
                "Only the party owner or the only human player can delete the party",
            ),
            DeletePartyError::PartyInProgress => {
                Self::conflict("PARTY_PLAYING", "Cannot delete party during active game")
            }
            DeletePartyError::Repository(e) => {
                Self::internal("DELETE_PARTY_ERROR", "Failed to delete party", e)
            }
        }
    }
}

impl From<AddBotToPartyError> for ApiError {
    fn from(e: AddBotToPartyError) -> Self {
        match e {
            AddBotToPartyError::PartyNotFound => Self::party_not_found(),
            AddBotToPartyError::NotOwner => {
                Self::forbidden("NOT_OWNER", "Only the party owner can add a bot")
            }
            AddBotToPartyError::PartyNotWaiting => {
                Self::conflict("PARTY_STARTED", "Party has already started")
            }
            AddBotToPartyError::PartyFull => Self::conflict("PARTY_FULL", "Party is full"),
            AddBotToPartyError::BotNotFound => Self::not_found("BOT_NOT_FOUND", "Bot not found"),
            AddBotToPartyError::NotABot => Self::bad_request("NOT_A_BOT", "User is not a bot"),
            AddBotToPartyError::AlreadyInParty => {
                Self::conflict("ALREADY_IN_PARTY", "Bot is already in this party")
            }
            AddBotToPartyError::Repository(e) => {
                Self::internal("ADD_BOT_ERROR", "Failed to add bot", e)
            }
        }
    }
}

// ============================================================================
// Game use cases
// ============================================================================

impl From<GetGameStateError> for ApiError {
    fn from(e: GetGameStateError) -> Self {
        match e {
            GetGameStateError::PartyNotFound => Self::party_not_found(),
            GetGameStateError::NotInParty => Self::not_in_party(),
            GetGameStateError::Repository(e) => {
                Self::internal("GET_STATE_ERROR", "Failed to get game state", e)
            }
        }
    }
}

impl From<SelectHandSizeError> for ApiError {
    fn from(e: SelectHandSizeError) -> Self {
        const CODE: &str = "SELECT_HAND_SIZE_ERROR";
        const MSG: &str = "Failed to select hand size";
        match e {
            SelectHandSizeError::InvalidHandSize { min, max } => Self::bad_request(
                "INVALID_HAND_SIZE",
                format!("Hand size must be between {min} and {max}"),
            ),
            SelectHandSizeError::PartyNotFound => Self::party_not_found(),
            SelectHandSizeError::PartyNotPlaying => Self::party_not_playing(),
            SelectHandSizeError::NotInParty => Self::not_in_party(),
            SelectHandSizeError::NotYourTurn => {
                Self::forbidden("NOT_YOUR_TURN", "Not your turn to select hand size")
            }
            SelectHandSizeError::WrongAction => {
                Self::bad_request("INVALID_ACTION_STATE", "Not in hand size selection phase")
            }
            e @ SelectHandSizeError::NoGameState => Self::internal(CODE, MSG, e),
            SelectHandSizeError::Repository(e) => Self::internal(CODE, MSG, e),
        }
    }
}

impl From<PlayCardsError> for ApiError {
    fn from(e: PlayCardsError) -> Self {
        const CODE: &str = "PLAY_CARDS_ERROR";
        const MSG: &str = "Failed to play cards";
        match e {
            PlayCardsError::PartyNotFound => Self::party_not_found(),
            PlayCardsError::PartyNotPlaying => Self::party_not_playing(),
            PlayCardsError::NotInParty => Self::not_in_party(),
            PlayCardsError::NotYourTurn => Self::forbidden("NOT_YOUR_TURN", "Not your turn"),
            PlayCardsError::WrongAction => {
                Self::bad_request("INVALID_ACTION_STATE", "Current action is not PLAY")
            }
            PlayCardsError::NoCardsSelected => {
                Self::bad_request("MISSING_CARDS", "Card IDs are required")
            }
            PlayCardsError::CardNotInHand(card) => {
                Self::bad_request("INVALID_CARDS", format!("Card {card} not in hand"))
            }
            PlayCardsError::RepeatedCard(card) => Self::bad_request(
                "INVALID_CARDS",
                format!("Card {card} played more than once"),
            ),
            PlayCardsError::InvalidCombination => {
                Self::bad_request("INVALID_PLAY", "Invalid card combination")
            }
            e @ (PlayCardsError::NoGameState | PlayCardsError::GameError(_)) => {
                Self::internal(CODE, MSG, e)
            }
            PlayCardsError::Repository(e) => Self::internal(CODE, MSG, e),
        }
    }
}

impl From<DrawCardError> for ApiError {
    fn from(e: DrawCardError) -> Self {
        const CODE: &str = "DRAW_CARD_ERROR";
        const MSG: &str = "Failed to draw card";
        match e {
            DrawCardError::PartyNotFound => Self::party_not_found(),
            DrawCardError::PartyNotPlaying => Self::party_not_playing(),
            DrawCardError::NotInParty => Self::not_in_party(),
            DrawCardError::NotYourTurn => Self::forbidden("NOT_YOUR_TURN", "Not your turn"),
            DrawCardError::WrongAction => {
                Self::bad_request("INVALID_ACTION_STATE", "Current action is not DRAW")
            }
            DrawCardError::DeckEmpty => {
                Self::bad_request("DECK_EMPTY", "Deck is empty and no cards to reshuffle")
            }
            DrawCardError::NoCardsAvailable => Self::bad_request(
                "NO_CARDS_AVAILABLE",
                "No cards available to draw from played cards",
            ),
            DrawCardError::CardNotAvailable => {
                Self::bad_request("CARD_NOT_AVAILABLE", "Card not available in played cards")
            }
            e @ (DrawCardError::NoGameState | DrawCardError::GameError(_)) => {
                Self::internal(CODE, MSG, e)
            }
            DrawCardError::Repository(e) => Self::internal(CODE, MSG, e),
        }
    }
}

impl From<CallZapZapError> for ApiError {
    fn from(e: CallZapZapError) -> Self {
        const CODE: &str = "ZAPZAP_ERROR";
        const MSG: &str = "Failed to call zapzap";
        match e {
            CallZapZapError::PartyNotFound => Self::party_not_found(),
            CallZapZapError::PartyNotPlaying => Self::party_not_playing(),
            CallZapZapError::NotInParty => Self::not_in_party(),
            CallZapZapError::NotYourTurn => Self::forbidden("NOT_YOUR_TURN", "Not your turn"),
            CallZapZapError::WrongAction => {
                Self::bad_request("INVALID_ACTION_STATE", "Cannot call zapzap at this time")
            }
            CallZapZapError::HandTooHigh => Self::bad_request(
                "HAND_TOO_HIGH",
                "Hand value too high. Must be ≤5 to call zapzap.",
            ),
            e @ (CallZapZapError::NoGameState | CallZapZapError::GameError(_)) => {
                Self::internal(CODE, MSG, e)
            }
            CallZapZapError::Repository(e) => Self::internal(CODE, MSG, e),
        }
    }
}

impl From<NextRoundError> for ApiError {
    fn from(e: NextRoundError) -> Self {
        const CODE: &str = "NEXT_ROUND_ERROR";
        const MSG: &str = "Failed to start next round";
        match e {
            NextRoundError::PartyNotFound => Self::party_not_found(),
            NextRoundError::PartyNotPlaying => Self::party_not_playing(),
            NextRoundError::RoundNotFinished => {
                Self::bad_request("ROUND_NOT_FINISHED", "Current round is not finished")
            }
            e @ NextRoundError::NoGameState => Self::internal(CODE, MSG, e),
            NextRoundError::Repository(e) => Self::internal(CODE, MSG, e),
        }
    }
}
