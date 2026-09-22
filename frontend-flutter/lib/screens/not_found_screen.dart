import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../l10n/app_localizations.dart';
import '../router.dart';

/// Shown for a path no route matches (a stale link, a typo in the URL bar).
class NotFoundScreen extends StatelessWidget {
  const NotFoundScreen({super.key});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    return Scaffold(
      appBar: AppBar(title: Text(l10n.notFoundTitle)),
      body: Center(
        child: FilledButton(
          onPressed: () => context.go(AppRoutes.home),
          child: Text(l10n.notFoundBackHome),
        ),
      ),
    );
  }
}
