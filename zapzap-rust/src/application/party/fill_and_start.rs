use std::sync::Arc;

use super::seat::{seat_player, Seating};
use super::start_party::{StartParty, StartPartyError, StartPartyInput, StartPartyOutput};
use crate::domain::entities::{BotDifficulty, PartyPlayer, PartyStatus, User};
use crate::domain::repositories::{PartyRepository, RepositoryError, UserRepository};

/// The levels a fill may seat, weakest first. `llm` needs a language model and answers
/// slowly; `drl` and `ml` have no strategy of their own (they play as `hard`): none of
/// the three is picked for a table filled in one step.
const FILL_LADDER: [BotDifficulty; 5] = [
    BotDifficulty::Easy,
    BotDifficulty::Medium,
    BotDifficulty::Hard,
    BotDifficulty::HardVince,
    BotDifficulty::Thibot,
];

/// The levels a fill asking for `difficulty` draws from, in order: that level, the
/// stronger ones going up, then the weaker ones going down. `easy` gives easy, medium,
/// hard, hard_vince, thibot; `hard` gives hard, hard_vince, thibot, medium, easy.
pub fn fill_order(difficulty: BotDifficulty) -> Vec<BotDifficulty> {
    let at = FILL_LADDER
        .iter()
        .position(|d| *d == difficulty)
        .unwrap_or(0);
    FILL_LADDER[at..]
        .iter()
        .chain(FILL_LADDER[..at].iter().rev())
        .copied()
        .collect()
}

/// The levels a client may ask a fill for: the three it offers
pub fn parse_fill_difficulty(value: &str) -> Option<BotDifficulty> {
    match value {
        "easy" => Some(BotDifficulty::Easy),
        "medium" => Some(BotDifficulty::Medium),
        "hard" => Some(BotDifficulty::Hard),
        _ => None,
    }
}

pub struct FillAndStartInput {
    /// The user asking: must own the party
    pub user_id: String,
    pub party_id: String,
    pub difficulty: BotDifficulty,
}

/// A bot seated by the fill, and where
pub struct SeatedBot {
    pub bot: User,
    pub player_index: u8,
}

pub struct FillAndStartOutput {
    pub seated: Vec<SeatedBot>,
    pub started: StartPartyOutput,
}

/// The owner of a waiting party fills every free seat with distinct bots of one level
/// (the next levels when it runs out, `fill_order`), then starts the party: one call
/// instead of one add-bot per seat and a start.
///
/// Every refusal the request can meet (owner, state, not enough bots) is checked before
/// a seat is taken. A start that still fails afterwards gives the seats back while the
/// party is waiting, so a failed call leaves the lobby as it found it.
pub struct FillAndStart<U: UserRepository, P: PartyRepository> {
    user_repo: Arc<U>,
    party_repo: Arc<P>,
}

impl<U: UserRepository, P: PartyRepository> FillAndStart<U, P> {
    pub fn new(user_repo: Arc<U>, party_repo: Arc<P>) -> Self {
        Self {
            user_repo,
            party_repo,
        }
    }

    pub async fn execute(
        &self,
        input: FillAndStartInput,
    ) -> Result<FillAndStartOutput, FillAndStartError> {
        let party = self
            .party_repo
            .find_by_id(&input.party_id)
            .await?
            .ok_or(FillAndStartError::PartyNotFound)?;
        if party.owner_id != input.user_id {
            return Err(FillAndStartError::NotOwner);
        }
        if party.status != PartyStatus::Waiting {
            return Err(FillAndStartError::PartyNotWaiting);
        }

        let players = self.party_repo.get_party_players(&party.id).await?;
        let free = (party.settings.player_count as usize).saturating_sub(players.len());
        let bots = self.pick_bots(input.difficulty, free, &players).await?;
        if bots.len() < free {
            return Err(FillAndStartError::NotEnoughBots {
                free,
                available: bots.len(),
            });
        }

        let mut seated = Vec::with_capacity(bots.len());
        for bot in bots {
            match seat_player(&*self.party_repo, &party, &bot.id).await {
                Ok(Seating::Seated(player_index)) => seated.push(SeatedBot { bot, player_index }),
                // A human took the last seat meanwhile: the table is full all the same
                Ok(Seating::Full) => break,
                // A concurrent fill seated this bot first
                Ok(Seating::AlreadyIn) => continue,
                Err(e) => {
                    self.give_back(&party.id, &seated).await;
                    return Err(e.into());
                }
            }
        }

        let start = StartParty::new(self.party_repo.clone());
        match start
            .execute(StartPartyInput {
                user_id: input.user_id,
                party_id: party.id.clone(),
            })
            .await
        {
            Ok(started) => Ok(FillAndStartOutput { seated, started }),
            Err(e) => {
                self.give_back(&party.id, &seated).await;
                Err(e.into())
            }
        }
    }

    /// Up to `count` bots not seated at the table, in `fill_order`, each level's by name
    async fn pick_bots(
        &self,
        difficulty: BotDifficulty,
        count: usize,
        players: &[PartyPlayer],
    ) -> Result<Vec<User>, RepositoryError> {
        let mut picked: Vec<User> = Vec::with_capacity(count);
        for level in fill_order(difficulty) {
            if picked.len() == count {
                break;
            }
            let mut bots = self.user_repo.find_all_bots(Some(level)).await?;
            bots.sort_by(|a, b| a.username.cmp(&b.username));
            for bot in bots {
                if picked.len() == count {
                    break;
                }
                if !players.iter().any(|p| p.user_id == bot.id) {
                    picked.push(bot);
                }
            }
        }
        Ok(picked)
    }

    /// Unseat the bots this call seated, unless the party has started meanwhile (a
    /// concurrent start may have dealt them in: they are players now)
    async fn give_back(&self, party_id: &str, seated: &[SeatedBot]) {
        if seated.is_empty() {
            return;
        }
        match self.party_repo.find_by_id(party_id).await {
            Ok(Some(party)) if party.status == PartyStatus::Waiting => {}
            _ => return,
        }
        for seat in seated {
            if let Err(e) = self
                .party_repo
                .remove_party_player(party_id, &seat.bot.id)
                .await
            {
                tracing::warn!(party_id, bot_id = %seat.bot.id, error = %e,
                    "fill-and-start: a bot seated before a failed start stays seated");
            }
        }
    }
}

#[derive(Debug, thiserror::Error)]
pub enum FillAndStartError {
    #[error("Party not found")]
    PartyNotFound,
    #[error("Not the party owner")]
    NotOwner,
    #[error("Party is not in waiting state")]
    PartyNotWaiting,
    #[error("Not enough bots: {free} free seats, {available} bots available")]
    NotEnoughBots { free: usize, available: usize },
    #[error(transparent)]
    Start(#[from] StartPartyError),
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn fill_order_goes_up_then_down() {
        use BotDifficulty::*;
        assert_eq!(
            fill_order(Easy),
            vec![Easy, Medium, Hard, HardVince, Thibot]
        );
        assert_eq!(
            fill_order(Medium),
            vec![Medium, Hard, HardVince, Thibot, Easy]
        );
        assert_eq!(
            fill_order(Hard),
            vec![Hard, HardVince, Thibot, Medium, Easy]
        );
    }

    #[test]
    fn only_the_three_offered_levels_are_asked_for() {
        assert_eq!(parse_fill_difficulty("easy"), Some(BotDifficulty::Easy));
        assert_eq!(parse_fill_difficulty("hard"), Some(BotDifficulty::Hard));
        for other in ["thibot", "llm", "Hard", ""] {
            assert_eq!(parse_fill_difficulty(other), None, "{other}");
        }
    }
}
