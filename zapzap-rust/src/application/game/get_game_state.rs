use std::sync::Arc;

use crate::domain::entities::{Party, Round, User};
use crate::domain::repositories::{PartyRepository, RepositoryError, UserRepository};

/// Get game state input
pub struct GetGameStateInput {
    pub party_id: String,
    pub user_id: String,
}

/// Player info for game state
#[derive(Debug, Clone)]
pub struct GamePlayerInfo {
    pub user: User,
    pub player_index: u8,
    pub hand_size: usize,
    pub score: u16,
    pub is_eliminated: bool,
}

/// Get game state output
pub struct GetGameStateOutput {
    pub party: Party,
    pub round: Option<Round>,
    pub players: Vec<GamePlayerInfo>,
    pub game_state: Option<GameStateView>,
    pub player_index: Option<u8>,
}

/// Winner info for game end
#[derive(Debug, Clone)]
pub struct WinnerInfoView {
    pub user_id: String,
    pub player_index: u8,
    pub username: String,
    pub score: u16,
}

/// Game state view (what the player can see)
#[derive(Debug, Clone)]
pub struct GameStateView {
    pub deck_size: usize,
    pub my_hand: Vec<u8>,
    pub last_cards_played: Vec<u8>,
    pub cards_played: Vec<u8>,
    pub current_turn: u8,
    pub current_action: String,
    pub round_number: u16,
    pub is_golden_score: bool,
    pub scores: Vec<u16>,
    pub hand_sizes: Vec<usize>,
    pub starting_player: u8,
    pub last_action: Option<serde_json::Value>,
    // Round end data (populated when currentAction == "finished")
    pub all_hands: Option<std::collections::HashMap<String, Vec<u8>>>,
    pub hand_points: Option<std::collections::HashMap<String, u16>>,
    pub zapzap_caller: Option<u8>,
    pub lowest_hand_player_index: Option<u8>,
    pub was_counter_acted: Option<bool>,
    pub counter_acted_by_player_index: Option<u8>,
    pub round_scores: Option<std::collections::HashMap<String, u16>>,
    // Game end data
    pub game_finished: Option<bool>,
    pub winner: Option<WinnerInfoView>,
}

/// Get game state use case
pub struct GetGameState<U: UserRepository, P: PartyRepository> {
    user_repo: Arc<U>,
    party_repo: Arc<P>,
}

impl<U: UserRepository, P: PartyRepository> GetGameState<U, P> {
    pub fn new(user_repo: Arc<U>, party_repo: Arc<P>) -> Self {
        Self {
            user_repo,
            party_repo,
        }
    }

