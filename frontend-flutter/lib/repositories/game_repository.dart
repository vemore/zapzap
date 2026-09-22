import '../models/game_results.dart';
import '../models/game_state.dart';
import '../services/api_client.dart';

/// `/api/game/:partyId`. A move answers with its own result only; refetch
/// [state] to render the table (or wait for the SSE event).
///
/// Every move can fail with 403 `NOT_YOUR_TURN` or 400
/// `INVALID_ACTION_STATE` (wrong phase), plus the codes named below.
class GameRepository {
  const GameRepository(this._api);

  final ApiClient _api;

  /// `GET /game/:id/state`: the caller's view of the table.
  Future<GameSnapshot> state(String partyId) async =>
      GameSnapshot.fromJson(await _api.get('/game/$partyId/state'));

  /// `POST /game/:id/selectHandSize`: 4-7, or 4-10 in golden score → 400
  /// `INVALID_HAND_SIZE`.
  Future<SelectHandSizeResult> selectHandSize(
    String partyId,
    int handSize,
  ) async => SelectHandSizeResult.fromJson(
    await _api.post(
      '/game/$partyId/selectHandSize',
      body: {'handSize': handSize},
    ),
  );

  /// `POST /game/:id/play` → 400 `INVALID_CARDS`, `INVALID_PLAY`.
  Future<PlayResult> play(String partyId, List<int> cardIds) async =>
      PlayResult.fromJson(
        await _api.post('/game/$partyId/play', body: {'cardIds': cardIds}),
      );

  /// `POST /game/:id/draw` from the deck → 400 `DECK_EMPTY`.
  Future<DrawResult> drawFromDeck(String partyId) async => DrawResult.fromJson(
    await _api.post('/game/$partyId/draw', body: {'source': 'deck'}),
  );

  /// `POST /game/:id/draw` of [cardId], one of the previous player's
  /// `lastCardsPlayed` → 400 `CARD_NOT_AVAILABLE`.
  Future<DrawResult> drawFromPlayed(String partyId, int cardId) async =>
      DrawResult.fromJson(
        await _api.post(
          '/game/$partyId/draw',
          body: {'source': 'played', 'cardId': cardId},
        ),
      );

  /// `POST /game/:id/zapzap` (hand ≤ 5, jokers at 0) → 400 `HAND_TOO_HIGH`.
  Future<ZapZapResult> zapZap(String partyId) async =>
      ZapZapResult.fromJson(await _api.post('/game/$partyId/zapzap'));

  /// `POST /game/:id/nextRound` once the round is finished → 400
  /// `ROUND_NOT_FINISHED`.
  Future<NextRoundResult> nextRound(String partyId) async =>
      NextRoundResult.fromJson(await _api.post('/game/$partyId/nextRound'));
}
