// A deleted account's finished games belong to an anonymous user whose id starts with
// this prefix (zapzap-rust/src/domain/entities/user.rs, DELETED_USER_ID_PREFIX).
export const DELETED_USER_ID_PREFIX = 'deleted-';

export const DELETED_PLAYER_NAME = 'Joueur supprimé';

/** The name to show for a player of a finished game */
export const playerName = (userId, username) =>
  typeof userId === 'string' && userId.startsWith(DELETED_USER_ID_PREFIX)
    ? DELETED_PLAYER_NAME
    : username;
