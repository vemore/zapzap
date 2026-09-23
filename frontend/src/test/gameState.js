/**
 * Builds the body of `GET /game/:partyId/state` as GameBoard reads it, for the
 * GameBoard and game-flow tests. The viewer is always `me` (player index 0 by
 * default); the other seats get their hand sizes from `handSizes`.
 *
 * @param {Object} options
 * @param {string[]} options.usernames - One per seat, in seat order
 * @param {number} options.me - Seat of the signed-in user
 * @param {number[]} options.myHand - Card ids in the viewer's hand
 * @param {number[]} options.handSizes - Hand size per seat (the viewer's is ignored)
 * @param {number[]} options.scores - Total score per seat
 * @param {number} options.currentTurn - Seat whose turn it is
 * @param {string} options.currentAction - 'selectHandSize' | 'play' | 'draw' | 'finished'
 * @param {Object} options.extra - Merged into `gameState` (round-end fields and so on)
 */
export function gameStateResponse({
  usernames = ['Alice', 'Bob'],
  me = 0,
  myHand = [0, 14, 28],
  handSizes,
  scores,
  currentTurn = 0,
  currentAction = 'play',
  roundNumber = 1,
  extra = {},
} = {}) {
  const sizes = handSizes || usernames.map(() => 5);
  return {
    party: { id: 'party1', name: 'Test Party' },
    players: usernames.map((username, playerIndex) => ({
      userId: String(playerIndex + 1),
      playerIndex,
      username,
    })),
    round: { roundNumber },
    gameState: {
      currentTurn,
      currentAction,
      playerHand: myHand,
      otherPlayersHandSizes: Object.fromEntries(
        sizes.map((size, seat) => [seat, seat === me ? myHand.length : size])
      ),
      scores: Object.fromEntries((scores || usernames.map(() => 0)).map((s, seat) => [seat, s])),
      deckSize: 30,
      lastCardsPlayed: [],
      cardsPlayed: [],
      startingPlayer: 0,
      ...extra,
    },
  };
}

/** The user id GameBoard compares with `players[].userId`, for seat `me`. */
export const userIdOfSeat = (seat) => String(seat + 1);
