import 'json.dart';

/// A bot account a party can seat (`GET /bots`).
class Bot {
  const Bot({
    required this.id,
    required this.username,
    required this.difficulty,
    this.userType = 'bot',
  });

  factory Bot.fromJson(JsonMap json) => Bot(
    id: Json.string(json, 'id'),
    username: Json.string(json, 'username'),
    difficulty: Json.string(json, 'botDifficulty'),
    userType: Json.string(json, 'userType', 'bot'),
  );

  final String id;
  final String username;

  /// `easy`, `medium`, `hard`, `hard_vince`, `ml`, `drl`, `llm` or `thibot`
  /// (the backend's `botDifficulty`).
  final String difficulty;
  final String userType;
}
