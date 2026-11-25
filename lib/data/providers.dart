import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_riverpod/misc.dart' show FutureProviderFamily;
import 'package:image_picker/image_picker.dart' show XFile;

import '../core/utils/formatters.dart';
import 'api/api_client.dart';
import 'api/token_store.dart';
import 'models.dart';

// ---------------------------------------------------------------------------
// Infrastructure
// ---------------------------------------------------------------------------

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());
final apiProvider = Provider<ApiClient>((ref) => ApiClient(ref.watch(tokenStoreProvider)));

/// The signed-in user (null = signed out).
class SessionNotifier extends Notifier<UserProfile?> {
  @override
  UserProfile? build() => null;

  ApiClient get _api => ref.read(apiProvider);
  TokenStore get _tokens => ref.read(tokenStoreProvider);

  /// Restores a saved session. Returns false when there is none or it expired.
  /// Throws [ApiException] without status code when the server is unreachable.
  Future<bool> restore() async {
    await _tokens.load();
    if (_tokens.access == null) return false;
    try {
      state = UserProfile.fromJson(await _api.get('/me/') as Json);
      return true;
    } on ApiException catch (e) {
      if (e.statusCode == null) rethrow;
      await _tokens.clear();
      return false;
    }
  }

  /// Sends an OTP. Returns the code in development (DEBUG backend) for convenience.
  Future<String?> requestOtp(String phone) async {
    final res = await _api.post('/auth/otp/request/', data: {'phone': phone}, auth: false) as Json;
    return res['debug_code'] as String?;
  }

  /// Returns true when a new account was created. [fullName] names a new account.
  Future<bool> verifyOtp(String phone, String code, {String? fullName}) async {
    final res = await _api.post('/auth/otp/verify/',
        data: {'phone': phone, 'code': code, 'full_name': ?fullName}, auth: false) as Json;
    await _signIn(res);
    return res['is_new_user'] == true;
  }

  /// Applies sign-up details after the phone is verified.
  Future<void> completeSignup(PendingSignup s) async {
    final user = state;
    if (user == null) return;
    if (s.name.isNotEmpty || s.email.isNotEmpty) {
      await updateProfile(name: s.name.isNotEmpty ? s.name : user.name, email: s.email.isNotEmpty ? s.email : user.email);
    }
    if (s.password.isNotEmpty) await _api.post('/me/password/', data: {'new_password': s.password});
  }

  Future<void> loginWithPassword(String identifier, String password) async {
    final res = await _api.post('/auth/login/', data: {'identifier': identifier, 'password': password},
        auth: false) as Json;
    await _signIn(res);
  }

  Future<void> _signIn(Json res) async {
    await _tokens.saveTokens(res['access'] as String, res['refresh'] as String?);
    state = UserProfile.fromJson(res['user'] as Json);
  }

  Future<void> updateProfile({required String name, required String email}) async {
    state = UserProfile.fromJson(await _api.patch('/me/', data: {'full_name': name, 'email': email}) as Json);
  }

  Future<void> updateAvatar(XFile photo) async {
    state = UserProfile.fromJson(await _api.upload('/me/', files: {'avatar': photo}, patch: true) as Json);
  }

  Future<void> logout() async {
    try {
      if (_tokens.refresh != null) await _api.post('/auth/logout/', data: {'refresh': _tokens.refresh});
    } catch (_) {}
    await _tokens.clear();
    state = null;
  }

  /// Called when the refresh token is no longer valid.
  void expired() => state = null;
}

final sessionProvider = NotifierProvider<SessionNotifier, UserProfile?>(SessionNotifier.new);

/// Details entered on the sign-up screen, applied once the OTP is verified.
class PendingSignup {
  const PendingSignup({required this.name, required this.email, required this.password});

  final String name;
  final String email;
  final String password;
}

class PendingSignupNotifier extends Notifier<PendingSignup?> {
  @override
  PendingSignup? build() => null;
  void set(PendingSignup? value) => state = value;
}

final pendingSignupProvider = NotifierProvider<PendingSignupNotifier, PendingSignup?>(PendingSignupNotifier.new);

final userProvider = Provider<UserProfile>((ref) =>
    ref.watch(sessionProvider) ?? const UserProfile(id: '', name: 'Guest', phone: '', email: ''));

final countriesProvider = FutureProvider<List<CountryOption>>(
    (ref) => ref.read(apiProvider).list('/countries/', CountryOption.fromJson));

// ---------------------------------------------------------------------------
// Properties & selected unit
// ---------------------------------------------------------------------------

final propertiesProvider = FutureProvider<List<Property>>((ref) async {
  if (ref.watch(sessionProvider) == null) return [];
  return ref.read(apiProvider).list('/me/units/', Property.fromJson);
});

