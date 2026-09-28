//! The turn timer (GAME_RULES.md "Turn Time Limit"). A party that starts with a turn time
//! limit and at least two humans times its humans' turns: every game-state write stamps
//! the deadline of the turn under way (`GameState::stamp_turn_deadline`), and a background
//! task (`spawn_turn_timer`) looks every second for a timed seat past its deadline. Its
//! human is ejected for good: a bot takes the seat, with its hand and score, the game goes
//! on, and the human's game counts as a loss.

use std::collections::HashSet;
use std::sync::Arc;
use std::time::Duration;

use uuid::Uuid;

use crate::application::bot::spawn_bot_turns;
use crate::domain::entities::{BotDifficulty, PartyStatus, User, UserType, DELETED_USER_ID_PREFIX};
use crate::domain::repositories::{
    PartyRepository, RepositoryError, SeatReplacement, UserRepository, VersionedGameState,
};
use crate::domain::value_objects::TURN_TIME_LIMITS;
use crate::infrastructure::app_state::{AppState, GameEvent};

/// How often the turn timer looks for a late seat
pub const TURN_TIMER_TICK: Duration = Duration::from_secs(1);
/// The pause before the bot that took a seat plays, as after a human's move
const STAND_IN_DELAY: Duration = Duration::from_millis(300);

/// A late human's seat given to a bot
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Ejection {
    pub party_id: String,
    pub player_index: u8,
    pub human_id: String,
    pub human_username: String,
    pub bot_id: String,
    pub bot_username: String,
    /// The party's new owner, when the human owned it
    pub new_owner_id: Option<String>,
}

/// The order a free bot is picked in to take a seat: a middle-strength rule-based bot
/// first; an LLM bot last, since it depends on an outside service
fn stand_in_rank(bot: &User) -> u8 {
    match bot.bot_difficulty {
        Some(BotDifficulty::Medium) => 0,
        Some(BotDifficulty::Hard) => 1,
        Some(BotDifficulty::Llm) => 3,
        _ => 2,
    }
}

/// Eject the human whose turn went past its deadline
pub struct EjectLatePlayer<U: UserRepository, P: PartyRepository> {
    user_repo: Arc<U>,
    party_repo: Arc<P>,
}

impl<U: UserRepository, P: PartyRepository> EjectLatePlayer<U, P> {
    pub fn new(user_repo: Arc<U>, party_repo: Arc<P>) -> Self {
        Self {
            user_repo,
            party_repo,
        }
    }

    /// Eject the human on turn in `party_id` when their turn went past its deadline at
    /// `now` (Unix milliseconds). `None` when nobody is late, or when a move came in
    /// between the read and the write: the move wins, and nothing is written.
    pub async fn execute(
        &self,
        party_id: &str,
        now: u64,
    ) -> Result<Option<Ejection>, RepositoryError> {
        let Some(party) = self.party_repo.find_by_id(party_id).await? else {
            return Ok(None);
        };
        if party.status != PartyStatus::Playing {
            return Ok(None);
        }
        let Some(VersionedGameState { state, version }) =
            self.party_repo.get_versioned_game_state(party_id).await?
        else {
            return Ok(None);
        };
        let Some(seat) = state.late_seat(now) else {
            return Ok(None);
        };

        let players = self.party_repo.get_party_players(party_id).await?;
        let Some(late) = players.iter().find(|p| p.player_index == seat) else {
            return Ok(None);
        };
        let Some(human) = self.user_repo.find_by_id(&late.user_id).await? else {
            return Ok(None);
        };
        if human.user_type != UserType::Human {
            // Only humans are timed; a bot plays its turn on its own
            return Ok(None);
        }

        let (bot, created) = self.stand_in(&players).await?;

        // The party passes to the first other human by seat, as on a forfeit; with no
        // other human, to the bot on the late human's seat, so that the owner is always a
        // player of the party (the bots play the game out)
        let new_owner_id = if party.owner_id == human.id {
            let mut others = players
                .iter()
                .filter(|p| p.user_id != human.id)
                .collect::<Vec<_>>();
            others.sort_by_key(|p| p.player_index);
            let ids: Vec<String> = others.iter().map(|p| p.user_id.clone()).collect();
            let users = self.user_repo.find_by_ids(&ids).await?;
            others
                .iter()
                .find_map(|p| {
                    users
                        .iter()
                        .find(|u| {
                            u.id == p.user_id
                                && u.user_type == UserType::Human
                                && !u.id.starts_with(DELETED_USER_ID_PREFIX)
                        })
                        .map(|u| u.id.clone())
                })
                .or_else(|| Some(bot.id.clone()))
        } else {
            None
        };

        let mut updated = state.clone();
        updated.untime_seat(seat);
        let replaced = self
            .party_repo
            .replace_player(&SeatReplacement {
                party_id,
                player_index: seat,
                human_id: &human.id,
                bot_id: &bot.id,
                new_bot: created.then_some(&bot),
                new_owner_id: new_owner_id.as_deref(),
                state: &updated,
                expected_version: version,
                seat_count: players.len() as u8,
            })
            .await;
        match replaced {
            Ok(()) => {}
            // The human moved in time after all, or the seat changed hands meanwhile
            Err(e) if e.is_conflict() => return Ok(None),
            Err(e) => return Err(e),
        }

        Ok(Some(Ejection {
            party_id: party_id.to_string(),
            player_index: seat,
            human_id: human.id,
            human_username: human.username,
            bot_id: bot.id,
            bot_username: bot.username,
            new_owner_id,
        }))
    }

