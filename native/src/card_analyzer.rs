//! CardAnalyzer - High-performance card analysis for ZapZap
//!
//! Optimized Rust implementation of card hand analysis.
//! Uses u8 for card IDs (0-53) and fixed-size arrays where possible.

use smallvec::SmallVec;

/// Card ID range
pub const JOKER_START: u8 = 52;

/// Pre-computed card points lookup table
const CARD_POINTS: [u8; 13] = [1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13];

/// Get card points for zapzap calculation
/// Jokers (52-53) = 0 points
#[inline(always)]
pub fn get_card_points(card_id: u8) -> u8 {
    if card_id >= JOKER_START {
        return 0;
    }
    let rank = card_id % 13;
    CARD_POINTS[rank as usize]
}

/// Get card rank (0-12), returns 255 for jokers
#[inline(always)]
pub fn get_rank(card_id: u8) -> u8 {
    if card_id >= JOKER_START {
        return 255;
    }
    card_id % 13
}

/// Get card suit (0-3), returns 255 for jokers
#[inline(always)]
pub fn get_suit(card_id: u8) -> u8 {
    if card_id >= JOKER_START {
        return 255;
    }
    card_id / 13
}

/// Check if card is a joker
#[inline(always)]
pub fn is_joker(card_id: u8) -> bool {
    card_id >= JOKER_START
}

/// Calculate total hand value (for zapzap eligibility)
/// Jokers count as 0 points
#[inline]
pub fn calculate_hand_value(hand: &[u8]) -> u16 {
    hand.iter().map(|&c| get_card_points(c) as u16).sum()
}

/// Calculate hand score for end of round
/// Jokers = 0 if lowest hand, 25 otherwise
pub fn calculate_hand_score(hand: &[u8], is_lowest: bool) -> u16 {
    hand.iter()
        .map(|&c| {
            if is_joker(c) {
                if is_lowest { 0 } else { 25 }
            } else {
                get_card_points(c) as u16
            }
        })
        .sum()
}

/// Check if player can call ZapZap (hand value <= 5)
#[inline]
pub fn can_call_zapzap(hand: &[u8]) -> bool {
    calculate_hand_value(hand) <= 5
}

/// Check if cards form a valid same-rank combination (pairs/sets)
pub fn is_valid_same_rank(cards: &[u8]) -> bool {
    if cards.len() < 2 {
        return false;
    }

    let mut target_rank: Option<u8> = None;

    for &card in cards {
        if !is_joker(card) {
            let rank = get_rank(card);
            match target_rank {
                None => target_rank = Some(rank),
                Some(r) if r != rank => return false,
                _ => {}
            }
        }
    }

    true // All jokers or all same rank
}

/// Check if cards form a valid sequence (run in same suit)
pub fn is_valid_sequence(cards: &[u8]) -> bool {
    if cards.len() < 3 {
        return false;
    }

    let mut normal_cards: SmallVec<[u8; 10]> = SmallVec::new();
    let mut joker_count = 0;
    let mut target_suit: Option<u8> = None;

    for &card in cards {
        if is_joker(card) {
            joker_count += 1;
        } else {
            let suit = get_suit(card);
            match target_suit {
                None => target_suit = Some(suit),
                Some(s) if s != suit => return false,
                _ => {}
            }
            normal_cards.push(get_rank(card));
        }
    }

    // All jokers is valid
    if normal_cards.is_empty() {
        return true;
    }

    // Sort ranks
    normal_cards.sort_unstable();

    // Calculate gaps needed
    let mut gaps_needed = 0;
    for i in 1..normal_cards.len() {
        let diff = normal_cards[i] as i16 - normal_cards[i - 1] as i16 - 1;
        if diff > 0 {
            gaps_needed += diff as usize;
        }
    }

    gaps_needed <= joker_count
}

/// Check if a play is valid
pub fn is_valid_play(cards: &[u8]) -> bool {
    match cards.len() {
        0 => false,
        1 => true,
        _ => is_valid_same_rank(cards) || is_valid_sequence(cards),
    }
}

