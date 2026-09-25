import 'package:flutter/widgets.dart';

/// Off the web the app draws its own Google button
/// (`GoogleSignInService.platformButton` is `null` there).
Widget googleButton(BuildContext context) =>
    throw UnsupportedError('Google draws its own button on the web only');
