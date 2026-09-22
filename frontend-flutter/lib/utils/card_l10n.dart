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

  String playErrorMessage(PlayError error) => switch (error) {
    PlayError.empty => playErrorEmpty,
    PlayError.unknownCard => playErrorUnknownCard,
    PlayError.duplicateCard => playErrorDuplicateCard,
    PlayError.mixedSuits => playErrorMixedSuits,
    PlayError.sequenceTooShort => playErrorSequenceTooShort,
    PlayError.notConsecutive => playErrorNotConsecutive,
  };
}
