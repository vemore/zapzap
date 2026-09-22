import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../repositories/admin_repository.dart';
import '../repositories/auth_repository.dart';
import '../repositories/game_repository.dart';
import '../repositories/history_repository.dart';
import '../repositories/party_repository.dart';
import '../repositories/stats_repository.dart';
import '../services/api_client.dart';
import '../services/api_config.dart';
import '../services/sse_transport.dart';
import '../services/token_storage.dart';
import 'auth_provider.dart';
import 'sse_provider.dart';

/// Everything the widget tree can `context.read`/`watch`, in one list.
/// A new provider (auth, lobby, game...) is one more entry here.
///
/// [apiClient] replaces the real client, for tests; otherwise one is built
/// from [apiConfig] and closed with the tree. [tokenStorage] replaces the
/// platform's session storage, [sseTransport] the platform's real-time
/// transport, for tests.
List<SingleChildWidget> appProviders({
  required ApiConfig apiConfig,
  ApiClient? apiClient,
  TokenStorage? tokenStorage,
  SseTransport? sseTransport,
}) => [
  Provider<ApiConfig>.value(value: apiConfig),
  if (apiClient != null)
    Provider<ApiClient>.value(value: apiClient)
  else
    Provider<ApiClient>(
      create: (_) => ApiClient(config: apiConfig),
      dispose: (_, client) => client.close(),
    ),
  Provider<AuthRepository>(
    create: (context) => AuthRepository(context.read<ApiClient>()),
  ),
  // Not lazy: the stored session is read at start-up, while the splash shows.
  ChangeNotifierProvider<AuthProvider>(
    lazy: false,
    create: (context) => AuthProvider(
      repository: context.read<AuthRepository>(),
      apiClient: context.read<ApiClient>(),
      storage: tokenStorage ?? TokenStorage.platform(),
    )..restore(),
  ),
  Provider<PartyRepository>(
    create: (context) => PartyRepository(context.read<ApiClient>()),
  ),
  Provider<GameRepository>(
    create: (context) => GameRepository(context.read<ApiClient>()),
  ),
  Provider<HistoryRepository>(
    create: (context) => HistoryRepository(context.read<ApiClient>()),
  ),
  Provider<StatsRepository>(
    create: (context) => StatsRepository(context.read<ApiClient>()),
  ),
  Provider<AdminRepository>(
    create: (context) => AdminRepository(context.read<ApiClient>()),
  ),
  ChangeNotifierProvider<SseProvider>(
    create: (_) => SseProvider(uri: apiConfig.sseUri, transport: sseTransport),
  ),
];