class SelectedUnitNotifier extends Notifier<String?> {
  @override
  String? build() => ref.read(tokenStoreProvider).unitId;

  void select(String unitId) {
    state = unitId;
    ref.read(tokenStoreProvider).saveUnit(unitId);
  }
}

final selectedUnitProvider = NotifierProvider<SelectedUnitNotifier, String?>(SelectedUnitNotifier.new);

/// The approved unit the app is showing (selected one, else the first approved).
final currentPropertyProvider = FutureProvider<Property?>((ref) async {
  final approved = (await ref.watch(propertiesProvider.future)).where((p) => p.isApproved).toList();
  if (approved.isEmpty) return null;
  final selected = ref.watch(selectedUnitProvider);
  return approved.firstWhere((p) => p.id == selected, orElse: () => approved.first);
});

final unitIdProvider = FutureProvider<String>((ref) async {
  final p = await ref.watch(currentPropertyProvider.future);
  if (p == null) throw ApiException('Your unit is awaiting approval. Join or wait for management to approve.');
  return p.id;
});

/// Country/community settings for the selected unit; also sets the default display currency.
final contextProvider = FutureProvider<AppContext>((ref) async {
  final unit = await ref.watch(unitIdProvider.future);
  final ctx = AppContext.fromJson(await ref.read(apiProvider).get('/context/', unit: unit) as Json);
  Fmt.setCurrency(ctx.currencyCode, ctx.decimals);
  return ctx;
});

FutureProvider<List<T>> _unitList<T>(String path, T Function(Json) fromJson, [Map<String, dynamic>? query]) =>
    FutureProvider<List<T>>((ref) async {
      final unit = await ref.watch(unitIdProvider.future);
      return ref.read(apiProvider).list(path, fromJson, query: query, unit: unit);
    });

FutureProviderFamily<T, String> _unitDetail<T>(String Function(String id) path, T Function(Json) fromJson) =>
    FutureProvider.family<T, String>((ref, id) async {
      final unit = await ref.watch(unitIdProvider.future);
      return fromJson(await ref.read(apiProvider).get(path(id), unit: unit) as Json);
    });

// ---------------------------------------------------------------------------
// Gate
// ---------------------------------------------------------------------------

/// Visitors by bucket: 'upcoming' | 'inside' | 'history'.
final visitorsProvider = FutureProvider.family<List<Visitor>, String>((ref, bucket) async {
  final unit = await ref.watch(unitIdProvider.future);
  return ref.read(apiProvider).list('/visitors/', Visitor.fromJson, query: {'bucket': bucket}, unit: unit);
});

final visitorProvider = _unitDetail((id) => '/visitors/$id/', Visitor.fromJson);
final frequentEntriesProvider = _unitList('/frequent-entries/', FrequentEntry.fromJson, {'is_active': true});
final emergencyContactsProvider = _unitList('/emergency-contacts/', EmergencyContact.fromJson);

// ---------------------------------------------------------------------------
// Household
// ---------------------------------------------------------------------------

final familyProvider = _unitList('/household/family/', FamilyMember.fromJson);
final vehiclesProvider = _unitList('/household/vehicles/', Vehicle.fromJson);
final petsProvider = _unitList('/household/pets/', Pet.fromJson);
final dailyHelpProvider = _unitList('/household/daily-help/', DailyHelp.fromJson);
final helperProvider = _unitDetail((id) => '/household/daily-help/$id/', DailyHelp.fromJson);
final helperAttendanceProvider =
    _unitDetail((id) => '/household/daily-help/$id/attendance/', AttendanceMonth.fromJson);

final helperReviewsProvider = FutureProvider.family<List<Review>, String>((ref, id) async {
  final unit = await ref.watch(unitIdProvider.future);
  return ref.read(apiProvider).list('/household/daily-help/$id/reviews/', Review.fromJson, unit: unit);
});

// ---------------------------------------------------------------------------
// Finance
// ---------------------------------------------------------------------------

final duesProvider = _unitList('/finance/invoices/', Due.fromJson, {'open': true, 'ordering': 'due_date'});
final paymentsProvider = _unitList('/finance/payments/', Payment.fromJson, {'status': 'success'});

final duesSummaryProvider = FutureProvider<DuesSummary>((ref) async {
  final unit = await ref.watch(unitIdProvider.future);
  return DuesSummary.fromJson(await ref.read(apiProvider).get('/finance/invoices/summary/', unit: unit) as Json);
});

final statementProvider = FutureProvider<Statement>((ref) async {
  final unit = await ref.watch(unitIdProvider.future);
  return Statement.fromJson(await ref.read(apiProvider).get('/finance/invoices/statement/', unit: unit) as Json);
});

