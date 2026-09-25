import 'dart:convert';
import 'dart:io';

import 'package:zapzap/models/json.dart';

/// The raw text of `test/fixtures/<name>.json`.
///
/// The fixtures are answers captured from a local Node backend (production's
/// backend then; removed since, last at commit `232f168`), seeded with the
/// demo users and the bots, by playing a game with two bots; tokens are
/// replaced by placeholders. `error_*.json` wrap the answer as `{status, body}`.
String fixtureText(String name) =>
    File('test/fixtures/$name.json').readAsStringSync();

JsonMap fixture(String name) =>
    (jsonDecode(fixtureText(name)) as Map).cast<String, dynamic>();

/// An `error_*.json` fixture: its status and its body, re-encoded.
({int status, String body}) errorFixture(String name) {
  final json = fixture(name);
  return (status: json['status'] as int, body: jsonEncode(json['body']));
}
