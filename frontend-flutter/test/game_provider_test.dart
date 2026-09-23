import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/models/game_state.dart';
import 'package:zapzap/models/sse_event.dart';
import 'package:zapzap/providers/game_provider.dart';
import 'package:zapzap/repositories/game_repository.dart';
import 'package:zapzap/services/api_exception.dart';
import 'package:zapzap/utils/rules.dart';

import 'game_helpers.dart';

void main() {
  late StreamController<SseEvent> events;

  setUp(() => events = StreamController<SseEvent>.broadcast());
  tearDown(() => events.close());

  GameProvider provider(FakeGameBackend backend, {String? userId = 'u1'}) {
    final game = GameProvider(
      GameRepository(backend.client()),
      partyId: 'p1',
      events: events.stream,
      currentUserId: userId,
    );
    addTearDown(game.dispose);
    return game;
  }

  /// One backend broadcast, as `SseEvent` reads it.
  SseEvent event(String action, {String partyId = 'p1'}) =>
      SseEvent({'partyId': partyId, 'action': action});

  group('the table', () {
    test('derives the caller\'s seat, turn, counts and eliminations', () async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(
            currentTurn: 0,
            currentAction: 'play',
            playerHand: [0, 1, 2],
            otherPlayersHandSizes: {'1': 4, '2': 6},
            scores: {'0': 12, '1': 30, '2': 5},
            eliminatedPlayers: [2],
          ),
        ),
      );
      final game = provider(backend);
      await game.load();

      expect(game.loading, isFalse);
      expect(game.error, isNull);
      expect(game.myPlayerIndex, 0);
      expect(game.isMyTurn, isTrue);
      expect(game.cardCountOf(0), 3);
      expect(game.cardCountOf(1), 4);
      expect(game.cardCountOf(2), 6);
      expect(game.scoreOf(1), 30);
      expect(game.isEliminated(2), isTrue);
      expect(game.isEliminated(0), isFalse);
      expect(game.nameOf(1), 'EasyBot1');
    });

    test('is not the caller\'s turn when another seat is to move', () async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(currentTurn: 1, currentAction: 'play'),
        ),
      );
      final game = provider(backend);
      await game.load();

      expect(game.isMyTurn, isFalse);
      expect(game.canPlay, isFalse);
      expect(game.canDraw, isFalse);
      expect(game.canZapZap, isFalse);
    });

    test('orders the players from the round\'s starting player', () async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(
            currentTurn: 2,
            currentAction: 'play',
            startingPlayer: 2,
          ),
        ),
      );
      final game = provider(backend);
      await game.load();

      expect(game.orderedPlayers.map((player) => player.playerIndex), [
        2,
        0,
        1,
      ]);
    });

    test('a party that has not dealt yet is not started', () async {
      final backend = FakeGameBackend(state: gameSnapshotJson());
      final game = provider(backend);
      await game.load();

      expect(game.isStarted, isFalse);
      expect(game.error, isNull);
    });

    test('a failed load fills error, not actionError', () async {
      final game = provider(FakeGameBackend());
      await game.load();

      expect(game.error, isA<ApiException>());
      expect(game.actionError, isNull);
      expect(game.refreshError, isNull);
    });

    test('a refresh that fails keeps the table it could not replace', () async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(currentTurn: 0, currentAction: 'play'),
        ),
      );
      final game = provider(backend);
      await game.load();
      final table = game.snapshot;

      backend.failures['GET /api/game/p1/state'] = (
        status: 500,
        body: {'error': 'the refetch fell over', 'code': 'SERVER_ERROR'},
      );
      await game.load(showSpinner: false);

      expect(game.error, isNull, reason: 'the board must stay drawable');
      expect(game.snapshot, same(table));
      expect(game.refreshError, isA<ApiException>());

      backend.failures.clear();
      await game.load(showSpinner: false);
      expect(game.refreshError, isNull, reason: 'cleared by the next answer');
    });

    test('a move that lands but whose refetch fails keeps the table', () async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(
            currentTurn: 0,
            currentAction: 'play',
            playerHand: [0, 13, 26],
          ),
        ),
      );
      final game = provider(backend);
      await game.load();
      game.toggleCard(0);
      backend.failures['GET /api/game/p1/state'] = (
        status: 500,
        body: {'error': 'the refetch fell over', 'code': 'SERVER_ERROR'},
      );

      await game.play();

      expect(backend.paths, contains('/api/game/p1/play'));
      expect(game.error, isNull);
      expect(game.snapshot, isNotNull);
      expect(
        game.consumeActionError(),
        isNull,
        reason: 'the move went through',
      );
      expect(game.refreshError, isA<ApiException>());
    });

    test(
      'the newest load wins, whatever order the answers come back in',
      () async {
        final backend = FakeGameBackend(
          state: gameSnapshotJson(
            gameState: gameStateJson(currentTurn: 1, currentAction: 'play'),
          ),
        );
        final held = Completer<void>();
        backend.onState = (call) => call == 1 ? held.future : Future.value();
        final game = provider(backend);

        // Two refetches a fraction of a second apart, as a bot party's `play`
        // and `draw` broadcasts produce; the first answers last.
        final first = game.load();
        await pumpEventQueue();
        backend.state = gameSnapshotJson(
          gameState: gameStateJson(currentTurn: 0, currentAction: 'play'),
        );
        await game.load(showSpinner: false);
        expect(game.isMyTurn, isTrue);

        held.complete();
        await first;

        expect(
          game.isMyTurn,
          isTrue,
          reason: 'the stale answer must not put the board back a turn',
        );
        expect(game.loading, isFalse);
      },
    );
  });

  group('the selection', () {
    test('keeps the tap order and toggles off', () async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(
            currentTurn: 0,
            currentAction: 'play',
            playerHand: [3, 16, 29],
          ),
        ),
      );
      final game = provider(backend);
      await game.load();

      game
        ..toggleCard(29)
        ..toggleCard(3)
        ..toggleCard(16);
      expect(game.selectedCards, [29, 3, 16]);

      game.toggleCard(3);
      expect(game.selectedCards, [29, 16]);

      game.clearSelection();
      expect(game.selectedCards, isEmpty);
    });

    test('clearing drops the discard card too', () async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(
            currentTurn: 0,
            currentAction: 'draw',
            lastCardsPlayed: [7, 8],
          ),
        ),
      );
      final game = provider(backend);
      await game.load();

      game.selectDiscardCard(8);
      expect(game.hasSelection, isTrue);
      expect(game.willTakeFromDiscard, isTrue);

      game.clearSelection();

      expect(game.selectedDiscardCard, isNull);
      expect(game.willTakeFromDiscard, isFalse);
      expect(game.hasSelection, isFalse);
    });

    test('names why a selection cannot be played, and blocks Play', () async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(
            currentTurn: 0,
            currentAction: 'play',
            playerHand: [0, 14, 30],
          ),
        ),
      );
      final game = provider(backend);
      await game.load();

      // An Ace of spades and a 2 of hearts: neither a group nor a run.
      game
        ..toggleCard(0)
        ..toggleCard(14);
      expect(game.invalidPlay, PlayError.mixedSuits);
      expect(game.canPlay, isFalse);

      game.clearSelection();
      game.toggleCard(0);
      expect(game.invalidPlay, isNull);
      expect(game.canPlay, isTrue);
    });

    test('a new hand drops the selection', () async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(
            currentTurn: 0,
            currentAction: 'play',
            playerHand: [3, 16, 29],
          ),
        ),
      );
      final game = provider(backend);
      await game.load();
      game.toggleCard(3);
      expect(game.selectedCards, [3]);

      backend.state = gameSnapshotJson(
        gameState: gameStateJson(
          currentTurn: 0,
          currentAction: 'play',
          playerHand: [3, 16, 40],
        ),
      );
      await game.load(showSpinner: false);

      expect(game.selectedCards, isEmpty);
    });
  });

  group('the moves', () {
    test('play posts the cards in tap order and refetches', () async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(
            currentTurn: 0,
            currentAction: 'play',
            playerHand: [0, 13, 26],
          ),
        ),
      );
      final game = provider(backend);
      await game.load();
      game
        ..toggleCard(26)
        ..toggleCard(0)
        ..toggleCard(13);

      await game.play();

      expect(backend.bodyOf('POST', '/api/game/p1/play'), {
        'cardIds': [26, 0, 13],
      });
      // The answer is not the new table: the state is fetched again.
      expect(backend.paths.where((path) => path.endsWith('/state')).length, 2);
    });

    test('a refused play keeps the table and fills actionError', () async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(
            currentTurn: 0,
            currentAction: 'play',
            playerHand: [0, 13, 26],
          ),
        ),
      );
      backend.failures['POST /api/game/p1/play'] = (
        status: 400,
        body: {'error': 'Invalid play', 'code': 'INVALID_PLAY'},
      );
      final game = provider(backend);
      await game.load();
      game.toggleCard(0);

      await game.play();

      expect(game.error, isNull, reason: 'the board must stay drawable');
      expect(game.snapshot, isNotNull);
      final error = game.consumeActionError();
      expect((error! as ApiException).code, GameErrorCode.invalidPlay);
      expect(game.consumeActionError(), isNull, reason: 'shown once');
    });

    test('draw takes the deck, or the selected discard card', () async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(
            currentTurn: 0,
            currentAction: 'draw',
            lastCardsPlayed: [7, 8],
          ),
        ),
      );
      final game = provider(backend);
      await game.load();

      expect(game.canDraw, isTrue);
      expect(game.canSelectDiscard, isTrue);
      await game.draw();
      expect(backend.bodyOf('POST', '/api/game/p1/draw'), {'source': 'deck'});

      game.selectDiscardCard(8);
      expect(game.willTakeFromDiscard, isTrue);
      await game.draw();
      expect(backend.bodyOf('POST', '/api/game/p1/draw'), {
        'source': 'played',
        'cardId': 8,
      });
      expect(game.selectedDiscardCard, isNull, reason: 'cleared after a draw');
    });

    test('a discard card the pile no longer holds is not posted', () async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(
            currentTurn: 0,
            currentAction: 'draw',
            lastCardsPlayed: [7, 8],
          ),
        ),
      );
      final game = provider(backend);
      await game.load();
      game.selectDiscardCard(8);
      expect(game.willTakeFromDiscard, isTrue);

      // The pile changes under the selection; the hand does not, so the
      // selection survives the refresh.
      backend.state = gameSnapshotJson(
        gameState: gameStateJson(
          currentTurn: 0,
          currentAction: 'draw',
          lastCardsPlayed: [20, 21],
        ),
      );
      await game.load(showSpinner: false);

      expect(game.selectedDiscardCard, 8);
      expect(game.willTakeFromDiscard, isFalse);
      await game.draw();
      expect(backend.bodyOf('POST', '/api/game/p1/draw'), {'source': 'deck'});
    });

    test(
      'ZapZap needs a hand of 5 points or less, in the play phase',
      () async {
        final backend = FakeGameBackend(
          state: gameSnapshotJson(
            gameState: gameStateJson(
              currentTurn: 0,
              currentAction: 'play',
              playerHand: [0, 1, 52],
            ),
          ),
        );
        final game = provider(backend);
        await game.load();

        expect(game.zapZapEligible, isTrue);
        expect(game.handValues.eligibility, 3);
        expect(game.handValues.penalty, 28);
        expect(game.canZapZap, isTrue);

        await game.zapZap();
        expect(backend.paths, contains('/api/game/p1/zapzap'));
      },
    );

    test('a heavy hand cannot call ZapZap', () async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(
            currentTurn: 0,
            currentAction: 'play',
            playerHand: [12, 11, 10],
          ),
        ),
      );
      final game = provider(backend);
      await game.load();

      expect(game.zapZapEligible, isFalse);
      expect(game.canZapZap, isFalse);
    });
  });

  group('the hand size', () {
    test('is 4-7 normally and 4-10 in Golden Score', () async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(
            currentTurn: 0,
            currentAction: 'selectHandSize',
          ),
        ),
      );
      final game = provider(backend);
      await game.load();
      expect(game.handSizeMax, 7);
      expect(game.defaultHandSize, 5);

      backend.state = gameSnapshotJson(
        gameState: gameStateJson(
          currentTurn: 0,
          currentAction: 'selectHandSize',
          isGoldenScore: true,
        ),
      );
      await game.load(showSpinner: false);
      expect(game.handSizeMax, 10);
      expect(game.defaultHandSize, 7);
    });

    test('posts the chosen size', () async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(
            currentTurn: 0,
            currentAction: 'selectHandSize',
          ),
        ),
      );
      final game = provider(backend);
      await game.load();

      await game.selectHandSize(6);
      expect(backend.bodyOf('POST', '/api/game/p1/selectHandSize'), {
        'handSize': 6,
      });
    });
  });

  group('the event stream', () {
    test('refetches on this party\'s moves and ignores the others', () async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(currentTurn: 1, currentAction: 'play'),
        ),
      );
      final game = provider(backend);
      await game.load();
      final before = backend.paths.where((p) => p.endsWith('/state')).length;

      events.add(event('play', partyId: 'other'));
      await pumpEventQueue();
      expect(
        backend.paths.where((p) => p.endsWith('/state')).length,
        before,
        reason: 'another party\'s events are dropped',
      );

      for (final action in [
        'play',
        'draw',
        'selectHandSize',
        'zapzap',
        'roundStarted',
        'gameFinished',
        'partyStarted',
      ]) {
        events.add(event(action));
        await pumpEventQueue();
      }
      expect(
        backend.paths.where((p) => p.endsWith('/state')).length,
        before + 7,
      );
    });

    test(
      'the owner starting the party puts a waiting client on the table',
      () async {
        final backend = FakeGameBackend(
          state: gameSnapshotJson(gameState: null),
        );
        final game = provider(backend);
        await game.load();
        expect(game.isStarted, isFalse);

        backend.state = gameSnapshotJson(
          gameState: gameStateJson(
            currentTurn: 0,
            currentAction: 'selectHandSize',
          ),
        );
        events.add(event('partyStarted'));
        await pumpEventQueue();

        expect(game.isStarted, isTrue);
        expect(game.currentAction, GameAction.selectHandSize);
      },
    );

    test('a deleted party ends the board', () async {
      final backend = FakeGameBackend(
        state: gameSnapshotJson(
          gameState: gameStateJson(currentTurn: 0, currentAction: 'play'),
        ),
      );
      final game = provider(backend);
      await game.load();

      events.add(event('partyDeleted'));
      await pumpEventQueue();

      expect(game.outcome, GameOutcome.closed);
    });
  });

  test('a finished round exposes what the round-end screen needs', () async {
    final backend = FakeGameBackend(
      state: gameSnapshotJson(
        roundStatus: 'finished',
        gameState: gameStateJson(
          currentTurn: 2,
          currentAction: 'finished',
          zapZapCaller: 2,
          lowestHandPlayerIndex: 2,
          handPoints: {'0': 28, '1': 49, '2': 2},
          roundScores: {'0': 28, '1': 49, '2': 0},
          allHands: {
            '0': [17, 28],
            '1': [42, 33],
            '2': [26, 0],
          },
        ),
      ),
    );
    final game = provider(backend);
    await game.load();

    expect(game.currentAction, GameAction.finished);
    expect(game.isRoundFinished, isTrue);
    expect(game.isGameFinished, isFalse);
    expect(game.game!.allHands![1], [42, 33]);
    expect(game.game!.roundScores![1], 49);
  });
}
