import '../models/admin.dart';
import '../models/json.dart';
import '../services/api_client.dart';

/// `/api/admin`: admin accounts only, else 403 `{success: false, error,
/// code: ADMIN_REQUIRED}`; the routes' own refusals are `{success: false,
/// error}`, without a code.
class AdminRepository {
  const AdminRepository(this._api);

  final ApiClient _api;

  /// `GET /admin/users` (humans only).
  Future<Page<AdminUser>> users({int? limit, int? offset}) async =>
      Page.fromJson(
        await _api.get('/admin/users', query: _paging(limit, offset)),
        'users',
        AdminUser.fromJson,
      );

  /// `DELETE /admin/users/:id` → 400 for oneself or another admin.
  Future<void> deleteUser(String userId) async {
    await _api.delete('/admin/users/$userId');
  }

  /// `POST /admin/users/:id/admin`.
  Future<void> setAdmin(String userId, {required bool isAdmin}) async {
    await _api.post('/admin/users/$userId/admin', body: {'isAdmin': isAdmin});
  }

  /// `GET /admin/parties`, every visibility, optionally one [status].
  Future<Page<AdminParty>> parties({
    String? status,
    int? limit,
    int? offset,
  }) async => Page.fromJson(
    await _api.get(
      '/admin/parties',
      query: {'status': ?status, ..._paging(limit, offset)},
    ),
    'parties',
    AdminParty.fromJson,
  );

  /// `POST /admin/parties/:id/stop` → 400 when already finished.
  Future<void> stopParty(String partyId) async {
    await _api.post('/admin/parties/$partyId/stop');
  }

  /// `DELETE /admin/parties/:id`.
  Future<void> deleteParty(String partyId) async {
    await _api.delete('/admin/parties/$partyId');
  }

  /// `GET /admin/statistics`.
  Future<AdminStatistics> statistics() async =>
      AdminStatistics.fromJson(await _api.get('/admin/statistics'));

  static Map<String, String> _paging(int? limit, int? offset) => {
    if (limit != null) 'limit': '$limit',
    if (offset != null) 'offset': '$offset',
  };
}
