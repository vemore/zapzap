import '../l10n/app_localizations.dart';
import '../providers/game_provider.dart';
import '../services/api_exception.dart';

/// The localised text of a refused move. As everywhere in this client the
/// backend's own message is never shown: only its code is read
/// ([ApiException.code]).
///
/// The board shows this in a snack bar and stays where it is — unlike the
/// React board, where any failure replaces the whole screen
/// (`GameBoard.jsx:220-235`).
String gameErrorText(AppLocalizations l10n, Object error) {
  if (error is! ApiException) return l10n.errorGeneric;
  if (error.isConnectivity) return l10n.errorNetwork;
  return switch (error.code) {
    ApiErrorCode.notYourTurn => l10n.errorNotYourTurn,
    ApiErrorCode.handTooHigh => l10n.errorHandTooHigh,
    GameErrorCode.invalidActionState => l10n.errorInvalidActionState,
    GameErrorCode.invalidPlay => l10n.errorInvalidPlay,
    GameErrorCode.invalidCards => l10n.errorInvalidCards,
    GameErrorCode.cardNotAvailable => l10n.errorCardNotAvailable,
    GameErrorCode.deckEmpty => l10n.errorDeckEmpty,
    GameErrorCode.invalidHandSize => l10n.errorInvalidHandSize,
    GameErrorCode.roundNotFinished => l10n.errorRoundNotFinished,
    GameErrorCode.notInParty => l10n.errorNotInParty,
    ApiErrorCode.partyNotFound => l10n.errorPartyNotFound,
    _ => l10n.errorGeneric,
  };
}