    pub async fn execute(
        &self,
        input: GetGameStateInput,
    ) -> Result<GetGameStateOutput, GetGameStateError> {
        // Find party
        let party = self
            .party_repo
            .find_by_id(&input.party_id)
            .await?
            .ok_or(GetGameStateError::PartyNotFound)?;

        // Get player index
        let player_index = self
            .party_repo
            .get_player_index(&input.party_id, &input.user_id)
            .await?;

        // Get players
        let party_players = self.party_repo.get_party_players(&input.party_id).await?;

        // Get current round
        let round = self.party_repo.get_current_round(&input.party_id).await?;

        // Get game state
        let game_state = self.party_repo.get_game_state(&input.party_id).await?;

        // Batch fetch all users (avoids N+1 queries)
        let user_ids: Vec<String> = party_players.iter().map(|pp| pp.user_id.clone()).collect();
        let users = self.user_repo.find_by_ids(&user_ids).await?;
        let users_map: std::collections::HashMap<String, _> = users
            .into_iter()
            .map(|u| (u.id.clone(), u))
            .collect();

        // Build player info
        let mut players = Vec::with_capacity(party_players.len());
        for pp in &party_players {
            if let Some(user) = users_map.get(&pp.user_id).cloned() {
                let (hand_size, score, is_eliminated) = match &game_state {
                    Some(gs) => (
                        gs.get_hand(pp.player_index).len(),
                        gs.get_score(pp.player_index),
                        gs.is_eliminated(pp.player_index),
                    ),
                    None => (0, 0, false),
                };

                players.push(GamePlayerInfo {
                    user,
                    player_index: pp.player_index,
                    hand_size,
                    score,
                    is_eliminated,
                });
            }
        }

        // Sort by player index
        players.sort_by_key(|p| p.player_index);

        // Check if game is finished
        let is_game_finished = party.status == crate::domain::entities::PartyStatus::Finished;

        // Build game state view
        let game_state_view = game_state.map(|gs| {
            let my_hand = player_index
                .map(|idx| gs.get_hand(idx).to_vec())
                .unwrap_or_default();

            let hand_sizes: Vec<usize> = (0..gs.player_count)
                .map(|i| gs.get_hand(i).len())
                .collect();

            let scores: Vec<u16> = (0..gs.player_count)
                .map(|i| gs.get_score(i))
                .collect();

            // Get cards_played from game state
            let cards_played = gs.cards_played.to_vec();

            // Get starting_player from game state
            let starting_player = gs.starting_player;

            // Get last_action from game state as JSON
            let last_action = gs.get_last_action_json();

            // Build round_scores HashMap if available
            let round_scores_map = gs.round_scores.map(|scores| {
                let mut map = std::collections::HashMap::new();
                for i in 0..gs.player_count as usize {
                    map.insert(i.to_string(), scores[i]);
                }
                map
            });

            // Build all_hands HashMap (all player hands revealed at round end)
            let all_hands_map = if gs.current_action == crate::domain::value_objects::GameAction::Finished {
                let mut map = std::collections::HashMap::new();
                for i in 0..gs.player_count as usize {
                    map.insert(i.to_string(), gs.hands[i].to_vec());
                }
                Some(map)
            } else {
                None
            };

            // Build hand_points HashMap (hand value for each player at round end)
            let hand_points_map = if gs.current_action == crate::domain::value_objects::GameAction::Finished {
                let mut map = std::collections::HashMap::new();
                for i in 0..gs.player_count as usize {
                    let hand = &gs.hands[i];
                    let hand_value = crate::infrastructure::bot::card_analyzer::calculate_hand_score(hand, false);
                    map.insert(i.to_string(), hand_value);
                }
                Some(map)
            } else {
                None
            };

            // Determine winner if game is finished
            let (game_finished, winner) = if is_game_finished {
                // Find the winner (player with score <= 100 in golden score, or lowest score)
                let winner_info = if gs.is_golden_score {
                    // In golden score, winner is the player with lowest hand who called zapzap successfully
                    // or the only player still <= 100
                    let surviving: Vec<_> = scores.iter().enumerate()
                        .filter(|(_, &score)| score <= 100)
                        .collect();

                    if surviving.len() == 1 {
                        let (winner_idx, &winner_score) = surviving[0];
                        let winner_user = players.iter().find(|p| p.player_index == winner_idx as u8);
                        winner_user.map(|w| WinnerInfoView {
                            user_id: w.user.id.clone(),
                            player_index: winner_idx as u8,
                            username: w.user.username.clone(),
                            score: winner_score,
                        })
                    } else if let Some(lowest_idx) = gs.lowest_hand_player_index {
                        // Winner is the one with lowest hand
                        let winner_user = players.iter().find(|p| p.player_index == lowest_idx);
                        winner_user.map(|w| WinnerInfoView {
                            user_id: w.user.id.clone(),
                            player_index: lowest_idx,
                            username: w.user.username.clone(),
                            score: gs.get_score(lowest_idx),
                        })
                    } else {
                        None
                    }
                } else {
                    // Normal game end - find player with lowest score
                    let (winner_idx, &winner_score) = scores.iter().enumerate()
                        .min_by_key(|(_, &score)| score)
                        .unwrap_or((0, &0));
                    let winner_user = players.iter().find(|p| p.player_index == winner_idx as u8);
                    winner_user.map(|w| WinnerInfoView {
                        user_id: w.user.id.clone(),
                        player_index: winner_idx as u8,
                        username: w.user.username.clone(),
                        score: winner_score,
                    })
                };
                (Some(true), winner_info)
            } else {
                (None, None)
            };

            GameStateView {
                deck_size: gs.deck_size(),
                my_hand,
                last_cards_played: gs.last_cards_played.to_vec(),
                cards_played,
                current_turn: gs.current_turn,
                current_action: gs.current_action.as_str().to_string(),
                round_number: gs.round_number,
                is_golden_score: gs.is_golden_score,
                scores,
                hand_sizes,
                starting_player,
                last_action,
                // Round end data
                all_hands: all_hands_map,
                hand_points: hand_points_map,
                zapzap_caller: gs.zapzap_caller,
                lowest_hand_player_index: gs.lowest_hand_player_index,
                was_counter_acted: gs.was_counter_acted,
                counter_acted_by_player_index: gs.counter_acted_by_player_index,
                round_scores: round_scores_map,
                game_finished,
                winner,
            }
        });

        Ok(GetGameStateOutput {
            party,
            round,
            players,
            game_state: game_state_view,
            player_index,
        })
    }
}

#[derive(Debug, thiserror::Error)]
pub enum GetGameStateError {
    #[error("Party not found")]
    PartyNotFound,
    #[error("Repository error: {0}")]
    Repository(#[from] RepositoryError),
}
