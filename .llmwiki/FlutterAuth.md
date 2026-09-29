# FlutterAuth

> Scope: the Flutter client's session (`AuthProvider`, token storage), the login and register
> screens, the routing guard, and Google sign-in on the web and on Android.
> Related: [[FrontendFlutter]] · [[FlutterParties]] · [[FlutterAndroidPwa]] · [[Api]] · [[Frontend]]
> Updated: 2026-09-29

## Facts

### Authentication (`providers/auth_provider.dart`, `services/token_storage*.dart`, `router.dart`)

- **`AuthProvider`** (a `ChangeNotifier`, in `appProviders()`, not lazy): `user`, `token`
  (`null` signed out), `isAuthenticated` (a user and a token whose `exp` is still ahead —
  re-checked on every read, so a session that expires while the app runs stops counting
  at the next navigation), `isAdmin`, `isRestored`; `restore()`, `login`, `register`,
  `logout`, `rename(username)` (`PATCH /auth/me`: the new token and user replace the
  session and are stored, as a sign-in's are), `changePassword({newPassword,
  currentPassword, credential})` (the session goes on; a Google account without a password
  is stored as having one since), `deleteAccount({password, credential})` (the call, then `logout`: the stored
  session erased and the router on the login screen; a refusal throws, still signed in). It keeps `ApiClient.token` in step and owns `ApiClient.onUnauthorized`.
  `logout` is idempotent — the first of several parallel 401s does the work, the others
  return — clears the storage, and signs out of Google (`GoogleSignInService.signOut`, not
  awaited and its failure only logged: the session is closed either way). Other state that depends on the session (the SSE
  connection) listens to it and follows `token`; this provider knows nothing of SSE.
- **Start-up**: `restore()` reads the stored session; an expired, undecodable or
  `exp`-less token, or an unreadable user, is erased (`utils/jwt.dart`: payload decoded
  without checking the signature — the backend does that). Until it is done the router
  holds on `/splash`.
- **Storage** (`TokenStorage.platform()`, conditional import on `dart.library.js_interop`):
  `flutter_secure_storage` on Android (`token_storage_io.dart`), `shared_preferences` on
  the web (`token_storage_web.dart`, localStorage, keys prefixed `flutter.` by the plugin —
  no clash with the React client's own `token` on the same origin). Keys `token` and `user`
  (JSON of `User.toJson()`), those of the React client. `MemoryTokenStorage` for tests.
  `User.hasPassword` comes from `/auth/google` and `PATCH /auth/me`; login and register
  prove one, and a session stored before the field reads it as "not a Google account".
- **Screens**: login (`Login.jsx`) only requires both fields — as React, so an account
  that predates the rules still signs in; register (`Register.jsx`) checks the rules of
  `auth.js:42-88` (`utils/validators.dart`: username trimmed, 3-30,
  `^[a-zA-Z0-9_-]+$`; password 6-100, not trimmed). **Validate on touch or submit**
  (`FieldTouch`, also on the create-party name): a field shows its refusal once edited and
  left, or when submit is tapped, then live — never on a form just opened. Submit stays
  amber and active; a click with a field refused marks it, focuses it and sends nothing
  (C2). Both share `AuthCard` (`widgets/auth_form.dart`): the logo with its one-line pitch
  (`AppLogo(pitch: true)`, `authPitch`) above the title (C1); the fields in one
  `AutofillGroup`, Next moving on and Done submitting, the password with an eye
  (`AuthPasswordField`) (C3); a spinner in the button while the call runs, then the
  refusal in a red `ErrorBanner` (live region) just above the button (C4). The username
  is sent trimmed. Server refusals map from
  `ApiException.code`: `INVALID_CREDENTIALS`, `USERNAME_EXISTS`, no response
  (`NETWORK_ERROR`/`TIMEOUT`), else a generic text. Success navigates by itself: the router
  follows `AuthProvider`.
- **Routing guard** (`authRedirect(auth, uri)`, run on every navigation and on every
  `AuthProvider` change via `refreshListenable`): not restored → `/splash?from=<path>`;
  signed out → public routes (`/`, `/login`, `/register`) stay, anything else →
  `/login?from=<path>`; signed in → `/`, `/login`, `/register` lead to `from` or
  `/parties`; `/admin` and `/admin/**` need `isAdmin`, else `/parties` (the admin screen,
  Admin in [[FlutterHistoryAdmin]]); `/tutorial` stays, signed in or out. `from` is only
  followed when it is a local path (`/x`, not `//host` or a scheme). An unknown path shows
  the not-found screen, signed in or out (`test/app_test.dart`). React's
  `ProtectedRoute` checks only that a token exists, never its expiry
  (`frontend/src/components/Auth/ProtectedRoute.jsx:5`). On the web the route is the URL
  path under the base href (`/app/parties`): `lib/main.dart` calls `usePathUrlStrategy()`
  (`flutter_web_plugins`) before `runApp`, a no-op off the web; the browser path less
  `/app/` is go_router's initial route, which wins over `initialLocation`
  (`test/deep_link_test.dart`). A `push`ed screen shows its own path in the address bar:
  `createRouter` sets `GoRouter.optionURLReflectsImperativeAPIs = true` (go_router's
  default keeps the path of the screen below), so a reload of `/app/parties/new`, a lobby
  or a game stays on it and a lobby's URL can be shared (`test/deep_link_test.dart`, `the
  URL of a pushed screen`).

### Google sign-in (`services/google_sign_in_service.dart`, `widgets/google_sign_in_section.dart`)

- **Off unless the build names a client id**: `--dart-define=GOOGLE_CLIENT_ID=<web client
  id>`. Without it `GoogleSignInConfig` is disabled, `appProviders()` provides
  `DisabledGoogleSignIn`, and login and register show no Google button and no "ou" rule —
  as React hides its button without `VITE_GOOGLE_OAUTH_CLIENT_ID`.
- **Both platforms ask for the web client id's token**: the backend (since #71) checks the ID
  token's audience against its `GOOGLE_OAUTH_CLIENT_ID`, the web client. On the web it is
  GIS's `clientId`; on Android it is `serverClientId` (`GoogleSignInConfig.resolve`), the
  Android OAuth client only identifying the app ([[FlutterAndroidPwa]]). Other platforms: disabled.
- **The flow** (`google_sign_in` 7): every token arrives on `GoogleSignInService.idTokens`.
  On the web the token only comes out of Google's own button (`authenticate()` is not
  supported there): `platformButton` is the GIS `renderButton` (filled black, large,
  "continue with", rectangular — React's), imported only on the web
  (`google_sign_in_button_web.dart` / `_stub.dart`, conditional on `dart.library.js_interop`).
  On Android the app draws an outlined "Continuer avec Google" button (`Key('google-sign-in')`)
  that calls `signIn()` → `authenticate()` (Credential Manager). A closed dialog
  (`canceled`, `interrupted`) says nothing; any other failure is a `GoogleSignInFailure` —
  on `idTokens` for the plugin's own `GoogleSignInException`s, thrown by `signIn()` for
  the rest (a failed initialisation, a platform error), and shown by the section either way.
- **Google's web button is built once** (per locale), in the section's
  `didChangeDependencies`: the GIS plugin keys its `FutureBuilder` on
  `GSIButtonConfiguration.hashCode`, which the class does not override, so a button built
  in `build` re-rendered Google's iframe at every keystroke in the fields.
- **A token that arrives while the password form is being sent is dropped**
  (`GoogleSignInSection.enabled` false): Google's web button cannot be disabled.
- `GoogleSignInSection` (above the fields of login **and** register, as React) posts each
  token as `credential` to `POST /auth/google` through `AuthProvider.loginWithGoogle`; the
  router then leaves the screen as after a password login. A refusal — Google's side, or
  the backend's `GOOGLE_AUTH_FAILED`/`GOOGLE_AUTH_ERROR` — shows `authErrorGoogle` in the
  screen's red banner; no response shows the network text. `isNewUser` is not read.
- The plugin is initialised once, on first use (web: `initialize()` twice throws).
- **Google's GIS script loads on first use only**: the web plugin inserts
  `accounts.google.com/gsi/client` when it registers, before `main`, in every build.
  `web/index.html` holds that script element back (an inline `Node.prototype.appendChild`
  guard placed before `flutter_bootstrap.js`) until `window.zapzapLoadGoogleScript()`,
  which `PluginGoogleSignInService` calls on first use (`google_sign_in_script_web.dart`)
  and which puts the browser's own `appendChild` back (unless something wrapped it since).
  So a build without a client id never contacts accounts.google.com, and a build with one
  only once the login or register screen shows — not on the home screen, not on a restored
  session or the game table. The guard only sees `appendChild`, which the resolved
  `google_identity_services_web` loader (`loadWebSdk`) uses: `test/gis_script_guard_test.dart`
  compiles that loader to JavaScript (`test/gis_guard/load_gis.dart`) and runs it under
  the guard, as `index.html` has it, in headless Chrome (`CHROME_EXECUTABLE`, else
  `google-chrome` on the PATH), no host resolvable — so a plugin version that inserts the
  script any other way fails the test; it also checks `google_sign_in_web` loads GIS only
  through `loadWebSdk`.
- **The section falls back when Google is not ready**: it waits for
  `GoogleSignInService.ready()` (the plugin's initialisation) up to
  `GoogleSignInSection.readyTimeout`, 8 s; on a timeout (GIS blocked by an ad blocker or
  unreachable: the plugin's init then never completes, its "Getting ready" placeholder
  stays) or a failed initialisation it collapses — button, "ou" rule and spacing —, with
  no banner, and the next screen starts without it. If Google gets ready later after all,
  the section comes back. A failed initialisation is not also put on `idTokens`.
- **Logout signs out of Google**, so on a shared device the next person is not offered the
  previous account — also after a restored session, the usual logout, where Google was not
  used in this run. On **Android** `signOut` then initialises the plugin first and signs
  out (Credential Manager's `clearCredentialState`), whatever the session's kind: the
  credential state belongs to the device, and the call is local. On the **web** it stays a
  no-op until GIS is loaded in this run (`GoogleSignInConfig.usesGis`): GIS's sign-out,
  `disableAutoSelect`, only stops One Tap's automatic sign-in, which the app never asks for
  (no `attemptLightweightAuthentication`); the "Continue as …" of Google's button comes
  from Google's own cookies, which no client call clears. Loading GIS at logout would
  contact accounts.google.com for nothing (`test/google_sign_in_plugin_test.dart`, group
  `signOut before any use in this run`).
- **Tests** fake Google (`FakeGoogleSignIn` in `test/google_fakes.dart`, passed as
  `ZapZapApp(googleSignIn:)`); the real flow needs an authorised origin or a registered
  signing key, so it is checked by hand ([[FlutterAndroidPwa]]).

## Decisions & History

- **Google sign-in with the web client id on both platforms (2026-09-24,
  `feat/flutter-google-signin`).** The backend accepts one audience, the web client; asking
  Android for a token issued to `serverClientId` keeps both backends unchanged, and the
  Android OAuth client carries no secret — only the package and the signing key's SHA-1 —
  so nothing enters the repository. The client id is a build argument rather than a
  runtime setting: the web plugin needs it before the first frame, and the React image
  already receives it that way. The section sits on register as well as login because
  React has it on both, and a Google sign-in is a sign-up for a new account. Checked by
  hand: the PWA image built with the id draws Google's button at `/app/login` (GIS answers
  "origin not allowed" on `localhost:9531`, as expected: only the production origin is
  authorised); the image without it draws none; the debug APK builds with the id. Not
  checked: a real sign-in on the web (needs the production origin) and on Android (no
  emulator usable here).
- **Session and guard (2026-09-22, `feat/flutter-auth`).** The guard checks the JWT's `exp`,
  which React never does, so an expired session goes to login instead of failing on its
  first call. The router follows `AuthProvider` (`refreshListenable`) rather than screens
  navigating after login or logout, so a 401 anywhere lands on login the same way a logout
  does. The splash route exists so a deep link survives the asynchronous storage read at
  start-up. Secure storage on Android only: the web has no secure store, and the React
  client keeps the same token in localStorage.
- **Google's section falls back, logout signs out of Google, GIS loads on first use
  (2026-09-25, `fix/flutter-google-gis`).** With GIS blocked the plugin's `init` awaits a
  script load that never completes (`loadWebSdk` has no error path), so the section times
  out itself; 8 s leaves a slow phone time to fetch GIS. The plugin's constructor loads
  GIS at registration, before any Dart of ours runs, with no switch outside tests
  (`debugOverrideLoader`), and `index.html` cannot see a `--dart-define`: the page holds
  the script element and the app releases it. Releasing on first use rather than in
  `main` when a client id is set also spares the home screen and the game table the
  third-party request. Checked in headless Chromium (the PR's network log): without the id
  no request to accounts.google.com, with it none on the home screen and GIS plus its
  button iframe once the login screen shows; with accounts.google.com blocked the section
  collapses after 8 s.
- **Logout after a restored session, and the guard's release (2026-09-28,
  `fix/flutter-google-signout`).** `signOut` returned when Google was not initialised in
  this run, so the logout of a restored session — the usual one — never reached Credential
  Manager. Android now initialises to sign out, for every session rather than only a
  stored Google one (`User.isGoogleUser`): nothing to store, and a password session after
  a Google one that never signed out is covered too. The web keeps the no-request goal
  of #112: nothing GIS undoes applies to this app. The guard's `appendChild` stayed
  replaced all session and was pinned by the text of `index.html` only; it is now handed
  back on release, and the plugin's loader is run under it for real. `flutter test
  --platform chrome` was the other way, but its server serves only `test/` and packages,
  not `web/index.html`; a VM test driving `dart compile js` and headless Chrome takes
  about 3 s. Checked in headless Chromium on both builds (`flutter build web --base-href
  /app/`): without the id no request to accounts.google.com on `/app/`, `/app/login`,
  `/app/register`; with one, none on `/app/`, GIS on login and register with the
  browser's own `appendChild` afterwards.
- **Deleting one's own account (2026-09-25, `feat/delete-own-account`).** Google Play wants
  an app that creates accounts to delete them from inside it: the entry sits in the app-bar
  menu of every signed-in screen, not on a profile screen the app does not have. The
  confirmation is the password, or for a Google account a fresh Google token — the client
  knows which from the stored `isGoogleUser`. The backend answers a refusal with 403/409,
  never 401, so a wrong password does not sign out through `onUnauthorized`. Deleted players
  are anonymised, not erased (the user's decision): the history names them from the
  `deleted-` id prefix.
- **The account page (2026-09-29, `feat/account-page`).** A player could only delete the
  account: no rename, no password change, and a Google account could never add a password.
  The menu's « Supprimer mon compte » became « Mon compte », a routed page
  ([[FlutterParties]] § The app-bar menu) — a route rather than a sheet, so the PWA has
  `/app/account` to point the old web URL at later. The rename keeps the session: the
  backend answers a new token, stored as a sign-in's. `User.hasPassword` was added because
  `isGoogleUser` alone cannot tell a Google account that set a password; the delete dialog
  still offers Google to every Google account, which the backend accepts from an account
  with both ([[Api]]). The Google confirmation moved into `widgets/google_confirmation.dart`,
  shared by the delete and password dialogs, so both give up on Google the same way.
