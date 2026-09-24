import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/router.dart';

import 'auth_helpers.dart';
import 'party_helpers.dart';
import 'sse_fakes.dart';

// The create-party name: its refusal waits until the field was edited and
// left, or until Create was tapped — never on a form that just opened.
void main() {
  Future<void> pumpForm(WidgetTester tester, FakeLobbyBackend backend) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ZapZapApp(
        apiConfig: testConfig,
        locale: const Locale('fr'),
        initialLocation: AppRoutes.createParty,
        apiClient: backend.client(),
        tokenStorage: storedSession(validToken),
        sseTransport: FakeSseTransport(),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool enabled(WidgetTester tester) =>
      tester
          .widget<ButtonStyleButton>(find.byKey(const Key('create-submit')))
          .onPressed !=
      null;

  bool posted(FakeLobbyBackend backend) => backend.requests.any(
    (request) => request.method == 'POST' && request.url.path == '/api/party',
  );

  Future<void> leaveField(WidgetTester tester) async {
    tester.binding.focusManager.primaryFocus?.unfocus();
    await tester.pump();
  }

  const required = 'Le nom de la partie est requis';
  const tooShort = 'Le nom doit faire au moins 3 caractères';

  testWidgets('the form opens without an error; Create with no name shows it '
      'and sends nothing', (tester) async {
    final backend = FakeLobbyBackend();
    await pumpForm(tester, backend);
    expect(find.text(required), findsNothing);
    expect(enabled(tester), isTrue);

    await tester.tap(find.byKey(const Key('create-submit')));
    await tester.pumpAndSettle();
    expect(find.text(required), findsOneWidget);
    expect(posted(backend), isFalse);

    // From then on the field is checked live.
    await tester.enterText(find.byKey(const Key('party-name')), 'Soirée');
    await tester.pump();
    expect(find.text(required), findsNothing);
  });

  testWidgets('two characters then leaving the field shows the 3-50 message', (
    tester,
  ) async {
    final backend = FakeLobbyBackend();
    await pumpForm(tester, backend);

    await tester.enterText(find.byKey(const Key('party-name')), ' ab ');
    await tester.pump();
    expect(find.text(tooShort), findsNothing, reason: 'still typing');

    await leaveField(tester);
    expect(find.text(tooShort), findsOneWidget);

    await tester.tap(find.byKey(const Key('create-submit')));
    await tester.pumpAndSettle();
    expect(posted(backend), isFalse);

    await tester.enterText(find.byKey(const Key('party-name')), 'abc');
    await tester.pump();
    expect(find.text(tooShort), findsNothing);
  });

  testWidgets('a field left untouched stays quiet', (tester) async {
    await pumpForm(tester, FakeLobbyBackend());
    await tester.tap(find.byKey(const Key('party-name')));
    await tester.pump();
    await leaveField(tester);
    expect(find.text(required), findsNothing);
  });

  testWidgets('the name takes fifty characters at most', (tester) async {
    await pumpForm(tester, FakeLobbyBackend());
    await tester.enterText(find.byKey(const Key('party-name')), 'x' * 60);
    await tester.pump();
    expect(
      tester
          .widget<TextField>(find.byKey(const Key('party-name')))
          .controller!
          .text,
      'x' * 50,
    );
  });

  testWidgets('Enter on a valid name creates the party', (tester) async {
    final backend = FakeLobbyBackend();
    await pumpForm(tester, backend);
    await tester.enterText(find.byKey(const Key('party-name')), 'Soirée');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();
    expect(backend.bodyOf('POST', '/api/party')['name'], 'Soirée');
  });
}
