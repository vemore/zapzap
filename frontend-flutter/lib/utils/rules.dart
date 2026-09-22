import '../models/card.dart';

/// The play rules of `GAME_RULES.md` (Valid Card Combinations, ZapZap
/// Eligibility), ported from `frontend/src/utils/validation.js` and
/// `scoring.js`. Cards are ids, as the API sends them.

enum PlayType { single, sameRank, sequence, invalid }

/// Why a play is refused; the UI maps it to a localised message
/// (`playErrorMessage` in `utils/card_l10n.dart`).
enum PlayError {
  empty,
  unknownCard,
  duplicateCard,
  mixedSuits,
  sequenceTooShort,
  notConsecutive,
}

class PlayAnalysis {
  const PlayAnalysis.valid(this.type) : error = null;
  const PlayAnalysis.invalid(PlayError this.error) : type = PlayType.invalid;

  final PlayType type;
  final PlayError? error;

  bool get isValid => error == null;
}

/// The shortest sequence (`GAME_RULES.md`: "Same Suit, 3+ consecutive").
const minSequenceLength = 3;

/// A hand at or under this many points (jokers 0) may call ZapZap.
const zapZapThreshold = 5;

bool isValidPlay(List<int> cards) => analyzePlay(cards).isValid;

PlayType playType(List<int> cards) => analyzePlay(cards).type;

/// Classifies [cards] as a play: a single card; a same-rank group of 2 or more
/// (jokers wild, all-joker groups included, as the backend accepts); or a
/// sequence of 3 or more of one suit, jokers filling the gaps, Ace low only
/// (no K-A wrap).
PlayAnalysis analyzePlay(List<int> cards) {
  if (cards.isEmpty) return const PlayAnalysis.invalid(PlayError.empty);
  if (!cards.every(GameCard.isValidId)) {
    return const PlayAnalysis.invalid(PlayError.unknownCard);
  }
  // Each card exists once: a repeated id is not a pair of it.
  if (cards.toSet().length != cards.length) {
    return const PlayAnalysis.invalid(PlayError.duplicateCard);
  }
  if (cards.length == 1) return const PlayAnalysis.valid(PlayType.single);

  final regulars = cards.map(GameCard.new).where((c) => !c.isJoker).toList();
  final jokers = cards.length - regulars.length;

  if (regulars.map((c) => c.rank).toSet().length <= 1) {
    return const PlayAnalysis.valid(PlayType.sameRank);
  }
  if (regulars.map((c) => c.suit).toSet().length > 1) {
    return const PlayAnalysis.invalid(PlayError.mixedSuits);
  }
  if (cards.length < minSequenceLength) {
    return const PlayAnalysis.invalid(PlayError.sequenceTooShort);
  }
  // One suit, so every rank is distinct: the gaps are what jokers must fill,
  // and the whole run must fit between Ace and King.
  final ranks = regulars.map((c) => c.rank).toList()..sort();
  final gaps = ranks.last - ranks.first + 1 - ranks.length;
  if (gaps > jokers || cards.length > 13) {
    return const PlayAnalysis.invalid(PlayError.notConsecutive);
  }
  return const PlayAnalysis.valid(PlayType.sequence);
}

/// The points of [hand]: jokers 0, or 25 when [penalty] is set.
int handValue(Iterable<int> hand, {bool penalty = false}) =>
    hand.fold(0, (sum, id) => sum + GameCard(id).value(penalty: penalty));

/// Whether [hand] may call ZapZap: 5 points or less, jokers counted 0.
bool isZapZapEligible(Iterable<int> hand) => handValue(hand) <= zapZapThreshold;

/// The two values shown for a hand: for eligibility (jokers 0) and for
/// scoring (jokers 25).
({int eligibility, int penalty}) handValueDisplay(Iterable<int> hand) =>
    (eligibility: handValue(hand), penalty: handValue(hand, penalty: true));

/// [cards] by suit then rank, jokers last (`sortCards` in `cards.js`).
List<int> sortCards(Iterable<int> cards) => cards.toList()..sort();
