// Compiled to JavaScript by test/gis_script_guard_test.dart, not a test
// itself: the resolved google_identity_services_web's own loader, run in
// headless Chrome under web/index.html's guard. The script goes to the
// detached element the page names `gisTarget`, so once released it is in
// the page but never fetched.
import 'dart:js_interop';
import 'dart:js_interop_unsafe';

import 'package:google_identity_services_web/loader.dart';
import 'package:web/web.dart' as web;

void main() {
  loadWebSdk(target: globalContext['gisTarget'] as web.HTMLElement);
}
