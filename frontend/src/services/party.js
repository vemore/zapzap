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
