import 'dart:convert';

import 'json.dart';

/// The seats a party falls back to when the backend sent no `playerCount`,
/// as in React (`PartyList.jsx:167`, `PartyLobby.jsx:134`).
const int defaultPartyPlayers = 5;

/// Party statuses, as the backend spells them.
abstract final class PartyStatus {
  static const waiting = 'waiting';
  static const playing = 'playing';
  static const finished = 'finished';
}

/// A party's settings, `{playerCount, allowSpectators, roundTimeLimit}`
/// (`PartySettings`, `zapzap-rust/src/domain/value_objects/party_settings.rs`).
/// `playerCount` (3-8, the seats) is required on create, else 400
/// `VALIDATION_ERROR`. A field missing from an unreadable answer is `null`.
class PartySettings {
  const PartySettings({
    this.playerCount,
    this.allowSpectators,
    this.roundTimeLimit,
  });

  /// Accepts an object or a JSON-encoded string (`GET /admin/parties`).
  factory PartySettings.fromJson(Object? value) {
    if (value is String) {
      try {
        return PartySettings.fromJson(jsonDecode(value));
      } on FormatException {
        return const PartySettings();
      }
    }
    if (value is! Map) return const PartySettings();
    final json = value.cast<String, dynamic>();
    return PartySettings(
      playerCount: Json.intOrNull(json['playerCount']),
      allowSpectators: Json.boolOrNull(json, 'allowSpectators'),
      roundTimeLimit: Json.intOrNull(json['roundTimeLimit']),
    );
  }

  final int? playerCount;
  final bool? allowSpectators;

  /// Seconds per round, 0 for none (stored, not enforced).
  final int? roundTimeLimit;

  JsonMap toJson() => {
    'playerCount': ?playerCount,
    'allowSpectators': ?allowSpectators,
    'roundTimeLimit': ?roundTimeLimit,
  };
}

/// A party as create, details and join return it; fields a route does not
/// send are `null` (join sends only `id`, `name`, `status`).
class Party {
  const Party({
    required this.id,
    required this.name,
    required this.status,
    this.ownerId,
    this.inviteCode,
    this.visibility,
    this.settings = const PartySettings(),
    this.currentRoundId,
    this.createdAt,
    this.updatedAt,
  });

  factory Party.fromJson(JsonMap json) => Party(
    id: Json.string(json, 'id'),
    name: Json.string(json, 'name'),
    status: Json.string(json, 'status'),
    ownerId: Json.stringOrNull(json, 'ownerId'),
    inviteCode: Json.stringOrNull(json, 'inviteCode'),
    visibility: Json.stringOrNull(json, 'visibility'),
    settings: PartySettings.fromJson(json['settings']),
    currentRoundId: Json.stringOrNull(json, 'currentRoundId'),
    createdAt: Json.timestamp(json, 'createdAt'),
    updatedAt: Json.timestamp(json, 'updatedAt'),
  );

  final String id;
  final String name;

  /// One of [PartyStatus].
  final String status;
  final String? ownerId;
  final String? inviteCode;

  /// `public` or `private`.
  final String? visibility;
  final PartySettings settings;
  final String? currentRoundId;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

/// A row of `GET /party` (public parties only).
class PartySummary {
  const PartySummary({
    required this.id,
    required this.name,
    required this.status,
    required this.ownerId,
    required this.playerCount,
    required this.maxPlayers,
    required this.isMember,
    this.inviteCode,
    this.visibility,
    this.createdAt,
  });

  factory PartySummary.fromJson(JsonMap json) => PartySummary(
    id: Json.string(json, 'id'),
    name: Json.string(json, 'name'),
    status: Json.string(json, 'status'),
    ownerId: Json.string(json, 'ownerId'),
    playerCount: Json.integer(json, 'playerCount'),
    maxPlayers: _maxPlayers(json),
    isMember: Json.boolean(json, 'isMember'),
    inviteCode: Json.stringOrNull(json, 'inviteCode'),
    visibility: Json.stringOrNull(json, 'visibility'),
    createdAt: Json.timestamp(json, 'createdAt'),
  );

  /// A row without `maxPlayers` (or with 0) would read "2 / 0" and Full:
  /// fall back on the settings, then on [defaultPartyPlayers], as React does
  /// (`settings.playerCount || 5`, `PartyList.jsx:167`).
  static int _maxPlayers(JsonMap json) {
    for (final count in [
      Json.intOrNull(json['maxPlayers']),
      PartySettings.fromJson(json['settings']).playerCount,
    ]) {
      if (count != null && count > 0) return count;
    }
    return defaultPartyPlayers;
  }

  final String id;
  final String name;
  final String status;
  final String ownerId;
  final int playerCount;
  final int maxPlayers;