    /// A bot not seated at this table, and whether it is a new one, which `replace_player`
    /// creates with the ejection (none is free)
    async fn stand_in(
        &self,
        players: &[crate::domain::entities::PartyPlayer],
    ) -> Result<(User, bool), RepositoryError> {
        let seated: HashSet<&str> = players.iter().map(|p| p.user_id.as_str()).collect();
        let mut free: Vec<User> = self
            .user_repo
            .find_all_bots(None)
            .await?
            .into_iter()
            .filter(|bot| !seated.contains(bot.id.as_str()))
            .collect();
        free.sort_by(|a, b| (stand_in_rank(a), &a.username).cmp(&(stand_in_rank(b), &b.username)));
        if let Some(bot) = free.into_iter().next() {
            return Ok((bot, false));
        }
        let id = Uuid::new_v4().to_string();
        let bot = User::new_bot(
            id.clone(),
            format!("StandInBot-{}", &id[..8]),
            BotDifficulty::Medium,
        );
        Ok((bot, true))
    }
}

/// Eject every human past their turn deadline now: each ejection is told to the party's
/// players (and to the ejected human) as `gameUpdate` `playerReplaced`, and the bot that
/// took the seat plays. Returns the ejections.
pub async fn enforce_turn_deadlines(state: &Arc<AppState>) -> Vec<Ejection> {
    let now = state.clock.now_millis();
    let parties = match state.party_repo.parties_past_turn_deadline(now).await {
        Ok(parties) => parties,
        Err(e) => {
            tracing::error!("Turn timer: looking for late seats failed: {}", e);
            return Vec::new();
        }
    };
    let mut ejections = Vec::new();
    for party_id in parties {
        let ejected = EjectLatePlayer::new(state.user_repo.clone(), state.party_repo.clone())
            .execute(&party_id, now)
            .await;
        match ejected {
            Ok(Some(ejection)) => {
                tracing::info!(
                    "Turn timer: {} ran out of time in party {}; {} takes seat {}",
                    ejection.human_username,
                    party_id,
                    ejection.bot_username,
                    ejection.player_index
                );
                // In the ejected human's name, so that their own stream hears of it too
                let event = GameEvent::new(
                    "gameUpdate",
                    Some(party_id.clone()),
                    Some(ejection.human_id.clone()),
                )
                .with_action("playerReplaced")
                .with_data(serde_json::json!({
                    "playerIndex": ejection.player_index,
                    "replacedUserId": ejection.human_id,
                    "replacedUsername": ejection.human_username,
                    "botId": ejection.bot_id,
                    "botUsername": ejection.bot_username,
                    "newOwnerId": ejection.new_owner_id,
                }));
                state.broadcast_event(event);
                spawn_bot_turns(state, party_id, STAND_IN_DELAY);
                ejections.push(ejection);
            }
            Ok(None) => {}
            Err(e) => tracing::error!("Turn timer: party {} failed: {}", party_id, e),
        }
    }
    ejections
}

/// At the server's start, give every turn under way at least its whole limit from now:
/// the deadlines are absolute times, and the time the server was down (a deploy, a
/// restart) must not count against the player on turn. A deadline already further away is
/// kept. Returns the number of turns given more time.
pub async fn extend_turn_deadlines_after_downtime(state: &Arc<AppState>) -> usize {
    let now = state.clock.now_millis();
    let longest = u64::from(TURN_TIME_LIMITS.iter().copied().max().unwrap_or(0)) * 1000;
    // Every party whose deadline could fall before now + its own limit
    let parties = match state
        .party_repo
        .parties_past_turn_deadline(now.saturating_add(longest))
        .await
    {
        Ok(parties) => parties,
        Err(e) => {
            tracing::error!("Turn timer: reading the deadlines at startup failed: {}", e);
            return 0;
        }
    };
    let mut extended = 0;
    for party_id in parties {
        let read = state.party_repo.get_versioned_game_state(&party_id).await;
        let Ok(Some(VersionedGameState {
            state: mut game_state,
            version,
        })) = read
        else {
            continue;
        };
        let full_turn = now.saturating_add(u64::from(game_state.turn_clock.limit_secs) * 1000);
        match game_state.turn_clock.deadline {
            Some(deadline) if deadline < full_turn => {
                game_state.turn_clock.deadline = Some(full_turn);
            }
            _ => continue,
        }
        // The same turn keeps the deadline it is written with (`stamp_turn_deadline`); a
        // move that wrote meanwhile began its own turn or kept one it had in full
        match state
            .party_repo
            .update_game_state(&party_id, &game_state, version)
            .await
        {
            Ok(()) => extended += 1,
            Err(e) if e.is_conflict() => {}
            Err(e) => tracing::error!("Turn timer: party {} at startup: {}", party_id, e),
        }
    }
    if extended > 0 {
        tracing::info!("Turn timer: {extended} turn(s) under way given their whole limit again");
    }
    extended
}

/// Run the turn timer in the background, every `every`, for the server's lifetime. It
/// starts by giving the turns under way their whole limit again
/// (`extend_turn_deadlines_after_downtime`): it runs once per server start.
pub fn spawn_turn_timer(state: Arc<AppState>, every: Duration) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        extend_turn_deadlines_after_downtime(&state).await;
        let mut ticks = tokio::time::interval(every);
        ticks.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);
        loop {
            ticks.tick().await;
            enforce_turn_deadlines(&state).await;
        }
    })
}
