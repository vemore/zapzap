import 'dart:convert';
import 'dart:io';

import 'package:zapzap/models/json.dart';

/// The raw text of `test/fixtures/<name>.json`.
///
/// The fixtures are the Rust backend's answers (`zapzap-rust/`, seeded with
/// `seed --demo`), from a game against EasyBot1 and MediumBot1 played through
/// the API to its end; tokens are replaced by placeholders. Each one's shape
/// (keys and value types) was checked against a capture from that backend
/// on 2026-09-25 (`.llmwiki/FrontendFlutter.md` § Fixtures). `error_*.json`
/// wrap the answer as `{status, body}`.
String fixtureText(String name) =>
    File('test/fixtures/$name.json').readAsStringSync();

JsonMap fixture(String name) =>
    (jsonDecode(fixtureText(name)) as Map).cast<String, dynamic>();

/// An `error_*.json` fixture: its status and its body, re-encoded.
({int status, String body}) errorFixture(String name) {
  final json = fixture(name);
  return (status: json['status'] as int, body: jsonEncode(json['body']));
}
