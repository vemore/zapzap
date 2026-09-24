use crate::domain::entities::{lowest_free_seat, Party};
use crate::domain::repositories::{PartyRepository, RepositoryError};
use crate::domain::value_objects::MAX_PLAYER_COUNT;

/// Where seating a player in a waiting party ended
#[derive(Debug, PartialEq, Eq)]
pub(crate) enum Seating {
    Seated(u8),
    /// Every seat of `settings.playerCount` is taken
    Full,
    /// The user is already in the party (a concurrent join of the same user won)
    AlreadyIn,
}

/// Seat `user_id` on the lowest free seat, not `players.len()`: a leave can leave a gap.
/// A concurrent join can take that seat first (UNIQUE(party_id, player_index)): then
/// the seats are read again and the next free one is tried. Each lost race means one
/// more seat taken, so the party is `Full` after at most `playerCount` of them.
pub(crate) async fn seat_player<P: PartyRepository>(
    party_repo: &P,
    party: &Party,
    user_id: &str,
) -> Result<Seating, RepositoryError> {
    for _ in 0..=MAX_PLAYER_COUNT {
        let players = party_repo.get_party_players(&party.id).await?;
        if players.iter().any(|p| p.user_id == user_id) {
            return Ok(Seating::AlreadyIn);
        }
        if party.is_full(players.len()) {
            return Ok(Seating::Full);
        }
        let seat = lowest_free_seat(&players);
        match party_repo.add_party_player(&party.id, user_id, seat).await {
            Ok(()) => return Ok(Seating::Seated(seat)),
            Err(RepositoryError::AlreadyExists(_)) => return Ok(Seating::AlreadyIn),
            Err(e) if e.is_seat_conflict() => continue,
            Err(e) => return Err(e),
        }
    }
    // Every seat was lost to a concurrent join
    Ok(Seating::Full)
}
