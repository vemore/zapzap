# FlutterRealtime

> Scope: the Flutter client's real-time channel (SSE): parser, transports, `SseClient`,
> `SseEvent`, `SseProvider`, and presence.
> Related: [[FrontendFlutter]] · [[FlutterAuth]] · [[FlutterParties]] · [[Architecture]] · [[Backend]]
> Updated: 2026-09-29

## Facts

### Real-time channel (SSE)

The server side is fixed ([[Architecture]]): `GET /suscribeupdate[?token=]`. The backend filters
per user ([[Backend]]): events without a party and
a public party's lifecycle events (`playerJoined`, `playerLeft`, `partyStarted`,
`partyDeleted`, `gameFinished`, what `PartyListProvider` reloads on, with `playerReplaced` and `playerForfeited` from the players' own streams) go to every stream, a
game's moves and every event of a private party only to its players' streams — so the
token matters; an initial `event: connected`, then every broadcast as `event:
event` + a JSON object, a `: heartbeat` comment every 20 s, and a `type` on every broadcast (`zapzap-rust/src/api/sse.rs`,
`GameEvent`, `zapzap-rust/src/infrastructure/app_state.rs:230-244`).

- **`SseParser`** (`services/sse_parser.dart`): the `text/event-stream` format, pure, fed
  chunks of any size — `\n`/`\r\n`/`\r` line ends, `:` comments ignored, multi-line `data`
  joined with `\n`, blank-line dispatch (none without data), default name `message`, `id`,
  `retry` (read, not acted on). Emits `SseMessage(event, data, id)`.
- **`SseTransport`** (`services/sse_transport.dart`) opens one connection, never reconnects;
  `createPlatformTransport()` picks it by conditional import (`dart.library.js_interop`):
  - `HttpSseTransport` (`sse_transport_io.dart`, Android): a streamed `package:http`
    request, `Accept: text/event-stream`, UTF-8 → `SseParser`; one `http.Client` per
    connection, closed with it; a non-200 fails; **60 s** without a byte fails (heartbeats
    are every 20 s, so a half-open socket after a network change is noticed).
  - `EventSourceSseTransport` (`sse_transport_web.dart`, PWA): `package:web` `EventSource`,
    a listener on `event` only (the backend names every broadcast so); on `onerror` it closes the source, so the browser's
    own retry never runs alongside ours.
- **`SseClient`** (`services/sse_client.dart`, plain Dart): `connect(token)` opens
  `<sseUri>?token=<jwt>` — with the token the backend registers the user as online, so
  presence works (the removed React client's lobby and board connected tokenless); the same token
  again is a no-op, a new one replaces the connection. On an error or end of stream it
  reopens **3 s** later (`defaultReconnectDelay`, React's `reconnectDelay`), until
  `disconnect()`. A generation counter drops late callbacks of a replaced connection.
  `events` is a broadcast `Stream<SseEvent>`: only `event` events whose data is a
  JSON object (the `connected` greeting is dropped).
- **`SseEvent`** (`models/sse_event.dart`): the payload (`data`) plus `type`, `partyId`,
  `userId`, `action`, `timestamp` through the lenient `Json` readers; `isPresence` for
  `userConnected`/`userDisconnected` (the only presence events `api/sse.rs` sends). A client may get events of other
  parties (public lifecycle ones): a screen keeps those of its
  `partyId`.
- **`SseProvider`** (`providers/sse_provider.dart`, a `ChangeNotifier`): `connect(token)`,
  `disconnect()`, `follow(token?)`, `events`, `connected` (notifies on change). One for the
  whole signed-in session: in `appProviders` a `ChangeNotifierProxyProvider<AuthProvider,
  SseProvider>`, not lazy, calls `follow(auth.isAuthenticated ? auth.token : null)` on every
  `AuthProvider` change — connected on sign-in or a restored session, closed on logout (a
  401 included), reopened when the token changes (`test/sse_session_test.dart`).
  `ZapZapApp(sseTransport:)` swaps the transport for tests.
- The backend subscribes a new stream before it broadcasts `userConnected`, so a client
  hears its own arrival; a user is online while at least one of their streams is open (a
  second tab, or a reconnection whose new stream opens before the old one closes), and only
  the first stream's opening and the last one's closing are broadcast (`sse_handler` and
  `StreamGuard`, `zapzap-rust/src/api/sse.rs`).
- Checked against the local Node backend (2026-09-22): a `play` sent by curl as another user
  reached `HttpSseTransport` (a `dart run` script) and `EventSourceSseTransport` (the web build
  in Chromium); the token's user appeared in `GET /api/players/connected`; after the backend
  was stopped and restarted, the client reconnected 3 s after the drop.

## Decisions & History

- **Presence count (2026-09-24, `fix/flutter-connected-count`).** The app bar read 0 for a
  lone signed-in player on Node: the sign-in `GET /players/connected` answered before the
  stream was registered, and Node broadcast `userConnected` before subscribing the new
  stream, so the client never learnt of itself; any stream of a user closing (a second tab,
  the PWA's first-load reconnection) also removed a user who was still connected. Fixed on
  both sides — Node counts streams per user and subscribes before broadcasting, the client
  reloads the list on each connection — so the client is right against the Rust backend
  too, which keeps the old server behaviour for now.
- **Real-time channel (2026-09-22, `feat/flutter-sse`).** One connection per signed-in
  session with the token, rather than React's one per screen without it: presence needs the
  token, and the stream is global anyway. Two transports because `package:http` on the web
  does not stream a response the way `EventSource` does, and Android has no `EventSource`.
  The reconnection lives in `SseClient`, not in the transports, so both platforms retry on
  the same 3 s and a fake transport tests it. The idle timeout exists only on Android:
  `EventSource` notices a dead connection itself.
