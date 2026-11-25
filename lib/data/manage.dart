import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'api/api_client.dart';
import 'guard.dart';
import 'models.dart';
import 'providers.dart';

/// Community management (admin / manager) data layer. Screens work with raw JSON
/// so every /manage/ endpoint can be driven by the generic resource screens.

/// True for community admins/managers and platform admins.
final isManagerProvider = Provider<bool>((ref) {
  final roles = ref.watch(myRolesProvider).value ?? {};
  return roles.contains('admin') || roles.contains('manager') || roles.contains('platform_admin');
});

final isPlatformAdminProvider = Provider<bool>((ref) => (ref.watch(myRolesProvider).value ?? {}).contains('platform_admin'));

/// Tower names when the user only manages some towers (a tower admin); empty for community admins.
final myManagedTowersProvider = Provider<List<String>>((ref) {
  final data = ref.watch(myRolesDetailProvider).value;
  if (data == null || data['is_platform_admin'] == true) return const [];
  final manager = [
    for (final r in (data['roles'] as List).cast<Json>())
      if (r['role'] == 'admin' || r['role'] == 'manager') r,
  ];
  if (manager.isEmpty || manager.any((r) => (r['towers'] as List? ?? []).isEmpty)) return const [];
  return [for (final r in manager) for (final t in (r['towers'] as List).cast<Json>()) '${t['name']}'];
});

/// True for tower admins: they manage only some towers, not the whole community.
final isTowerAdminProvider = Provider<bool>((ref) => ref.watch(myManagedTowersProvider).isNotEmpty);

/// Communities the signed-in user manages (all of them for a platform admin).
final managedCommunitiesProvider = FutureProvider<List<Json>>((ref) async {
  if (ref.watch(sessionProvider) == null) return [];
  return ref.read(manageApiProvider).listAll('/manage/communities/', community: false);
});

class _SelectedCommunity extends Notifier<String?> {
  @override
  String? build() => null;

  void select(String id) => state = id;
}

final _selectedCommunityProvider = NotifierProvider<_SelectedCommunity, String?>(_SelectedCommunity.new);

/// The community currently being managed (defaults to the first one).
final manageCommunityProvider = Provider<Json?>((ref) {
  final list = ref.watch(managedCommunitiesProvider).value ?? [];
  if (list.isEmpty) return null;
  final id = ref.watch(_selectedCommunityProvider);
  return list.firstWhere((c) => c['id'] == id, orElse: () => list.first);
});

void selectManagedCommunity(WidgetRef ref, String id) {
  ref.read(_selectedCommunityProvider.notifier).select(id);
  ref.invalidate(manageSummaryProvider);
}

final manageSummaryProvider = FutureProvider<Json?>((ref) async {
  final c = ref.watch(manageCommunityProvider);
  if (c == null) return null;
  return await ref.read(apiProvider).get('/manage/summary/', query: {'community': c['id']}) as Json;
});

/// Thin helper over [ApiClient] that adds the selected community where needed.
class ManageApi {
  ManageApi(this.ref);

  final Ref ref;

  ApiClient get _api => ref.read(apiProvider);

  String? get communityId => ref.read(manageCommunityProvider)?['id'] as String?;

  /// Fetches every page of a list endpoint.
  Future<List<Json>> listAll(String path, {Map<String, dynamic>? query, bool community = true}) async {
    final out = <Json>[];
    for (var page = 1; page < 50; page++) {
      final data = await _api.get(path, query: {
        'page_size': 100,
        'page': page,
        if (community && communityId != null) 'community': communityId,
        ...?query,
      });
      if (data is List) return data.cast<Json>();
      final map = data as Json;
      out.addAll((map['results'] as List).cast<Json>());
      if (map['next'] == null) break;
    }
    return out;
  }

  Future<dynamic> post(String path, [Object? body]) => _api.post(path, data: body);

  Future<dynamic> patch(String path, Object? body) => _api.patch(path, data: body);

  Future<void> delete(String path) => _api.delete(path);
}

final manageApiProvider = Provider<ManageApi>(ManageApi.new);
