import 'package:flutter/material.dart';
import 'package:flutter_web_plugins/url_strategy.dart';

import 'app.dart';
import 'services/api_config.dart';

void main() {
  // Path URLs on the web (/app/parties, not /app/#/parties), so a route is a
  // real deep link: the page's <base href="/app/"> is stripped to find it, and
  // nginx's SPA fallback serves index.html for it. A no-op off the web.
  usePathUrlStrategy();
  runApp(ZapZapApp(apiConfig: ApiConfig.fromEnvironment()));
}
