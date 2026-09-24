// The host side of `flutter drive`: it runs integration_test/ in the browser
// (or on a device) and reports the result. Procedure: .llmwiki/Testing.md.
import 'package:integration_test/integration_test_driver.dart';

Future<void> main() => integrationDriver();
