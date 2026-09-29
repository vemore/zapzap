import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:zapzap/app.dart';
import 'package:zapzap/l10n/app_localizations.dart';
import 'package:zapzap/models/user.dart';
import 'package:zapzap/providers/auth_provider.dart';
import 'package:zapzap/repositories/auth_repository.dart';
import 'package:zapzap/router.dart';
import 'package:zapzap/screens/account_screen.dart';
import 'package:zapzap/screens/home_screen.dart';
import 'package:zapzap/screens/login_screen.dart';
import 'package:zapzap/screens/parties_screen.dart';
import 'package:zapzap/services/token_storage.dart';
import 'package:zapzap/services/tutorial_offer_store.dart';
import 'package:zapzap/widgets/guest_banner.dart';

import 'auth_helpers.dart';
import 'party_helpers.dart';
import 'sse_fakes.dart';

const _bannerFr =
    'Enregistre ton compte et mets un mot de passe pour garder tes parties '
    "d'un appareil à l'autre.";
const _browserFr =
    "Ce compte n'existe que dans ce navigateur : il sera perdu si ses données "
    'sont effacées.';

void main() {
  /// A storage holding the guest session of [FakeLobbyBackend.guestUser] and
  /// its credentials.
  MemoryTokenStorage guestSession(FakeLobbyBackend backend) =>
      MemoryTokenStorage({
        TokenStorage.tokenKey: backend.guestToken,
        TokenStorage.userKey: jsonEncode(FakeLobbyBackend.guestUser),
        TokenStorage.guestKey: jsonEncode({
          'userId': 'g1',
          'username': 'Guest_12345',
          'password': FakeLobbyBackend.guestPassword,
        }),
      });

  Future<void> pumpApp(
    WidgetTester tester, {
    required FakeLobbyBackend backend,
    required MemoryTokenStorage storage,
    String initialLocation = AppRoutes.home,
    TutorialOfferStore? offer,
  }) async {
    tester.view.physicalSize = const Size(1000, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      ZapZapApp(
        apiConfig: testConfig,
        locale: const Locale('fr'),
        initialLocation: initialLocation,
        apiClient: backend.client(),
        tokenStorage: storage,
        sseTransport: FakeSseTransport(),
        tutorialOffer: offer,
      ),
    );
    await tester.pumpAndSettle();
  }

  String locationOf(WidgetTester tester) =>
      GoRouter.of(tester.element(find.byType(Scaffold).first)).state.uri.path;

  Future<void> openMenuEntry(WidgetTester tester, String key) async {
    await tester.tap(find.byKey(const Key('app-bar-menu')));
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(Key(key)));
    await tester.pumpAndSettle();
  }

  group('« Jouer sans compte »', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    testWidgets('home → « Jouer sans compte » → the parties with the guest '
        'warning, whose button opens the account page; reachable after the '
        "tutorial offer's Later", (tester) async {
      final backend = FakeLobbyBackend();
      final storage = MemoryTokenStorage();
      await pumpApp(
        tester,
        backend: backend,
        storage: storage,
        offer: PreferencesTutorialOfferStore(),
      );

      // The first opening offers the example game; Later leaves the home
      // screen with both ways in.
      await tester.tap(find.text('Plus tard'));
      await tester.pumpAndSettle();
      expect(find.byType(HomeScreen), findsOneWidget);
      expect(find.text('Se connecter'), findsOneWidget);

      await tester.tap(find.text('Jouer sans compte'));
      await tester.pumpAndSettle();

      expect(
        backend.requests.where((r) => r.url.path == '/api/auth/guest'),
        hasLength(1),
      );
      expect(find.byType(PartiesScreen), findsOneWidget);
      expect(locationOf(tester), AppRoutes.parties);
      expect(find.byKey(const Key('guest-banner')), findsOneWidget);
      expect(find.text(_bannerFr), findsOneWidget);
      // Not the web build: nothing about the browser
      expect(find.textContaining('navigateur'), findsNothing);

      // The session and the guest's way back in are stored
      expect(storage.values[TokenStorage.tokenKey], backend.guestToken);
      expect(jsonDecode(storage.values[TokenStorage.guestKey]!), {
        'userId': 'g1',
        'username': 'Guest_12345',
        'password': FakeLobbyBackend.guestPassword,
        'active': true,
      });

      await tester.tap(find.text('Enregistrer mon compte'));
      await tester.pumpAndSettle();
      expect(find.byType(AccountScreen), findsOneWidget);
      expect(locationOf(tester), AppRoutes.account);
      // The warning again, without a button to the page it is on
      expect(find.byKey(const Key('guest-banner')), findsOneWidget);
      expect(find.byKey(const Key('guest-banner-register')), findsNothing);
      expect(find.text('Guest_12345'), findsWidgets);
      expect(
        find.text('Compte invité, gardé sur cet appareil'),
        findsOneWidget,
      );
      expect(find.text('Choisir un mot de passe'), findsOneWidget);
    });

    testWidgets('a refusal past the rate limit says so on the home screen, '
        'signed out', (tester) async {
      final backend = FakeLobbyBackend();
      backend.failures['POST /api/auth/guest'] = (
        status: 429,
        body: {'error': 'Too many guest accounts', 'code': 'RATE_LIMITED'},
      );
      await pumpApp(tester, backend: backend, storage: MemoryTokenStorage());

      await tester.tap(find.byKey(const Key('home-guest')));
      await tester.pumpAndSettle();

      expect(find.byType(HomeScreen), findsOneWidget);
      expect(
        find.text(
          'Trop de comptes invités ont été créés depuis ce réseau. '
          'Réessaie plus tard, ou crée un compte.',
        ),
        findsOneWidget,
      );
      // The button can be tried again
      final button = tester.widget<ButtonStyleButton>(
        find.byKey(const Key('home-guest')),
      );
      expect(button.onPressed, isNotNull);
    });

    testWidgets('a player who is not a guest sees no warning', (tester) async {
      final backend = FakeLobbyBackend();
      await pumpApp(
        tester,
        backend: backend,
        storage: storedSession(validToken),
        initialLocation: AppRoutes.parties,
      );
      expect(find.byType(PartiesScreen), findsOneWidget);
      expect(find.byKey(const Key('guest-banner')), findsNothing);
    });
  });

  group('signing out as a guest', () {
    testWidgets('warns that the account will be lost; confirmed, the '
        "device forgets the guest's password", (tester) async {
      final backend = FakeLobbyBackend();
      final storage = guestSession(backend);
      await pumpApp(
        tester,
        backend: backend,
        storage: storage,
        initialLocation: AppRoutes.parties,
      );

      await openMenuEntry(tester, 'menu-logout');
      expect(find.byKey(const Key('logout-dialog')), findsOneWidget);
      expect(
        tester.widget<Text>(find.byKey(const Key('logout-body'))).data,
        'Tu joues sans compte enregistré : si tu te déconnectes, ce compte et '
        'tes parties seront perdus. Pour les garder, choisis d\'abord un mot '
        'de passe dans « Mon compte ».',
      );
      expect(find.text('Me déconnecter et perdre le compte'), findsOneWidget);

      // Cancel keeps everything
      await tester.tap(find.byKey(const Key('logout-cancel')));
      await tester.pumpAndSettle();
      expect(find.byType(PartiesScreen), findsOneWidget);
      expect(storage.values[TokenStorage.guestKey], isNotNull);

      await openMenuEntry(tester, 'menu-logout');
      await tester.tap(find.byKey(const Key('logout-confirm')));
      await tester.pumpAndSettle();
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(storage.values, isEmpty);
    });

    testWidgets('an account that is not a guest keeps the usual words', (
      tester,
    ) async {
      await pumpApp(
        tester,
        backend: FakeLobbyBackend(),
        storage: storedSession(validToken),
        initialLocation: AppRoutes.parties,
      );
      await openMenuEntry(tester, 'menu-logout');
      expect(
        tester.widget<Text>(find.byKey(const Key('logout-body'))).data,
        'Tu devras te reconnecter pour jouer.',
      );
      expect(find.text('Se déconnecter'), findsWidgets);
    });
  });

  group('the account page of a guest', () {
    testWidgets('choosing a password claims the account, confirmed by the '
        'stored one unseen; the device then forgets it and the warning goes', (
      tester,
    ) async {
      final backend = FakeLobbyBackend()
        ..passwordChangedUser = {
          ...FakeLobbyBackend.guestUser,
          'isGuest': false,
        };
      final storage = guestSession(backend);
      await pumpApp(
        tester,
        backend: backend,
        storage: storage,
        initialLocation: AppRoutes.account,
      );
      expect(find.byKey(const Key('guest-banner')), findsOneWidget);

      await tester.tap(find.byKey(const Key('account-password')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('change-password-dialog')), findsOneWidget);
      // Nothing to type but the new password
      expect(find.byKey(const Key('change-password-current')), findsNothing);
      await tester.enterText(
        find.byKey(const Key('change-password-new')),
        'mon-secret',
      );
      await tester.pump();
      await tester.tap(find.byKey(const Key('change-password-confirm')));
      await tester.pumpAndSettle();

      expect(backend.bodyOf('PUT', '/api/auth/me/password'), {
        'newPassword': 'mon-secret',
        'currentPassword': FakeLobbyBackend.guestPassword,
      });
      expect(
        find.text(
          'Compte enregistré. Connecte-toi avec ton pseudo et ce mot de passe '
          'sur tes autres appareils.',
        ),
        findsOneWidget,
      );
      expect(storage.values[TokenStorage.guestKey], isNull);
      expect(
        (jsonDecode(storage.values[TokenStorage.userKey]!) as Map)['isGuest'],
        isFalse,
      );
      expect(find.byKey(const Key('guest-banner')), findsNothing);
      expect(find.text('Connexion par mot de passe'), findsOneWidget);

      // Signing out now is an ordinary sign-out
      await openMenuEntry(tester, 'menu-logout');
      expect(
        tester.widget<Text>(find.byKey(const Key('logout-body'))).data,
        'Tu devras te reconnecter pour jouer.',
      );
    });

    testWidgets('the deletion is confirmed by the stored password, nothing '
        'typed', (tester) async {
      final backend = FakeLobbyBackend();
      final storage = guestSession(backend);
      await pumpApp(
        tester,
        backend: backend,
        storage: storage,
        initialLocation: AppRoutes.account,
      );

      await tester.tap(find.byKey(const Key('account-delete')));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('delete-account-password')), findsNothing);
      await tester.tap(find.byKey(const Key('delete-account-confirm')));
      await tester.pumpAndSettle();

      expect(backend.bodyOf('DELETE', '/api/auth/me'), {
        'password': FakeLobbyBackend.guestPassword,
      });
      expect(find.byType(LoginScreen), findsOneWidget);
      expect(storage.values, isEmpty);
    });
  });

  group('the warning on the web', () {
    Future<void> pumpBanner(WidgetTester tester, {required bool web}) async {
      final api = unusedApi();
      final auth = AuthProvider(
        repository: AuthRepository(api),
        apiClient: api,
        storage: MemoryTokenStorage({
          TokenStorage.tokenKey: validToken,
          TokenStorage.userKey: jsonEncode(
            const User(
              id: 'g1',
              username: 'Guest_12345',
              isGuest: true,
            ).toJson(),
          ),
        }),
      );
      await auth.restore();
      await tester.pumpWidget(
        ChangeNotifierProvider<AuthProvider>.value(
          value: auth,
          child: MaterialApp(
            locale: const Locale('fr'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            home: Scaffold(body: GuestBanner(web: web)),
          ),
        ),
      );
    }

    testWidgets('says the account lives only in this browser', (tester) async {
      await pumpBanner(tester, web: true);
      expect(
        tester.widget<Text>(find.byKey(const Key('guest-banner-text'))).data,
        '$_bannerFr $_browserFr',
      );
    });

    testWidgets('the app does not', (tester) async {
      await pumpBanner(tester, web: false);
      expect(
        tester.widget<Text>(find.byKey(const Key('guest-banner-text'))).data,
        _bannerFr,
      );
    });
  });
}
