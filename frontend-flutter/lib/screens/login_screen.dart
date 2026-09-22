import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../router.dart';

/// The login screen. A placeholder until the login form lands.
class LoginScreen extends StatelessWidget {
  const LoginScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.loginTitle),
        leading: BackButton(onPressed: () => context.go(AppRoutes.home)),
      ),
      body: Center(child: Text(l10n.loginComingSoon)),
    );
  }
}
