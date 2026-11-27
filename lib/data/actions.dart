import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import 'api/api_client.dart';
import 'models.dart';
import 'providers.dart';

/// All write operations. Each one calls the API, then refreshes the affected providers.
class AppActions {
  AppActions(this.ref);

  final Ref ref;

  ApiClient get _api => ref.read(apiProvider);
  Future<String> get _unit => ref.read(unitIdProvider.future);

  Future<dynamic> _post(String path, [Object? data]) async => _api.post(path, data: data, unit: await _unit);

  // Properties ----------------------------------------------------------------

  Future<List<Community>> searchCommunities(String q) =>
      _api.list('/communities/', Community.fromJson, query: {'search': q});

  Future<List<TowerOption>> towers(String communityId) async =>
      ((await _api.get('/communities/$communityId/towers/')) as List)
          .map((e) => TowerOption.fromJson(e as Json))
          .toList();

  Future<List<UnitOption>> units(String communityId, String towerId, {String search = ''}) async =>
      ((await _api.get('/communities/$communityId/units/', query: {'tower': towerId, 'search': search})) as List)
          .map((e) => UnitOption.fromJson(e as Json))
          .toList();

  /// Requests a unit. Returns true when the tower approves automatically (access right away).
  Future<bool> joinUnit(String unitId, ResidentRole role) async {
    final res = await _api.post('/me/units/', data: {'unit': unitId, 'role': role.name}) as Json;
    ref.invalidate(propertiesProvider);
    return res['status'] == 'approved';
  }

  Future<void> leaveUnit(String membershipId) async {
    await _api.delete('/me/units/$membershipId/');
    ref.invalidate(propertiesProvider);
  }

  void selectUnit(String unitId) => ref.read(selectedUnitProvider.notifier).select(unitId);

  // Gate -----------------------------------------------------------------------

  Future<Visitor> preApprove(Json body) async {
    final v = Visitor.fromJson(await _post('/visitors/', body) as Json);
    ref.invalidate(visitorsProvider);
    return v;
  }

  /// action: approve | deny | leave-at-gate | cancel | mark-exit
  Future<void> visitorAction(String id, String action) async {
    await _post('/visitors/$id/$action/');
    ref.invalidate(visitorsProvider);
    ref.invalidate(visitorProvider(id));
    ref.invalidate(contextProvider);
  }

  Future<void> addFrequentEntry(Json body) async {
    await _post('/frequent-entries/', body);
    ref.invalidate(frequentEntriesProvider);
  }

  Future<void> removeFrequentEntry(String id) async {
    await _api.delete('/frequent-entries/$id/', unit: await _unit);
    ref.invalidate(frequentEntriesProvider);
  }

  Future<String> raiseSos(String type, String message) async =>
      ((await _post('/sos/', {'alert_type': type, 'message': message})) as Json)['id'] as String;

  Future<void> cancelSos(String id) => _post('/sos/$id/cancel/');

  Future<void> allowKidExit(List<String> childIds, int minutes, String note) =>
      _post('/kid-exits/', {'children': childIds, 'duration_minutes': minutes, 'note': note});

  Future<void> addPersonalContact(String name, String phone) async {
    await _post('/emergency-contacts/', {'name': name, 'phone': phone, 'icon': 'favorite'});
    ref.invalidate(emergencyContactsProvider);
  }

  // Household ------------------------------------------------------------------

  Future<void> addFamilyMember(String name, String relation, String phone, bool isMinor) async {
    await _post('/household/family/', {'name': name, 'relation': relation, 'phone': phone, 'is_minor': isMinor});
    ref.invalidate(familyProvider);
  }

  Future<void> removeFamilyMember(String id) async {
    await _api.delete('/household/family/$id/', unit: await _unit);
    ref.invalidate(familyProvider);
  }

  Future<void> addVehicle(String number, String model, String slot) async {
    await _post('/household/vehicles/', {'number': number, 'make_model': model, 'parking_slot': slot});
    ref.invalidate(vehiclesProvider);
  }

  Future<void> addPet(String name, String species, String breed) async {
    await _post('/household/pets/', {'name': name, 'species': species, 'breed': breed});
    ref.invalidate(petsProvider);
  }

  Future<void> addDailyHelp(String name, String role, String phone, String timing) async {
    await _post('/household/daily-help/', {'name': name, 'role': role, 'phone': phone, 'timing': timing});
    ref.invalidate(dailyHelpProvider);
  }

  Future<void> removeDailyHelp(String id) async {
    await _api.delete('/household/daily-help/$id/', unit: await _unit);
    ref.invalidate(dailyHelpProvider);
  }

