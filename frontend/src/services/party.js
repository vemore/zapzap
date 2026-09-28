import { apiClient } from './api';

/** The bot levels a free lobby seat can take, in the order the menu lists them */
export const BOT_DIFFICULTIES = [
  { value: 'easy', label: 'Easy' },
  { value: 'medium', label: 'Medium' },
  { value: 'hard', label: 'Hard' },
  { value: 'hard_vince', label: 'Hard Vince' },
  { value: 'llm', label: 'LLM (Llama 3.3)' },
  { value: 'thibot', label: 'Thibot' },
];

/** The levels fill-and-start takes; the backend falls back to the next ones */
export const FILL_DIFFICULTIES = BOT_DIFFICULTIES.slice(0, 3);

/**
 * The turn time limits a party can be created with (`settings.turnTimeLimit`, seconds;
 * anything else is refused). The server runs the clock only when the game starts with
 * two humans or more (GAME_RULES.md, Turn Time Limit).
 */
export const TURN_TIME_LIMITS = [
  { value: 0, label: 'Off' },
  { value: 30, label: '30 s' },
  { value: 60, label: '60 s' },
  { value: 120, label: '2 min' },
];

/** The label of a turn time limit in seconds, or null when there is none */
export function turnTimeLimitLabel(seconds) {
  if (!seconds) return null;
  return TURN_TIME_LIMITS.find(l => l.value === seconds)?.label || `${seconds} s`;
}

/** GET /bots: every bot account (an empty list when the call fails) */
export async function listBots() {
  try {
    const response = await apiClient.get('/bots');
    return response.data?.bots || [];
  } catch (err) {
    console.error('Failed to fetch bots:', err);
    return [];
  }
}

/** POST /party/:id/bots (owner, waiting party): the bot takes the lowest free seat */
export async function addBotToParty(partyId, botId) {
  const response = await apiClient.post(`/party/${partyId}/bots`, { botId });
  return response.data;
}

/**
 * POST /party/:id/fill-and-start (owner, waiting party): every free seat gets a bot of
 * `difficulty` (the next levels when it runs out), then the party starts. A refusal
 * (409 NOT_ENOUGH_BOTS, PARTY_STARTED) seats nobody.
 */
export async function fillAndStart(partyId, difficulty) {
  const response = await apiClient.post(`/party/${partyId}/fill-and-start`, { difficulty });
  return response.data;
}

/**
 * What the party list says to a player the turn timer ejected: their seat went to a bot,
 * and GameBoard sent them back there with `state.ejected`.
 */
export const EJECTED_MESSAGE = 'Vous avez été retiré de la partie (temps dépassé)';
