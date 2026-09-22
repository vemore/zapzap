/// The four suits, in the order of the card ids (`id ~/ 13`).
enum Suit { spades, hearts, clubs, diamonds }

/// A ZapZap card, identified as by the backend and the React client
/// (`frontend/src/utils/cards.js`): 0-12 spades, 13-25 hearts, 26-38 clubs,
/// 39-51 diamonds, each from Ace to King; 52 the red joker, 53 the black one.
///
/// Named `GameCard` so it does not clash with Material's `Card`.
class GameCard {
  const GameCard(this.id) : assert(id >= 0 && id < deckSize);

  final int id;

  static const deckSize = 54;
  static const redJoker = 52;
  static const blackJoker = 53;

  /// Every card of the deck, by id.
  static final List<GameCard> deck = List.unmodifiable(
    List.generate(deckSize, GameCard.new),
  );

  /// Whether [id] names a card of the deck.
  static bool isValidId(int id) => id >= 0 && id < deckSize;

  bool get isJoker => id >= redJoker;

  bool get isRedJoker => id == redJoker;

  /// The suit, or null for a joker.
  Suit? get suit => isJoker ? null : Suit.values[id ~/ 13];

  /// Whether the card is printed in red: hearts, diamonds and the red joker.
  bool get isRed => isRedJoker || suit == Suit.hearts || suit == Suit.diamonds;

  /// The rank for sequences: Ace 1 .. King 13; 0 for a joker.
  int get rank => isJoker ? 0 : id % 13 + 1;

  /// The index symbol printed on the card (`A`, `2`..`10`, `J`, `Q`, `K`),
  /// empty for a joker. Not translated: these are the card's own markings.
  String get rankSymbol => isJoker ? '' : _rankSymbols[rank - 1];

  /// The point value (`GAME_RULES.md`, Card Values): Ace 1, 2-10 face value,
  /// Jack 11, Queen 12, King 13; a joker is 0 in play (ZapZap eligibility)
  /// and 25 when [penalty] is set (final scoring).
  int value({bool penalty = false}) => isJoker ? (penalty ? 25 : 0) : rank;

  /// The face under `assets/cards/` (see `THIRD_PARTY.md`).
  String get assetPath {
    if (isJoker) {
      return 'assets/cards/joker_${isRedJoker ? 'red' : 'black'}.svg';
    }
    return 'assets/cards/${_rankNames[rank - 1]}_of_${suit!.name}.svg';
  }

  @override
  bool operator ==(Object other) => other is GameCard && other.id == id;

  @override
  int get hashCode => id.hashCode;

  @override
  String toString() => 'GameCard($id)';

  static const _rankSymbols = [
    'A', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'J', 'Q', 'K', //
  ];
  static const _rankNames = [
    'ace', '2', '3', '4', '5', '6', '7', '8', '9', '10', 'jack', 'queen',
    'king', //
  ];
}
