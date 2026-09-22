import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:zapzap/l10n/app_localizations.dart';
import 'package:zapzap/providers/sse_provider.dart';
import 'package:zapzap/widgets/connection_indicator.dart';

import 'sse_fakes.dart';

void main() {
  testWidgets('shows the Wifi state of the real-time channel', (tester) async {
    final transport = FakeSseTransport();
    final sse = SseProvider(
      uri: Uri.parse('http://localhost:9999/suscribeupdate'),
      transport: transport,
    );
    addTearDown(sse.dispose);

    await tester.pumpWidget(
      ChangeNotifierProvider<SseProvider>.value(
        value: sse,
        child: const MaterialApp(
          locale: Locale('fr'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(body: ConnectionIndicator()),
        ),
      ),
    );
    expect(find.byIcon(Icons.wifi_off), findsOneWidget);
    expect(find.byTooltip('Temps réel déconnecté'), findsOneWidget);

    sse.connect('jwt');
    transport.last.open();
    await tester.pump();
    expect(find.byIcon(Icons.wifi), findsOneWidget);
    expect(find.byTooltip('Temps réel connecté'), findsOneWidget);

    sse.disconnect();
    await tester.pump();
    expect(find.byIcon(Icons.wifi_off), findsOneWidget);
  });
}
