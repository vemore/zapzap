import 'package:provider/provider.dart';
import 'package:provider/single_child_widget.dart';

import '../services/api_config.dart';

/// Everything the widget tree can `context.read`/`watch`, in one list.
/// A new provider (auth, lobby, game...) is one more entry here.
List<SingleChildWidget> appProviders({required ApiConfig apiConfig}) => [
  Provider<ApiConfig>.value(value: apiConfig),
];