/// Find all valid same-rank plays in hand
/// Returns a vector of plays, each play is a SmallVec of card IDs
pub fn find_same_rank_plays(hand: &[u8]) -> Vec<SmallVec<[u8; 8]>> {
    if hand.len() < 2 {
        return Vec::new();
    }

    let mut plays = Vec::with_capacity(20);

    // Collect jokers
    let jokers: SmallVec<[u8; 2]> = hand.iter()
        .filter(|&&c| is_joker(c))
        .copied()
        .collect();

    // Group cards by rank (13 possible ranks)
    let mut by_rank: [SmallVec<[u8; 4]>; 13] = Default::default();

    for &card in hand {
        if !is_joker(card) {
            let rank = get_rank(card) as usize;
            by_rank[rank].push(card);
        }
    }

    // Generate plays for each rank
    for cards in &by_rank {
        if cards.len() >= 2 {
            // Pure pairs/sets
            plays.push(cards.clone().into_iter().collect());

            // With jokers (up to 4 cards total)
            for j in 1..=jokers.len().min(4 - cards.len()) {
                let mut play: SmallVec<[u8; 8]> = cards.iter().copied().collect();
                play.extend(jokers.iter().take(j).copied());
                plays.push(play);
            }
        } else if cards.len() == 1 && !jokers.is_empty() {
            // Single card + jokers
            for j in 1..=jokers.len() {
                let mut play: SmallVec<[u8; 8]> = SmallVec::new();
                play.push(cards[0]);
                play.extend(jokers.iter().take(j).copied());
                plays.push(play);
            }
        }
    }

    plays
}

/// Find all valid sequence plays in hand
pub fn find_sequence_plays(hand: &[u8]) -> Vec<SmallVec<[u8; 8]>> {
    if hand.len() < 3 {
        return Vec::new();
    }

    let mut plays = Vec::with_capacity(20);

    // Collect jokers
    let jokers: SmallVec<[u8; 2]> = hand.iter()
        .filter(|&&c| is_joker(c))
        .copied()
        .collect();

    // Group cards by suit (4 possible suits)
    let mut by_suit: [SmallVec<[u8; 13]>; 4] = Default::default();

    for &card in hand {
        if !is_joker(card) {
            let suit = get_suit(card) as usize;
            by_suit[suit].push(card);
        }
    }

    // Find sequences in each suit
    for cards in &mut by_suit {
        if cards.len() + jokers.len() < 3 {
            continue;
        }

        // Sort by rank
        cards.sort_unstable_by_key(|&c| get_rank(c));

        // Try all subsequences of length >= 3
        for start in 0..cards.len() {
            for end in (start + 3)..=cards.len() {
                let subset = &cards[start..end];

                // Calculate gaps needed
                let mut gaps_needed = 0;
                for i in 1..subset.len() {
                    let diff = get_rank(subset[i]) as i16 - get_rank(subset[i - 1]) as i16 - 1;
                    if diff > 0 {
                        gaps_needed += diff as usize;
                    }
                }

                // Valid if we have enough jokers
                if gaps_needed <= jokers.len() {
                    if gaps_needed == 0 {
                        // No jokers needed
                        plays.push(subset.iter().copied().collect());
                    } else {
                        // Add with exact jokers needed
                        let mut play: SmallVec<[u8; 8]> = subset.iter().copied().collect();
                        play.extend(jokers.iter().take(gaps_needed).copied());
                        plays.push(play);
                    }
                }
            }
        }
    }

    plays
}

/// Find all valid plays in hand (main entry point)
pub fn find_all_valid_plays(hand: &[u8]) -> Vec<SmallVec<[u8; 8]>> {
    if hand.is_empty() {
        return Vec::new();
    }

    let mut plays = Vec::with_capacity(hand.len() + 40);

    // Single cards
    for &card in hand {
        let mut play: SmallVec<[u8; 8]> = SmallVec::new();
        play.push(card);
        plays.push(play);
    }

    // Same rank plays
    plays.extend(find_same_rank_plays(hand));

    // Sequence plays
    plays.extend(find_sequence_plays(hand));

    plays
}

