import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/models/admin.dart';
import 'package:zapzap/models/bot.dart';
import 'package:zapzap/models/game_results.dart';
import 'package:zapzap/models/game_state.dart';
import 'package:zapzap/models/history.dart';
import 'package:zapzap/models/json.dart';
import 'package:zapzap/models/party.dart';
import 'package:zapzap/models/stats.dart';
import 'package:zapzap/models/user.dart';

import 'fixtures.dart';

// Every model parsed from the backend's answers (test/fixtures/), plus the
// cases a fixture does not show, written from the Rust response structs
// (zapzap-rust/src/api/routes/*.rs).

DateTime utc(int seconds) =>
    DateTime.fromMillisecondsSinceEpoch(seconds * 1000, isUtc: true);

void main() {
  group('auth', () {
    test('login', () {
      final session = AuthSession.fromJson(fixture('auth_login'));
      expect(session.token, 'test-token-auth_login');
      expect(session.user.id, 'a8891da0-2bf8-4e72-ba71-8aa2e3f20f4e');
      expect(session.user.username, 'Vincent');
      expect(session.user.isAdmin, isFalse);
      expect(session.isNewUser, isFalse);
    });

    test('register: createdAt in Unix seconds, no isAdmin', () {
      final session = AuthSession.fromJson(fixture('auth_register'));
      expect(session.user.username, startsWith('fixture'));
      expect(session.user.createdAt, utc(1790094174));
      expect(session.user.isAdmin, isFalse);
    });

    test('a user survives toJson/fromJson', () {
      final user = AuthSession.fromJson(fixture('auth_register')).user;
      final again = User.fromJson(user.toJson());
      expect(again.id, user.id);
      expect(again.createdAt, user.createdAt);
    });
  });

  group('party', () {
    test('list', () {
      final page = Page.fromJson(
        fixture('party_list'),
        'parties',
        PartySummary.fromJson,
      );
      expect(page.items, hasLength(2));
      final party = page.items.first;
      expect(party.name, 'Fixture party');
      expect(party.status, PartyStatus.waiting);
      expect(party.playerCount, 3);
      expect(party.maxPlayers, 3);
      expect(party.isMember, isTrue);
      expect(party.inviteCode, 'BGJARGH7');
      expect(party.createdAt, utc(1790094174));
    });

    test('list paging sits at the top level (both backends)', () {
      final page = Page.fromJson(
        {
          'success': true,
          'parties': <Object>[],
          'total': 12,
          'limit': 50,
          'offset': 0,
        },
        'parties',
        PartySummary.fromJson,
      );
      expect(page.total, 12);
      expect(page.limit, 50);
      expect(page.offset, 0);
      expect(page.hasMore, isNull);
    });

    test(
      'a party row without maxPlayers falls back to its settings, then 5',
      () {
        final row = fixture('party_list')['parties'][0] as JsonMap;
        expect(
          PartySummary.fromJson({...row}..remove('maxPlayers')).maxPlayers,
          5,
        );
        expect(PartySummary.fromJson({...row, 'maxPlayers': 0}).maxPlayers, 5);
        expect(
          PartySummary.fromJson(
            {
              ...row,
              'settings': {'playerCount': 4},
            }..remove('maxPlayers'),
          ).maxPlayers,
          4,
        );
      },
    );

    test('create', () {
      final result = CreatePartyResult.fromJson(fixture('party_create'));
      expect(result.botsJoined, 2);
      expect(result.party.visibility, 'public');
      expect(result.party.settings.playerCount, 3);
      expect(result.party.settings.allowSpectators, isFalse);
      expect(result.party.settings.roundTimeLimit, 0);
    });

    test('details: players with userType and botDifficulty', () {
      final details = PartyDetails.fromJson(fixture('party_details'));
      expect(details.isOwner, isTrue);
      expect(details.userPlayerIndex, 0);
      expect(details.party.currentRoundId, isNull);
      expect(details.party.updatedAt, utc(1790094174));
      expect(details.players.map((p) => p.username), [
        'Vincent',
        'EasyBot1',
        'MediumBot1',
      ]);
      final human = details.players[0];
      expect(human.id, '5');
      expect(human.isBot, isFalse);
      expect(human.botDifficulty, isNull);
      final bot = details.players[1];
      expect(bot.isBot, isTrue);
      expect(bot.botDifficulty, 'easy');
      expect(bot.playerIndex, 1);
      expect(bot.joinedAt, utc(1790094174));
    });

    test('details: string ids, RFC 3339 dates, not in the party', () {
      final details = PartyDetails.fromJson({
        'success': true,
        'party': {
          'id': 'p1',
          'name': 'Rust',
          'ownerId': 'u1',
          'inviteCode': 'ABC',
          'visibility': 'private',
          'status': 'playing',
          'settings': {
            'playerCount': 6,
            'allowSpectators': true,
            'roundTimeLimit': 120,
          },
          'currentRoundId': 'r1',
          'createdAt': '2026-09-22T16:22:54+00:00',
          'updatedAt': '1790094174',
        },
        'players': [
          {
            'id': '12',
            'userId': 'u1',
            'username': 'Ana',
            'userType': 'human',
            'botDifficulty': null,
            'playerIndex': 0,
            'joinedAt': '2026-09-22T16:22:54Z',
          },
        ],
        'isOwner': false,
        'userPlayerIndex': null,
      });
      expect(details.isOwner, isFalse);
      expect(details.userPlayerIndex, isNull);
      expect(details.party.settings.playerCount, 6);
      expect(details.party.settings.allowSpectators, isTrue);
      expect(details.party.settings.roundTimeLimit, 120);
      expect(details.party.createdAt, DateTime.utc(2026, 9, 22, 16, 22, 54));
      expect(details.party.updatedAt, utc(1790094174));
      expect(details.players.single.id, '12');
    });

    test('join, start, connected players', () {
      final join = JoinPartyResult.fromJson(fixture('party_join'));
      expect(join.party.name, 'Second');
      expect(join.playerIndex, 1);
      final start = StartPartyResult.fromJson(fixture('party_start'));
      expect(start.party.status, PartyStatus.playing);
      expect(start.round.roundNumber, 1);
      expect(start.round.status, 'active');
      expect(
        Json.list(
          fixture('players_connected'),
          'players',
          ConnectedPlayer.fromJson,
        ),
        isEmpty,
      );
      final player = ConnectedPlayer.fromJson({
        'userId': 'u1',
        'username': 'Ana',
        'status': 'party',
        'partyId': 'p1',
        'connectedAt': 1790094197863, // milliseconds
      });
      expect(player.connectedAt, DateTime.utc(2026, 9, 22, 16, 23, 17, 863));
    });

    test('settings: {playerCount, allowSpectators, roundTimeLimit}', () {
      final settings = PartySettings.fromJson({
        'playerCount': 5,
        'allowSpectators': true,
        'roundTimeLimit': 90,
      });
      expect(settings.playerCount, 5);
      expect(settings.allowSpectators, isTrue);
      expect(settings.roundTimeLimit, 90);
      expect(settings.toJson(), {
        'playerCount': 5,
        'allowSpectators': true,
        'roundTimeLimit': 90,
      });
    });

    test('settings as a JSON string (admin), and toJson', () {
      final settings = PartySettings.fromJson(
        '{"playerCount":5,"allowSpectators":false,"roundTimeLimit":0}',
      );
      expect(settings.playerCount, 5);
      expect(settings.allowSpectators, isFalse);
      expect(settings.roundTimeLimit, 0);
      expect(const PartySettings(playerCount: 4).toJson(), {'playerCount': 4});
    });

    test('settings keys the backend no longer has are not read', () {
      final settings = PartySettings.fromJson({
        'playerCount': 3,
        'handSize': 7,
        'maxScore': 100,
        'enableGoldenScore': true,
        'goldenScoreThreshold': 100,
      });
      expect(settings.toJson(), {'playerCount': 3});
    });
  });

  test('bots', () {
    final bots = Json.list(fixture('bots'), 'bots', Bot.fromJson);
    expect(bots, hasLength(8));
    expect(bots.first.username, 'EasyBot1');
    expect(bots.first.difficulty, 'easy');
    expect(bots.map((b) => b.difficulty).toSet(), {
      'easy',
      'medium',
      'hard',
      'thibot',
    });
  });

  group('game state', () {
    test('a waiting party has no round and no game state', () {
      final snapshot = GameSnapshot.fromJson(fixture('game_state_waiting'));
      expect(snapshot.party.status, PartyStatus.waiting);
      expect(snapshot.players, hasLength(3));
      expect(snapshot.round, isNull);
      expect(snapshot.gameState, isNull);
    });

    test('a round in play', () {
      final snapshot = GameSnapshot.fromJson(fixture('game_state_playing'));
      final state = snapshot.gameState!;
      expect(snapshot.round!.status, 'active');
      expect(state.currentTurn, 0);
      expect(state.currentAction, GameAction.play);
      expect(state.deckSize, 38);
      expect(state.lastCardsPlayed, [45]);
      expect(state.cardsPlayed, isEmpty);
      expect(state.scores, {0: 0, 1: 0, 2: 0});
      expect(state.playerHand, [17, 37, 28, 1, 51]);
      expect(state.otherPlayersHandSizes, {1: 5, 2: 5});
      expect(state.lastAction!.type, 'selectHandSize');
      expect(state.lastAction!.handSize, 5);
      expect(state.isGoldenScore, isFalse);
      expect(state.eliminatedPlayers, isEmpty);
      expect(state.startingPlayer, 0);
      expect(state.isRoundFinished, isFalse);
      expect(state.allHands, isNull);
      expect(state.handPoints, isNull);
      expect(state.zapZapCaller, isNull);
      expect(state.roundScores, isNull);
      expect(state.gameFinished, isFalse);
      expect(state.winner, isNull);
    });

    test('a finished round reveals every hand', () {
      final snapshot = GameSnapshot.fromJson(fixture('game_state_finished'));
      final state = snapshot.gameState!;
      expect(snapshot.round!.status, 'finished');
      expect(state.currentAction, GameAction.finished);
      expect(state.isRoundFinished, isTrue);
      expect(state.allHands, {
        0: [17, 28, 1, 30, 38],
        1: [42, 33, 24, 53],
        2: [26, 0],
      });
      expect(state.handPoints, {0: 28, 1: 49, 2: 2});
      expect(state.zapZapCaller, 2);
      expect(state.lowestHandPlayerIndex, 2);
      expect(state.wasCounterActed, isFalse);
      expect(state.counterActedByPlayerIndex, isNull);
      expect(state.roundScores, {0: 28, 1: 49, 2: 0});
      expect(state.scores, {0: 28, 1: 49, 2: 0});
      expect(state.gameFinished, isFalse);
      expect(state.winner, isNull);
      final zapzap = state.lastAction!;
      expect(zapzap.type, 'zapzap');
      expect(zapzap.playerIndex, 2);
      expect(zapzap.callerHandPoints, 2);
      expect(zapzap.roundScores, {0: 28, 1: 49, 2: 0});
      // lastAction.timestamp is in milliseconds, unlike the other dates.
      expect(zapzap.timestamp, DateTime.utc(2026, 9, 22, 16, 23, 17, 863));
    });

    test('a finished game names its winner', () {
      final state = GameSnapshot.fromJson(fixture('game_state_game_finished'))
          .gameState!;
      expect(state.gameFinished, isTrue);
      expect(state.isGoldenScore, isTrue);
      expect(state.eliminatedPlayers, [0]);
      expect(state.scores, {0: 122, 1: 58, 2: 77});
      expect(state.allHands![0], isEmpty);
      final winner = state.winner!;
      expect(winner.playerIndex, 2);
      expect(winner.username, 'MediumBot1');
      expect(winner.userId, '74a0d812-54b3-4b99-95a3-ca56596fe8bf');
      expect(winner.score, 77);
    });

    test('an unknown phase does not throw', () {
      expect(GameAction.fromWire('somethingNew'), GameAction.unknown);
      expect(GameAction.fromWire(null), GameAction.unknown);
      expect(GameAction.fromWire(''), GameAction.unknown);
      expect(GameAction.fromWire('draw'), GameAction.draw);
    });
  });

  group('game moves', () {
    test('play, draw, select hand size', () {
      final play = PlayResult.fromJson(fixture('game_play'));
      expect(play.cardsPlayed, isNotEmpty);
      expect(play.remainingCards, greaterThan(0));
      final draw = DrawResult.fromJson(fixture('game_draw'));
      expect(draw.source, 'deck');
      expect(draw.handSize, greaterThan(0));
      final select = SelectHandSizeResult.fromJson(
        fixture('game_select_hand_size'),
      );
      expect(select.handSize, 5);
    });

    test("zapzap: running totals and this round's points", () {
      final result = ZapZapResult.fromJson(fixture('game_zapzap'));
      expect(result.zapzapSuccess, isTrue);
      expect(result.counteracted, isFalse);
      expect(result.counteractedByPlayerIndex, isNull);
      expect(result.totalScores, {0: 0, 1: 23, 2: 9});
      expect(result.roundScores, {0: 0, 1: 23, 2: 9});
      expect(result.handPoints, {0: 28, 1: 23, 2: 9});
      expect(result.callerPoints, 3);
      final after = GameSnapshot.fromJson(fixture('game_state_after_zapzap'))
          .gameState!;
      expect(after.zapZapCaller, 0);
      expect(after.lowestHandPlayerIndex, 0);
      expect(after.roundScores, {0: 0, 1: 23, 2: 9});
    });

    test('zapzap counteracted, after round 1: totals are not round points', () {
      // Round 2, counteracted: totals were {0: 28, 1: 49, 2: 0}.
      final result = ZapZapResult.fromJson({
        'success': true,
        'zapzapSuccess': false,
        'counteracted': true,
        'counteractedBy': 2,
        'scores': {'0': 58, '1': 61, '2': 0},
        'roundScores': {'0': 30, '1': 12, '2': 0},
        'handPoints': {'0': 4, '1': 12, '2': 2},
        'callerPoints': 4,
      });
      expect(result.counteracted, isTrue);
      expect(result.counteractedByPlayerIndex, 2);
      expect(result.totalScores, {0: 58, 1: 61, 2: 0});
      expect(result.roundScores, {0: 30, 1: 12, 2: 0});
      expect(result.handPoints, {0: 4, 1: 12, 2: 2});
      expect(result.callerPoints, 4);
    });

    test('next round', () {
      final result = NextRoundResult.fromJson(fixture('game_next_round'));
      expect(result.gameFinished, isFalse);
      expect(result.round!.roundNumber, 2);
      expect(result.startingPlayer, 1);
      expect(result.scores, {0: 28, 1: 49, 2: 0});
      expect(result.eliminatedPlayers, isEmpty);
    });

    test('next round ending the game (objects, older bare indexes)', () {
      final result = NextRoundResult.fromJson({
        'success': true,
        'gameFinished': true,
        'winner': {'userId': 'u2', 'playerIndex': 2, 'score': 77},
        'finalScores': {'0': 122, '1': 58, '2': 77},
        'eliminatedPlayers': [
          {'userId': 'u0', 'playerIndex': 0, 'score': 122},
        ],
      });
      expect(result.winner!.playerIndex, 2);
      expect(result.finalScores, {0: 122, 1: 58, 2: 77});
      expect(result.eliminatedPlayers, [0]);
      // A Rust answer from before 2026-09-24.
      final older = NextRoundResult.fromJson({
        'success': true,
        'gameFinished': true,
        'winner': 2,
        'eliminatedPlayers': [0],
        'finalScores': [
          {'playerIndex': 0, 'score': 122},
        ],
      });
      expect(older.winner!.playerIndex, 2);
      expect(older.winner!.username, isNull);
      expect(older.eliminatedPlayers, [0]);
      expect(older.finalScores, {0: 122});
    });
  });

  group('history', () {
    test('my games and public games', () {
      for (final name in ['history_list', 'history_public']) {
        final page = Page.fromJson(
          fixture(name),
          'games',
          GameHistoryEntry.fromJson,
        );
        expect(page.items, hasLength(1), reason: name);
        expect(page.limit, 20);
        expect(page.hasMore, isFalse);
        final game = page.items.single;
        expect(game.partyName, 'Fixture party');
        expect(game.winnerUsername, 'MediumBot1');
        expect(game.winnerFinalScore, 77);
        expect(game.totalRounds, 5);
        expect(game.wasGoldenScore, isTrue);
        expect(game.playerCount, 3);
        expect(game.finishedAt, utc(1790094408));
      }
    });

    test('my games carry my place and score, public games do not', () {
      GameHistoryEntry only(String name) => Page.fromJson(
        fixture(name),
        'games',
        GameHistoryEntry.fromJson,
      ).items.single;
      final mine = only('history_list');
      expect(mine.userPlacement, 3);
      expect(mine.userScore, 122);
      final public = only('history_public');
      expect(public.userPlacement, isNull);
      expect(public.userScore, isNull);
    });

    test('an entry with every key, and its pagination', () {
      final page = Page.fromJson(
        {
          'success': true,
          'games': [
            {
              'id': 7,
              'partyId': 'p1',
              'partyName': 'Rust',
              'winnerUserId': 'u1',
              'winnerUsername': 'Ana',
              'winnerFinalScore': 41,
              'totalRounds': 6,
              'wasGoldenScore': false,
              'playerCount': 4,
              'finishedAt': 1790094408,
              'visibility': 'public',
              'userPlacement': 2,
              'userScore': 40,
            },
          ],
          'pagination': {'limit': 20, 'offset': 0, 'hasMore': false},
        },
        'games',
        GameHistoryEntry.fromJson,
      );
      expect(page.limit, 20);
      expect(page.hasMore, isFalse);
      expect(page.total, isNull);
      final game = page.items.single;
      expect(game.winnerUserId, 'u1');
      expect(game.winnerFinalScore, 41);
      expect(game.totalRounds, 6);
      expect(game.wasGoldenScore, isFalse);
      expect(game.visibility, 'public');
      expect(game.userPlacement, 2);
      expect(game.userScore, 40);
    });

    test('details: players and rounds, hand cards as a list', () {
      final details = GameDetails.fromJson(fixture('history_details'));
      expect(details.game.status, 'finished');
      expect(details.game.winnerUsername, 'MediumBot1');
      expect(details.game.winnerFinalScore, 77);
      expect(details.game.totalRounds, 5);
      expect(details.game.finishedAt, utc(1790094408));
      expect(details.players.map((p) => p.finishPosition), [1, 2, 3]);
      expect(details.players.first.isWinner, isTrue);
      expect(details.players[1].successfulZapZaps, 3);
      expect(details.rounds, hasLength(5));
      final first = details.rounds.first.players.first;
      expect(first.username, 'Vincent');
      expect(first.handCards, [17, 28, 1, 30, 38]);
      expect(first.scoreThisRound, 28);
      expect(first.totalScoreAfter, 28);
      expect(
        RoundPlayerScore.fromJson({
          'handCards': [1, 2],
        }).handCards,
        [1, 2],
      );
    });
  });

  group('stats', () {
    test('me and a user', () {
      for (final name in ['stats_me', 'stats_user']) {
        final stats = UserStats.fromJson(fixture(name));
        expect(stats.username, 'Vincent', reason: name);
        expect(stats.gamesPlayed, 1);
        expect(stats.losses, 1);
        expect(stats.winRate, 0);
        expect(stats.averageScore, 122);
        expect(stats.bestScore, 122);
        expect(stats.totalRoundsPlayed, 5);
        expect(stats.zapzaps.total, 0);
      }
    });

    test('leaderboard', () {
      final page = Page.fromJson(
        fixture('stats_leaderboard'),
        'leaderboard',
        LeaderboardEntry.fromJson,
      );
      final entry = page.items.single;
      expect(entry.rank, 1);
      expect(entry.username, 'Vincent');
      expect(entry.averageScore, 122);
      expect(page.hasMore, isFalse);
    });

    test('bots', () {
      final stats = BotStats.fromJson(fixture('stats_bots'));
      expect(stats.totals.totalBots, 2);
      expect(stats.totals.overallWinRate, 0.5);
      expect(stats.totals.overallZapzapSuccessRate, 1);
      expect(stats.byDifficulty.map((d) => d.difficulty), ['easy', 'medium']);
      expect(stats.byDifficulty.first.botCount, 1);
      expect(stats.byDifficulty.first.roundWinRate, 0.6);
      expect(stats.byDifficulty.first.zapzaps.successful, 3);
      expect(stats.byBot.last.username, 'MediumBot1');
      expect(stats.byBot.last.wins, 1);
      expect(stats.byBot.last.roundWinRate, isNull);
    });
  });

  group('admin', () {
    test('users', () {
      final page = Page.fromJson(
        fixture('admin_users'),
        'users',
        AdminUser.fromJson,
      );
      expect(page.items, hasLength(8));
      expect(page.total, 8);
      expect(page.limit, 50);
      final admin = page.items.firstWhere((u) => u.username == 'admin');
      expect(admin.isAdmin, isTrue);
      expect(admin.lastLoginAt, utc(1790094174));
      final vincent = page.items.firstWhere((u) => u.username == 'Vincent');
      expect(vincent.gamesPlayed, 1);
      final never = page.items.firstWhere((u) => u.username == 'Thibaut');
      expect(never.lastLoginAt, isNull);
    });

    test('parties: settings arrive JSON-encoded', () {
      final page = Page.fromJson(
        fixture('admin_parties'),
        'parties',
        AdminParty.fromJson,
      );
      expect(page.total, 2);
      final party = page.items.first;
      expect(party.ownerUsername, 'Vincent');
      expect(party.status, PartyStatus.finished);
      expect(party.settings.playerCount, 3);
      expect(party.playerCount, 3);
    });

    test('statistics', () {
      final stats = AdminStatistics.fromJson(fixture('admin_statistics'));
      expect(stats.totalUsers, 8);
      expect(stats.totalParties, 2);
      expect(stats.waitingParties, 1);
      expect(stats.finishedParties, 1);
      expect(stats.completionRate, 50);
      expect(stats.totalRounds, 5);
      expect(stats.daily.single.period, '2026-09-22');
      expect(stats.weekly.single.period, '2026-38');
      expect(stats.monthly.single.count, 1);
      expect(stats.mostActiveUsers.single.username, 'Vincent');
    });
  });

  group('Json helpers', () {
    test('timestamps: seconds, milliseconds, strings, garbage', () {
      final seconds = utc(1790094174);
      expect(Json.timestamp({'t': 1790094174}, 't'), seconds);
      expect(Json.timestamp({'t': 1790094174000}, 't'), seconds);
      expect(Json.timestamp({'t': '1790094174'}, 't'), seconds);
      expect(Json.timestamp({'t': 'yesterday'}, 't'), isNull);
      expect(Json.timestamp({'t': null}, 't'), isNull);
      expect(Json.timestamp({}, 't'), isNull);
    });

    test('player-index maps from string keys', () {
      expect(Json.intMap({'0': 1, '10': 2, 'x': 3}), {0: 1, 10: 2});
      expect(Json.intMap(null), isEmpty);
      expect(Json.intMapOrNull(null), isNull);
    });
  });
}