  /// The caller is in this party (`false` when the call was anonymous).
  final bool isMember;
  final String? inviteCode;
  final String? visibility;
  final DateTime? createdAt;
}

/// A seat in a party (`GET /party/:id`).
class PartyPlayer {
  const PartyPlayer({
    required this.userId,
    required this.username,
    required this.playerIndex,
    this.id,
    this.userType = 'human',
    this.botDifficulty,
    this.joinedAt,
  });

  factory PartyPlayer.fromJson(JsonMap json) => PartyPlayer(
    id: Json.stringOrNull(json, 'id'),
    userId: Json.string(json, 'userId'),
    username: Json.string(json, 'username'),
    playerIndex: Json.integer(json, 'playerIndex'),
    userType: Json.string(json, 'userType', 'human'),
    botDifficulty: Json.stringOrNull(json, 'botDifficulty'),
    joinedAt: Json.timestamp(json, 'joinedAt'),
  );

  /// The seat's row id (an integer, read as a string).
  final String? id;
  final String userId;
  final String username;
  final int playerIndex;

  /// `human` or `bot`.
  final String userType;

  /// For a bot: `easy`, `medium`, `hard`, `hard_vince`, `ml`, `drl`, `llm`,
  /// `thibot`.
  final String? botDifficulty;
  final DateTime? joinedAt;

  bool get isBot => userType == 'bot';
}

/// `GET /party/:id`: the party, its seats, and the caller's place in it.
class PartyDetails {
  const PartyDetails({
    required this.party,
    required this.players,
    this.isOwner = false,
    this.userPlayerIndex,
  });

  factory PartyDetails.fromJson(JsonMap json) => PartyDetails(
    party: Party.fromJson(Json.map(json, 'party') ?? const {}),
    players: Json.list(json, 'players', PartyPlayer.fromJson),
    isOwner: Json.boolean(json, 'isOwner'),
    userPlayerIndex: Json.intOrNull(json['userPlayerIndex']),
  );

  final Party party;
  final List<PartyPlayer> players;
  final bool isOwner;

  /// The caller's seat, `null` when not in the party.
  final int? userPlayerIndex;
}

/// `POST /party`.
class CreatePartyResult {
  const CreatePartyResult({required this.party, this.botsJoined = 0});

  factory CreatePartyResult.fromJson(JsonMap json) => CreatePartyResult(
    party: Party.fromJson(Json.map(json, 'party') ?? const {}),
    botsJoined: Json.integer(json, 'botsJoined'),
  );

  final Party party;
  final int botsJoined;
}

/// `POST /party/:id/join`: the party and the seat taken.
class JoinPartyResult {
  const JoinPartyResult({required this.party, required this.playerIndex});

  factory JoinPartyResult.fromJson(JsonMap json) => JoinPartyResult(
    party: Party.fromJson(Json.map(json, 'party') ?? const {}),
    playerIndex: Json.integer(json, 'playerIndex'),
  );

  final Party party;
  final int playerIndex;
}

/// A round reference: `{id, roundNumber, status}`.
class RoundInfo {
  const RoundInfo({
    required this.id,
    required this.roundNumber,
    required this.status,
  });

  factory RoundInfo.fromJson(JsonMap json) => RoundInfo(
    id: Json.string(json, 'id'),
    roundNumber: Json.integer(json, 'roundNumber'),
    status: Json.string(json, 'status'),
  );

  final String id;
  final int roundNumber;

  /// `active` or `finished`.
  final String status;
}

/// `POST /party/:id/start`.
class StartPartyResult {
  const StartPartyResult({required this.party, required this.round});

  factory StartPartyResult.fromJson(JsonMap json) => StartPartyResult(
    party: Party.fromJson(Json.map(json, 'party') ?? const {}),
    round: RoundInfo.fromJson(Json.map(json, 'round') ?? const {}),
  );

  /// Only `id`, `status` and `currentRoundId` are set.
  final Party party;
  final RoundInfo round;
}

/// A signed-in user with an open event stream (`GET /players/connected`, at
/// most 5).
class ConnectedPlayer {
  const ConnectedPlayer({
    required this.userId,
    required this.username,
    required this.status,
    this.partyId,
    this.connectedAt,
  });

  factory ConnectedPlayer.fromJson(JsonMap json) => ConnectedPlayer(
    userId: Json.string(json, 'userId'),
    username: Json.string(json, 'username'),
    status: Json.string(json, 'status', 'lobby'),
    partyId: Json.stringOrNull(json, 'partyId'),
    connectedAt: Json.timestamp(json, 'connectedAt'),
  );

  final String userId;
  final String username;

  /// `lobby`, `party` or `game` (Rust always says `lobby`).
  final String status;
  final String? partyId;
  final DateTime? connectedAt;
}
