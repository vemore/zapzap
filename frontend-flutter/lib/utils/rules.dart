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

/// How close a hand worth [value] points (jokers 0) is to calling ZapZap,
/// from 0 to 1: 1 at the threshold or under it, else threshold / value.
double zapZapProgress(int value) =>
    value <= zapZapThreshold ? 1 : zapZapThreshold / value;

/// Whether [hand] holds a joker: its two values then differ, 0 for ZapZap
/// and 25 for the score.
bool hasJoker(Iterable<int> hand) => hand.any((id) => GameCard(id).isJoker);

/// What a counteracted ZapZap adds to the caller's hand (`GAME_RULES.md`,
/// Final Scoring): 5 points for every other player still in the game.
int counteractPenalty(int activePlayers) =>
    activePlayers <= 1 ? 0 : (activePlayers - 1) * 5;

/// The two values shown for a hand: for eligibility (jokers 0) and for
/// scoring (jokers 25).
({int eligibility, int penalty}) handValueDisplay(Iterable<int> hand) =>
    (eligibility: handValue(hand), penalty: handValue(hand, penalty: true));

/// [cards] by suit then rank, jokers last (`sortCards` in `cards.js`).
List<int> sortCards(Iterable<int> cards) => cards.toList()..sort();

/// A play [suggestPlays] offers: its [cards] (ids, in the order they are
/// played) and the points they take off the hand, jokers at 0 — the value
/// ZapZap is decided on.
class PlaySuggestion {
  PlaySuggestion(List<int> cards)
    : cards = List.unmodifiable(cards),
      type = playType(cards),
      points = handValue(cards);

  final List<int> cards;
  final PlayType type;
  final int points;

  /// Whether [selection] holds exactly these cards, in any order.
  bool matches(Iterable<int> selection) {
    final selected = selection.toSet();
    return selected.length == cards.length && selected.containsAll(cards);
  }
}

/// How many suggestions [suggestPlays] returns at most.
const maxSuggestions = 3;

/// The plays of [hand] worth pointing out (J8 of the UX study), the most
/// points first, at most [limit]: each rank held twice or more, the best
/// sequence of each suit — jokers filling its gaps, the run a beginner
/// misses — and the single cards in neither. A joker alone, or with one
/// card, takes no point off and is not offered. Every suggestion is a legal
/// play by [analyzePlay], the function that judges the selection.
List<PlaySuggestion> suggestPlays(
  Iterable<int> hand, {
  int limit = maxSuggestions,
}) {
  final cards = hand.where(GameCard.isValidId).toSet().map(GameCard.new);
  final regulars = cards.where((c) => !c.isJoker).toList();
  final jokers = [
    for (final c in cards)
      if (c.isJoker) c.id,
  ];

  final groups = <PlaySuggestion>[];
  final byRank = <int, List<int>>{};
  for (final card in regulars) {
    byRank.putIfAbsent(card.rank, () => []).add(card.id);
  }
  for (final ids in byRank.values) {
    if (ids.length >= 2) groups.add(PlaySuggestion(ids..sort()));
  }
  for (final suit in Suit.values) {
    final run = _bestSequence(
      regulars.where((c) => c.suit == suit).toList(),
      jokers,
    );
    if (run != null) groups.add(run);
  }

  // A single card already in a group is played better with it.
  final grouped = {for (final g in groups) ...g.cards};
  final singles = [
    for (final card in regulars)
      if (!grouped.contains(card.id)) PlaySuggestion([card.id]),
  ];

  final all =
      [...groups, ...singles].where((s) => isValidPlay(s.cards)).toList()
        ..sort((a, b) {
          final byPoints = b.points.compareTo(a.points);
          if (byPoints != 0) return byPoints;
          final bySize = b.cards.length.compareTo(a.cards.length);
          if (bySize != 0) return bySize;
          return a.cards.first.compareTo(b.cards.first);
        });
  return all.take(limit).toList();
}

/// The sequence of [suited] (cards of one suit) worth the most points, with
/// as few of [jokers] as it takes, or `null` when none holds two regular
/// cards. Its cards run from the lowest rank to the highest, a joker in each
/// gap — or at an end, to reach three cards.
PlaySuggestion? _bestSequence(List<GameCard> suited, List<int> jokers) {
  if (suited.length < 2) return null;
  final idOfRank = {for (final c in suited) c.rank: c.id};
  List<int>? best;
  var bestPoints = -1;
  var bestJokers = 0;
  for (var low = 1; low <= 13; low++) {
    for (var high = low + minSequenceLength - 1; high <= 13; high++) {
      final ranks = [for (var r = low; r <= high; r++) r];
      final held = ranks.where(idOfRank.containsKey).toList();
      final gaps = ranks.length - held.length;
      if (held.length < 2 || gaps > jokers.length) continue;
      final points = held.fold(0, (sum, r) => sum + r);
      // Ties go to fewer jokers, then to the higher run: 5♠ 6♠ and a joker
      // read "5–7♠", the joker standing for the card above.
      if (points > bestPoints || (points == bestPoints && gaps <= bestJokers)) {
        var joker = 0;
        best = [for (final r in ranks) idOfRank[r] ?? jokers[joker++]];
        bestPoints = points;
        bestJokers = gaps;
      }
    }
  }
  return best == null ? null : PlaySuggestion(best);
}