  Future<void> reviewHelper(String id, int rating, String comment) async {
    await _post('/household/daily-help/$id/reviews/', {'rating': rating, 'comment': comment});
    ref.invalidate(helperReviewsProvider(id));
    ref.invalidate(helperProvider(id));
    ref.invalidate(dailyHelpProvider);
  }

  // Finance --------------------------------------------------------------------

  /// Starts a checkout with the country's gateway. Returns the payment id.
  Future<({String paymentId, String gateway})> checkout(List<String> invoiceIds, String method) async {
    final res = await _post('/finance/payments/checkout/', {'invoice_ids': invoiceIds, 'method': method}) as Json;
    return (
      paymentId: (res['payment'] as Json)['id'] as String,
      gateway: (res['checkout'] as Json)['gateway'] as String,
    );
  }

  /// Completes a mock-gateway payment (development).
  Future<Payment> confirmMockPayment(String paymentId) async {
    final p = Payment.fromJson(await _post('/finance/payments/$paymentId/mock-confirm/', {'success': true}) as Json);
    for (final provider in [duesProvider, paymentsProvider, duesSummaryProvider, statementProvider, contextProvider]) {
      ref.invalidate(provider);
    }
    return p;
  }

  // Community ------------------------------------------------------------------

  Future<void> vote(String pollId, int optionId) async {
    await _post('/polls/$pollId/vote/', {'option': optionId});
    ref.invalidate(pollsProvider);
  }

  /// [people] = how many are coming from this flat, including the resident.
  Future<void> rsvp(String eventId, bool going, {int people = 1}) async {
    await _post('/events/$eventId/rsvp/', {'going': going, 'guests': people});
    ref.invalidate(eventsProvider);
  }

  Future<void> createPost(String title, String body) async {
    await _post('/forum/posts/', {'title': title, 'body': body});
    ref.invalidate(forumProvider);
  }

  Future<void> reply(String postId, String body) async {
    await _post('/forum/posts/$postId/replies/', {'body': body});
    ref.invalidate(forumRepliesProvider(postId));
    ref.invalidate(forumProvider);
  }

  Future<void> like(String postId) async {
    await _post('/forum/posts/$postId/like/');
    ref.invalidate(forumPostProvider(postId));
    ref.invalidate(forumProvider);
  }

  Future<void> createClassified(String title, String price, String category, String description,
      {XFile? image}) async {
    final fields = {'title': title, 'price': price, 'category': category, 'description': description};
    if (image == null) {
      await _post('/classifieds/', fields);
    } else {
      await _api.upload('/classifieds/', fields: fields, files: {'image': image}, unit: await _unit);
    }
    ref.invalidate(classifiedsProvider);
  }

  Future<void> markSold(String id) async {
    await _post('/classifieds/$id/mark-sold/');
    ref.invalidate(classifiedsProvider);
  }

  Future<void> bookService(String vendorId, DateTime slot, String notes) =>
      _post('/services/bookings/', {'vendor': vendorId, 'slot_start': slot.toUtc().toIso8601String(), 'notes': notes});

  /// Creates the request, then uploads [documents] (document type -> photo).
  Future<void> requestMove(Json body, {Map<String, XFile> documents = const {}}) async {
    final id = ((await _post('/move-requests/', body)) as Json)['id'] as String;
    for (final d in documents.entries) {
      await _api.upload('/move-requests/$id/documents/', fields: {'doc_type': d.key}, files: {'file': d.value},
          unit: await _unit);
    }
  }

  // Help desk ------------------------------------------------------------------

  Future<Ticket> createTicket(String categoryId, String title, String description, String priority,
      {List<XFile> photos = const []}) async {
    final t = Ticket.fromJson(await _post('/helpdesk/tickets/', {
      'category': categoryId, 'title': title, 'description': description, 'priority': priority.toLowerCase(),
    }) as Json);
    for (final p in photos) {
      await _api.upload('/helpdesk/tickets/${t.id}/attachments/', files: {'file': p}, unit: await _unit);
    }
    ref.invalidate(ticketsProvider);
    return t;
  }

  Future<void> rateTicket(String id, int rating) async {
    await _post('/helpdesk/tickets/$id/rate/', {'rating': rating});
    ref.invalidate(ticketProvider(id));
    ref.invalidate(ticketsProvider);
  }

  // Messaging & notifications --------------------------------------------------

  Future<Conversation> startConversation(String userId) async =>
      Conversation.fromJson(await _post('/conversations/', {'user_id': userId}) as Json);

  Future<void> sendMessage(String conversationId, String body) async {
    await _post('/conversations/$conversationId/messages/', {'body': body});
    ref.invalidate(chatMessagesProvider(conversationId));
  }

  Future<void> markAllNotificationsRead() async {
    await _api.post('/notifications/read-all/');
    ref.invalidate(notificationsProvider);
  }
}

final actionsProvider = Provider<AppActions>(AppActions.new);
