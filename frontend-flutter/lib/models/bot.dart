import 'json.dart';

/// The bot difficulties a lobby seat can take, in the order its "add a bot"
/// menu shows them — the ones the React client offers. `ml` and `drl` exist
/// in the backend but are not offered: they play as `hard`.
const List<String> botDifficulties = [
  'easy',
  'medium',
  'hard',
  'hard_vince',
  'llm',
  'thibot',
];

/// The levels `POST /party/:id/fill-and-start` takes, weakest first: the
/// backend falls back to the next ones when a level runs out.
const List<String> fillDifficulties = ['easy', 'medium', 'hard'];

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
