import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../l10n/app_localizations.dart';
import '../providers/sse_provider.dart';
import '../utils/app_theme.dart';

/// The real-time connection state as a small Wifi icon, as in the React
/// lobby and game board: green when connected, grey when not.
class ConnectionIndicator extends StatelessWidget {
  const ConnectionIndicator({super.key, this.size = 16});

  /// Tailwind green-400, the React `text-green-400`.
  static const _online = Color(0xFF4ADE80);

  final double size;

  @override
  Widget build(BuildContext context) {
    final connected = context.select<SseProvider, bool>((sse) => sse.connected);
    final l10n = AppLocalizations.of(context);
    final label = connected ? l10n.sseConnected : l10n.sseDisconnected;
    return Tooltip(
      message: label,
      child: Icon(
        connected ? Icons.wifi : Icons.wifi_off,
        size: size,
        color: connected ? _online : AppColors.slate400,
        semanticLabel: label,
      ),
    );
  }
}
