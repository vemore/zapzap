//! The results of a finished game: the final ranking and what `save_game_results` writes.
//! One builder for the three ways a game ends — a zapzap (`call_zapzap.rs`), the
//! `nextRound` recovery of a zapzap stopped half-way (`next_round.rs`) and a forfeit that
//! leaves one seat (`user_repo.rs`).

use std::collections::HashMap;

use crate::domain::repositories::PlayerGameResult;
use crate::domain::value_objects::GameState;

/// A finished game's results, the winner's first and then in finish order
#[derive(Debug, Clone)]
pub struct GameResults {
    pub winner_user_id: String,
    pub winner_score: u16,
    pub total_rounds: u32,
    pub was_golden_score: bool,
    pub players: Vec<PlayerGameResult>,
}

/// One seat as the ranking sees it
struct RankedSeat {
    player_index: u8,
    user_id: String,
    score: u16,
    eliminated_in: Option<u32>,
}

/// Build the results of the game `state` ended, won by seat `winner`. `seats` are the
/// party's `(player index, user id)`; `recorded_eliminations` maps a user id to the first
/// round its `round_scores` rows mark it eliminated in (`elimination_order`). A seat the
/// state holds eliminated with no such round recorded (a forfeit, or a zapzap stopped
/// before its round scores were saved) counts as eliminated in the current round.
///
/// The final ranking (GAME_RULES.md "Final Ranking"): the winner first; then the seats
/// still in the game, lower total score first; then the eliminated seats, the later
/// eliminated first. Seats left level (same score, or out in the same round, a forfeit
/// and a score past 100 alike) rank by seat index.
pub fn build_game_results(
    state: &GameState,
    seats: impl IntoIterator<Item = (u8, String)>,
    recorded_eliminations: &[(String, Option<u32>)],
    winner: u8,
) -> GameResults {
    let total_rounds = u32::from(state.round_number);
    let recorded: HashMap<&str, Option<u32>> = recorded_eliminations
        .iter()
        .map(|(user_id, round)| (user_id.as_str(), *round))
        .collect();
    let mut ranking: Vec<RankedSeat> = seats
        .into_iter()
        .map(|(player_index, user_id)| {
            let eliminated_in = recorded
                .get(user_id.as_str())
                .copied()
                .flatten()
                .or(state.is_eliminated(player_index).then_some(total_rounds));
            RankedSeat {
                player_index,
                score: state.get_score(player_index),
                user_id,
                eliminated_in,
            }
        })
        .collect();
    ranking.sort_by_key(|seat| {
        let (group, order) = match seat.eliminated_in {
            _ if seat.player_index == winner => (0, 0),
            None => (1, u32::from(seat.score)),
            Some(round) => (2, u32::MAX - round),
        };
        (group, order, seat.player_index)
    });

    let winner_user_id = ranking
        .iter()
        .find(|seat| seat.player_index == winner)
        .map(|seat| seat.user_id.clone())
        .unwrap_or_default();
    let players = ranking
        .into_iter()
        .enumerate()
        .map(|(position, seat)| PlayerGameResult {
            is_winner: seat.player_index == winner,
            user_id: seat.user_id,
            final_score: seat.score,
            finish_position: (position + 1) as u8,
            rounds_played: total_rounds,
        })
        .collect();
    GameResults {
        winner_user_id,
        winner_score: state.get_score(winner),
        total_rounds,
        was_golden_score: state.is_golden_score,
        players,
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    /// A state at `round`, one seat per score, the seats of `eliminated` out
    fn state(scores: &[u16], eliminated: &[u8], round: u16) -> GameState {
        let mut state = GameState::new(scores.len() as u8);
        state.scores[..scores.len()].copy_from_slice(scores);
        for &seat in eliminated {
            state.eliminate_player(seat);
        }
        state.round_number = round;
        state
    }

    fn seats(order: &[u8]) -> Vec<(u8, String)> {
        order.iter().map(|&i| (i, format!("u{i}"))).collect()
    }

    fn positions(results: &GameResults) -> Vec<(String, u8)> {
        results
            .players
            .iter()
            .map(|p| (p.user_id.clone(), p.finish_position))
            .collect()
    }

    #[test]
    fn test_final_ranking_winner_then_survivors_then_later_eliminated() {
        let state = state(&[120, 40, 110, 20, 30], &[0, 2], 5);
        let recorded = [
            ("u0".to_string(), Some(2)),
            ("u1".to_string(), None),
            ("u2".to_string(), Some(4)),
            ("u3".to_string(), None),
            ("u4".to_string(), None),
        ];
        let results = build_game_results(&state, seats(&[0, 1, 2, 3, 4]), &recorded, 4);
        let order: Vec<&str> = results.players.iter().map(|p| p.user_id.as_str()).collect();
        assert_eq!(order, ["u4", "u3", "u1", "u2", "u0"]);
        assert_eq!(results.winner_user_id, "u4");
        assert_eq!(results.winner_score, 30);
        assert_eq!(results.total_rounds, 5);
        assert!(results.players[0].is_winner);
        assert!(results.players[1..].iter().all(|p| !p.is_winner));
        assert!(results.players.iter().all(|p| p.rounds_played == 5));
        let finals: Vec<u16> = results.players.iter().map(|p| p.final_score).collect();
        assert_eq!(finals, [30, 20, 40, 110, 120]);
    }

    #[test]
    fn test_a_forfeit_and_a_score_elimination_in_the_same_round_rank_by_seat() {
        // Round 3: seat 1 went past 100 at the round's end (recorded), then seat 2
        // forfeited (nothing recorded: the current round). Level on the round, they rank
        // by seat, whatever order the seats are read in and whatever their scores.
        let state = state(&[40, 130, 60], &[1, 2], 3);
        let recorded = [
            ("u0".to_string(), None),
            ("u1".to_string(), Some(3)),
            ("u2".to_string(), None),
        ];
        for order in [[0, 1, 2], [2, 1, 0], [1, 2, 0]] {
            let results = build_game_results(&state, seats(&order), &recorded, 0);
            assert_eq!(
                positions(&results),
                [("u0".into(), 1), ("u1".into(), 2), ("u2".into(), 3)],
                "seats read as {order:?}"
            );
        }

        // The forfeit at the lower seat: it ranks first of the two
        let state = self::state(&[40, 60, 130], &[1, 2], 3);
        let recorded = [
            ("u0".to_string(), None),
            ("u1".to_string(), None),
            ("u2".to_string(), Some(3)),
        ];
        for order in [[0, 1, 2], [2, 1, 0]] {
            let results = build_game_results(&state, seats(&order), &recorded, 0);
            assert_eq!(
                positions(&results),
                [("u0".into(), 1), ("u1".into(), 2), ("u2".into(), 3)],
                "seats read as {order:?}"
            );
        }
    }

    #[test]
    fn test_a_forfeit_ranks_above_seats_eliminated_in_earlier_rounds() {
        // Seat 3 was out in round 2; seat 1 forfeits in round 4
        let state = state(&[50, 70, 20, 115], &[1, 3], 4);
        let recorded = [("u3".to_string(), Some(2))];
        let results = build_game_results(&state, seats(&[3, 2, 1, 0]), &recorded, 2);
        assert_eq!(
            positions(&results),
            [
                ("u2".into(), 1),
                ("u0".into(), 2),
                ("u1".into(), 3),
                ("u3".into(), 4)
            ]
        );
    }

    #[test]
    fn test_level_survivors_rank_by_seat() {
        let state = state(&[30, 30, 10, 30], &[], 2);
        let results = build_game_results(&state, seats(&[3, 1, 0, 2]), &[], 2);
        let order: Vec<&str> = results.players.iter().map(|p| p.user_id.as_str()).collect();
        assert_eq!(order, ["u2", "u0", "u1", "u3"]);
    }

    #[test]
    fn test_a_recorded_elimination_round_wins_over_the_current_round() {
        // Seat 1 was out in round 1 and seat 2 in round 3: the state holds both
        // eliminated, the recorded rounds say which went first
        let state = state(&[10, 105, 101], &[1, 2], 3);
        let recorded = [("u1".to_string(), Some(1)), ("u2".to_string(), Some(3))];
        let results = build_game_results(&state, seats(&[0, 1, 2]), &recorded, 0);
        let order: Vec<&str> = results.players.iter().map(|p| p.user_id.as_str()).collect();
        assert_eq!(order, ["u0", "u2", "u1"]);
    }
}
