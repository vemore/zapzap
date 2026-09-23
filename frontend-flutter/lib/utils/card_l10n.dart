import '../l10n/app_localizations.dart';
import '../models/card.dart';
import 'rules.dart';

/// The localised texts of the card model and the play rules, kept out of
/// `models/` and `rules.dart` so those stay free of Flutter.
extension CardL10n on AppLocalizations {
  String suitName(Suit suit) => switch (suit) {
    Suit.spades => suitSpades,
    Suit.hearts => suitHearts,
    Suit.clubs => suitClubs,
    Suit.diamonds => suitDiamonds,
  };

  /// What a screen reader says for [card]: "A de Pique", "Joker rouge".
  String cardName(GameCard card) {
    if (card.isJoker) return card.isRedJoker ? cardJokerRed : cardJokerBlack;
    return cardLabel(card.rankSymbol, suitName(card.suit!));
  }

  /// [card] as printed in its corner — "7♥" —, a joker by its name.
  String cardShort(GameCard card) =>
      card.isJoker ? cardName(card) : '${card.rankSymbol}${card.suit!.symbol}';

  /// The primary button of the play step, naming the move [cards] make:
  /// "Jouer 7♥", "Jouer la paire de 7", "Jouer la suite (3 cartes)"; plain
  /// "Jouer" when they make none (nothing selected, or a refused play).
  String playMoveLabel(List<int> cards) {
    final analysis = analyzePlay(cards);
    switch (analysis.type) {
      case PlayType.single:
        return gameMovePlaySingle(cardShort(GameCard(cards.single)));
      case PlayType.sameRank:
        final regular = cards.map(GameCard.new).where((c) => !c.isJoker);
        if (regular.isEmpty) return gameMovePlayJokers(cards.length);
        final rank = regular.first.rankSymbol;
        return cards.length == 2
            ? gameMovePlayPair(rank)
            : gameMovePlayGroup(cards.length, rank);
      case PlayType.sequence:
        return gameMovePlaySequence(cards.length);
      case PlayType.invalid:
        return gameMovePlay;
    }
  }

  String playErrorMessage(PlayError error) => switch (error) {
    PlayError.empty => playErrorEmpty,
    PlayError.unknownCard => playErrorUnknownCard,
    PlayError.duplicateCard => playErrorDuplicateCard,
    PlayError.mixedSuits => playErrorMixedSuits,
    PlayError.sequenceTooShort => playErrorSequenceTooShort,
    PlayError.notConsecutive => playErrorNotConsecutive,
  };
}
