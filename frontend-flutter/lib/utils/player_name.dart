import '../l10n/app_localizations.dart';

/// The id prefix of a deleted player. When a player deletes their account,
/// the backend moves their finished games to a stand-in account whose id
/// starts with it (`zapzap-rust/src/application/auth/delete_account.rs`), so
/// the other players' history keeps the game.
const deletedUserIdPrefix = 'deleted-';

/// Whether [userId] is such a stand-in.
bool isDeletedUser(String? userId) =>
    userId != null && userId.startsWith(deletedUserIdPrefix);

/// The name to show for a player of the history: « Joueur supprimé » /
/// "Deleted player" for a deleted account, else [username].
String playerName(AppLocalizations l10n, String? userId, String username) =>
    isDeletedUser(userId) ? l10n.deletedPlayer : username;
