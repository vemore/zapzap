import 'package:flutter/material.dart';

import 'app.dart';
import 'services/api_config.dart';

void main() {
  runApp(ZapZapApp(apiConfig: ApiConfig.fromEnvironment()));
}