/// Find the play that removes the most points from hand
pub fn find_max_point_play(hand: &[u8]) -> Option<SmallVec<[u8; 8]>> {
    let plays = find_all_valid_plays(hand);

    plays.into_iter()
        .max_by_key(|play| {
            play.iter().map(|&c| get_card_points(c) as u32).sum::<u32>()
        })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_get_card_points() {
        assert_eq!(get_card_points(0), 1);   // Ace of Spades
        assert_eq!(get_card_points(1), 2);   // 2 of Spades
        assert_eq!(get_card_points(9), 10);  // 10 of Spades
        assert_eq!(get_card_points(10), 11); // Jack of Spades
        assert_eq!(get_card_points(11), 12); // Queen of Spades
        assert_eq!(get_card_points(12), 13); // King of Spades
        assert_eq!(get_card_points(52), 0);  // Joker
        assert_eq!(get_card_points(53), 0);  // Joker
    }

    #[test]
    fn test_calculate_hand_value() {
        assert_eq!(calculate_hand_value(&[0, 1, 2]), 6); // A + 2 + 3
        assert_eq!(calculate_hand_value(&[0, 52]), 1);   // A + Joker
        assert_eq!(calculate_hand_value(&[52, 53]), 0);  // Two jokers
    }

    #[test]
    fn test_can_call_zapzap() {
        assert!(!can_call_zapzap(&[0, 1, 2]));      // 1+2+3 = 6 > 5, NOT eligible
        assert!(can_call_zapzap(&[0, 1]));          // 1+2 = 3 <= 5
        assert!(can_call_zapzap(&[52, 53, 0]));     // 0+0+1 = 1 <= 5
        assert!(!can_call_zapzap(&[9, 10]));        // 10+11 = 21 > 5
        assert!(can_call_zapzap(&[0, 0, 1]));       // A+A+2 = 1+1+2 = 4 <= 5 (same card IDs for test)
    }

    #[test]
    fn test_is_valid_same_rank() {
        // Pair of aces (0 and 13)
        assert!(is_valid_same_rank(&[0, 13]));
        // Three aces
        assert!(is_valid_same_rank(&[0, 13, 26]));
        // Mixed ranks - invalid
        assert!(!is_valid_same_rank(&[0, 1]));
        // Joker + card
        assert!(is_valid_same_rank(&[0, 52]));
    }

    #[test]
    fn test_is_valid_sequence() {
        // 3-card sequence in spades
        assert!(is_valid_sequence(&[0, 1, 2]));     // A, 2, 3 of spades
        // Not enough cards
        assert!(!is_valid_sequence(&[0, 1]));
        // Different suits - invalid
        assert!(!is_valid_sequence(&[0, 1, 15]));   // A♠, 2♠, 3♥
        // With joker filling gap
        assert!(is_valid_sequence(&[0, 2, 52]));   // A, 3, Joker (fills 2)
    }

    #[test]
    fn test_find_all_valid_plays() {
        let hand = vec![0, 1, 2, 13]; // A♠, 2♠, 3♠, A♥
        let plays = find_all_valid_plays(&hand);

        // Should include:
        // - 4 single cards
        // - Pair of aces [0, 13]
        // - Sequence [0, 1, 2]
        assert!(plays.len() >= 6);

        // Check single cards exist
        assert!(plays.iter().any(|p| p.len() == 1 && p[0] == 0));

        // Check pair exists
        assert!(plays.iter().any(|p| p.len() == 2 && p.contains(&0) && p.contains(&13)));

        // Check sequence exists
        assert!(plays.iter().any(|p| p.len() == 3 && p.contains(&0) && p.contains(&1) && p.contains(&2)));
    }
}
