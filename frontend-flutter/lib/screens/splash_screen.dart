import 'package:flutter/material.dart';

import '../l10n/app_localizations.dart';
import '../widgets/app_logo.dart';

/// Start-up, while the stored session is read (`AuthProvider.restore`);
/// the router leaves it as soon as that is done.
class SplashScreen extends StatelessWidget {
  const SplashScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const AppLogo(),
            const SizedBox(height: 24),
            CircularProgressIndicator(
              semanticsLabel: AppLocalizations.of(context).splashLoading,
            ),
          ],
        ),
      ),
    );
  }
}