// ---------------------------------------------------------------------------
// Community
// ---------------------------------------------------------------------------

final noticesProvider = _unitList('/notices/', Notice.fromJson);
final noticeProvider = _unitDetail((id) => '/notices/$id/', Notice.fromJson);
final pollsProvider = _unitList('/polls/', Poll.fromJson);
final eventsProvider = _unitList('/events/', CommunityEvent.fromJson);
final forumProvider = _unitList('/forum/posts/', ForumPost.fromJson);
final forumPostProvider = _unitDetail((id) => '/forum/posts/$id/', ForumPost.fromJson);
final classifiedsProvider = _unitList('/classifieds/', Classified.fromJson);
final vendorsProvider = _unitList('/services/vendors/', ServiceVendor.fromJson);
final residentsProvider = _unitList('/directory/residents/', Person.resident);
final staffProvider = _unitList('/directory/staff/', Person.staff);

final forumRepliesProvider = FutureProvider.family<List<ForumReply>, String>((ref, id) async {
  final unit = await ref.watch(unitIdProvider.future);
  return ref.read(apiProvider).list('/forum/posts/$id/replies/', ForumReply.fromJson, unit: unit);
});

// ---------------------------------------------------------------------------
// Help desk, notifications, chat, search
// ---------------------------------------------------------------------------

final ticketCategoriesProvider = _unitList('/helpdesk/categories/', TicketCategory.fromJson);
final ticketsProvider = _unitList('/helpdesk/tickets/', Ticket.fromJson);
final ticketProvider = _unitDetail((id) => '/helpdesk/tickets/$id/', Ticket.fromJson);

final notificationsProvider = FutureProvider<List<AppNotification>>((ref) async {
  if (ref.watch(sessionProvider) == null) return [];
  return ref.read(apiProvider).list('/notifications/', AppNotification.fromJson);
});

final unreadCountProvider = Provider<int>(
    (ref) => ref.watch(notificationsProvider).value?.where((n) => !n.read).length ?? 0);

final chatMessagesProvider = FutureProvider.family<List<ChatMessage>, String>((ref, conversationId) async {
  final unit = await ref.watch(unitIdProvider.future);
  final items = await ref.read(apiProvider)
      .list('/conversations/$conversationId/messages/', ChatMessage.fromJson, unit: unit);
  return items.reversed.toList(); // API returns newest first
});

final searchProvider = FutureProvider.family<List<SearchResult>, String>((ref, q) async {
  if (q.trim().length < 2) return [];
  final unit = await ref.watch(unitIdProvider.future);
  final data = await ref.read(apiProvider).get('/search/', query: {'q': q}, unit: unit) as List;
  return data.map((e) => SearchResult.fromJson(e as Json)).toList();
});

// ---------------------------------------------------------------------------
// Settings
// ---------------------------------------------------------------------------

/// Server-side preferences: {'notification_prefs': {...}, 'privacy_prefs': {...}}.
class UserSettingsNotifier extends AsyncNotifier<Map<String, Map<String, bool>>> {
  @override
  Future<Map<String, Map<String, bool>>> build() async {
    if (ref.watch(sessionProvider) == null) return {};
    return _parse(await ref.read(apiProvider).get('/me/settings/') as Json);
  }

  Map<String, Map<String, bool>> _parse(Json j) => {
        for (final group in ['notification_prefs', 'privacy_prefs'])
          group: Map<String, bool>.from(j[group] as Map),
      };

  Future<void> toggle(String group, String key) async {
    final current = state.value ?? {};
    final value = !(current[group]?[key] ?? false);
    state = AsyncData({...current, group: {...?current[group], key: value}});
    try {
      state = AsyncData(_parse(await ref.read(apiProvider).patch('/me/settings/', data: {group: {key: value}}) as Json));
    } catch (e, st) {
      state = AsyncError(e, st);
      ref.invalidateSelf();
    }
  }
}

final userSettingsProvider =
    AsyncNotifierProvider<UserSettingsNotifier, Map<String, Map<String, bool>>>(UserSettingsNotifier.new);

class ThemeModeNotifier extends Notifier<ThemeMode> {
  @override
  ThemeMode build() => ThemeMode.system;
  void set(ThemeMode mode) => state = mode;
}

final themeModeProvider = NotifierProvider<ThemeModeNotifier, ThemeMode>(ThemeModeNotifier.new);

class LocaleNotifier extends Notifier<Locale> {
  @override
  Locale build() => const Locale('en');
  void set(Locale locale) => state = locale;
}

final localeProvider = NotifierProvider<LocaleNotifier, Locale>(LocaleNotifier.new);
