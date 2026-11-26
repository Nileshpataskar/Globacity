import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../core/widgets/status_chip.dart';
import 'api/api_client.dart';
import 'models.dart';
import 'providers.dart';

// ---------------------------------------------------------------------------
// Models
// ---------------------------------------------------------------------------

DateTime? _d(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();
String _s(dynamic v) => v?.toString() ?? '';

class GateInfo {
  const GateInfo({required this.id, required this.name, required this.iotEnabled});

  factory GateInfo.fromJson(Json j) =>
      GateInfo(id: _s(j['id']), name: _s(j['name']), iotEnabled: j['iot_enabled'] == true);

  final String id;
  final String name;
  final bool iotEnabled;
}

class GuardShift {
  const GuardShift({required this.id, required this.shift, required this.shiftLabel, required this.startedAt,
      this.gateId, this.gateName, this.endedAt});

  factory GuardShift.fromJson(Json j) => GuardShift(
        id: _s(j['id']),
        shift: _s(j['shift']),
        shiftLabel: _s(j['shift_label']),
        startedAt: _d(j['started_at'])!,
        endedAt: _d(j['ended_at']),
        gateId: j['gate'] as String?,
        gateName: j['gate_name'] as String?,
      );

  final String id;
  final String shift;
  final String shiftLabel;
  final DateTime startedAt;
  final DateTime? endedAt;
  final String? gateId;
  final String? gateName;
}

class GuardContext {
  const GuardContext({required this.communityId, required this.communityName, required this.gates, this.shift,
      this.country = '', this.currency = ''});

  factory GuardContext.fromJson(Json j) {
    final communities = (j['communities'] as List).cast<Json>();
    final c = communities.isEmpty ? <String, dynamic>{} : communities.first;
    return GuardContext(
      communityId: _s(c['id']),
      communityName: _s(c['name']),
      country: _s(c['country']),
      currency: _s(c['currency']),
      gates: [for (final g in (c['gates'] as List? ?? [])) GateInfo.fromJson(g as Json)],
      shift: j['shift'] == null ? null : GuardShift.fromJson(j['shift'] as Json),
    );
  }

  final String communityId;
  final String communityName;
  final String country;
  final String currency;
  final List<GateInfo> gates;
  final GuardShift? shift;
}

class GuardSummary {
  const GuardSummary(this.values);

  factory GuardSummary.fromJson(Json j) => GuardSummary({
        for (final e in j.entries)
          if (e.value is num) e.key: (e.value as num).toInt(),
      });

  final Map<String, int> values;
  int operator [](String key) => values[key] ?? 0;
}

class CodeLookup {
  const CodeLookup({required this.kind, required this.name, required this.detail, required this.units,
      required this.allowed, required this.reason});

  factory CodeLookup.fromJson(Json j) => CodeLookup(
        kind: _s(j['kind']),
        name: _s(j['name']),
        detail: _s(j['detail']),
        units: (j['units'] as List).map((e) => '$e').toList(),
        allowed: j['allowed'] == true,
        reason: _s(j['reason']),
      );

  final String kind;
  final String name;
  final String detail;
  final List<String> units;
  final bool allowed;
  final String reason;

  String get kindLabel => switch (kind) {
        'visitor' => 'Pre-approved visitor',
        'frequent_entry' => 'Frequent entry',
        'daily_help' => 'Daily help',
        _ => kind,
      };
}

class StaffStatus {
  const StaffStatus({required this.id, required this.name, required this.role, required this.designation,
      required this.shift, required this.phone, required this.isInside, this.checkIn, this.checkOut});

  factory StaffStatus.fromJson(Json j) => StaffStatus(
        id: _s(j['id']),
        name: _s(j['name']),
        role: _s(j['role']),
        designation: _s(j['designation']),
        shift: _s(j['shift']),
        phone: _s(j['phone']),
        isInside: j['is_inside'] == true,
        checkIn: _d(j['check_in']),
        checkOut: _d(j['check_out']),
      );

  final String id;
  final String name;
  final String role;
  final String designation;
  final String shift;
  final String phone;
  final bool isInside;
  final DateTime? checkIn;
  final DateTime? checkOut;
}

class Incident {
  const Incident({required this.id, required this.title, required this.description, required this.severity,
      required this.status, required this.location, required this.createdAt, this.photoUrl, this.reportedBy,
      this.resolution = ''});

  factory Incident.fromJson(Json j) => Incident(
        id: _s(j['id']),
        title: _s(j['title']),
        description: _s(j['description']),
        severity: _s(j['severity']),
        status: _s(j['status']),
        location: _s(j['location']),
        createdAt: _d(j['created_at'])!,
        photoUrl: j['photo'] as String?,
        reportedBy: j['reported_by_name'] as String?,
        resolution: _s(j['resolution']),
      );

  final String id;
  final String title;
  final String description;
  final String severity;
  final String status;
  final String location;
  final DateTime createdAt;
  final String? photoUrl;
  final String? reportedBy;
  final String resolution;

  Tone get severityTone => switch (severity) {
        'critical' || 'high' => Tone.danger,
        'medium' => Tone.warning,
        _ => Tone.info,
      };

  Tone get statusTone => switch (status) {
        'resolved' => Tone.success,
        'investigating' => Tone.info,
        _ => Tone.warning,
      };
}

class VehicleLogEntry {
  const VehicleLogEntry({required this.id, required this.number, required this.direction, required this.time,
      required this.isResident, this.unitLabel, this.gateName, this.note = ''});

  factory VehicleLogEntry.fromJson(Json j) => VehicleLogEntry(
        id: _s(j['id']),
        number: _s(j['number']),
        direction: _s(j['direction']),
        time: _d(j['created_at'])!,
        isResident: j['is_resident'] == true,
        unitLabel: j['unit_label'] as String?,
        gateName: j['gate_name'] as String?,
        note: _s(j['note']),
      );

  final String id;
  final String number;
  final String direction;
  final DateTime time;
  final bool isResident;
  final String? unitLabel;
  final String? gateName;
  final String note;
}

class SosAlert {
  const SosAlert({required this.id, required this.type, required this.status, required this.unitLabel,
      required this.raisedBy, required this.phone, required this.time, this.message = ''});

  factory SosAlert.fromJson(Json j) => SosAlert(
        id: _s(j['id']),
        type: _s(j['alert_type']),
        status: _s(j['status']),
        unitLabel: _s(j['unit_label']),
        raisedBy: _s(j['raised_by_name']),
        phone: _s(j['raised_by_phone']),
        time: _d(j['created_at'])!,
        message: _s(j['message']),
      );

  final String id;
  final String type;
  final String status;
  final String unitLabel;
  final String raisedBy;
  final String phone;
  final DateTime time;
  final String message;

  bool get isOpen => status == 'active' || status == 'acknowledged';
}

class KidExit {
  const KidExit({required this.id, required this.children, required this.unitLabel, required this.until, this.note = ''});

  factory KidExit.fromJson(Json j) => KidExit(
        id: _s(j['id']),
        children: [for (final c in (j['children_detail'] as List? ?? [])) _s((c as Json)['name'])],
        unitLabel: _s(j['unit_label']),
        until: _d(j['allowed_until'])!,
        note: _s(j['note']),
      );

  final String id;
  final List<String> children;
  final String unitLabel;
  final DateTime until;
  final String note;
}

class DirectoryEntry {
  const DirectoryEntry({required this.unitId, required this.unitLabel, required this.residents, required this.vehicles});

  factory DirectoryEntry.fromJson(Json j) => DirectoryEntry(
        unitId: _s(j['unit_id']),
        unitLabel: _s(j['unit_label']),
        residents: [
          for (final r in (j['residents'] as List)) (name: _s((r as Json)['name']), role: _s(r['role']), phone: r['phone'] as String?)
        ],
        vehicles: (j['vehicles'] as List).map((e) => '$e').toList(),
      );

  final String unitId;
  final String unitLabel;
  final List<({String name, String role, String? phone})> residents;
  final List<String> vehicles;
}

class HelperInside {
  const HelperInside({required this.id, required this.name, required this.role, required this.isInside, this.since});

  factory HelperInside.fromJson(Json j) => HelperInside(
        id: _s(j['id']), name: _s(j['name']), role: _s(j['role']), isInside: j['is_inside'] == true, since: _d(j['last_entry']));

  final String id;
  final String name;
  final String role;
  final bool isInside;
  final DateTime? since;
}

// ---------------------------------------------------------------------------
// Providers
// ---------------------------------------------------------------------------

/// Raw /me/roles/ response (roles with community and towers).
final myRolesDetailProvider = FutureProvider<Json>((ref) async {
  if (ref.watch(sessionProvider) == null) return {'roles': [], 'is_platform_admin': false};
  return await ref.read(apiProvider).get('/me/roles/') as Json;
});

/// Staff roles of the signed-in user ("guard", "admin", ...), plus "platform_admin".
final myRolesProvider = FutureProvider<Set<String>>((ref) async {
  final data = await ref.watch(myRolesDetailProvider.future);
  return {
    for (final r in (data['roles'] as List)) _s((r as Json)['role']),
    if (data['is_platform_admin'] == true) 'platform_admin',
  };
});

final isGuardProvider = Provider<bool>((ref) {
  final roles = ref.watch(myRolesProvider).value ?? {};
  return roles.contains('guard');
});

FutureProvider<List<T>> _guardList<T>(String path, T Function(Json) fromJson, [Map<String, dynamic>? query]) =>
    FutureProvider<List<T>>((ref) async {
      if (ref.watch(sessionProvider) == null) return [];
      return ref.read(apiProvider).list(path, fromJson, query: query);
    });

final guardContextProvider = FutureProvider<GuardContext>((ref) async {
  if (ref.watch(sessionProvider) == null) throw ApiException('Signed out');
  return GuardContext.fromJson(await ref.read(apiProvider).get('/guard/context/') as Json);
});

final guardSummaryProvider = FutureProvider<GuardSummary>((ref) async {
  if (ref.watch(sessionProvider) == null) throw ApiException('Signed out');
  return GuardSummary.fromJson(await ref.read(apiProvider).get('/guard/summary/') as Json);
});

/// Visitors at the gate by status: waiting | expected | inside.
final guardVisitorsProvider = FutureProvider.family<List<Visitor>, String>((ref, status) async {
  if (ref.watch(sessionProvider) == null) return [];
  return ref.read(apiProvider).list('/guard/visitors/', Visitor.fromJson, query: {'status': status, 'ordering': '-created_at'});
});

final guardHelpersInsideProvider = _guardList('/guard/daily-help/', HelperInside.fromJson, {'inside': true});
final guardStaffProvider = _guardList('/guard/staff/', StaffStatus.fromJson);
final guardIncidentsProvider = _guardList('/guard/incidents/', Incident.fromJson);
final guardVehiclesProvider = _guardList('/guard/vehicles/', VehicleLogEntry.fromJson);
final guardSosProvider = _guardList('/guard/sos/', SosAlert.fromJson);
final guardKidExitsProvider = _guardList('/guard/kid-exits/', KidExit.fromJson);

final guardDirectoryProvider = FutureProvider.family<List<DirectoryEntry>, String>((ref, q) async {
  if (q.trim().isEmpty) return [];
  final data = await ref.read(apiProvider).get('/guard/directory/', query: {'search': q}) as List;
  return data.map((e) => DirectoryEntry.fromJson(e as Json)).toList();
});

void invalidateGuardData(Ref ref) {
  for (final p in [guardSummaryProvider, guardHelpersInsideProvider, guardStaffProvider, guardIncidentsProvider,
    guardVehiclesProvider, guardSosProvider, guardKidExitsProvider, guardContextProvider]) {
    ref.invalidate(p);
  }
  ref.invalidate(guardVisitorsProvider);
}

// ---------------------------------------------------------------------------
// Actions
// ---------------------------------------------------------------------------

class GuardActions {
  GuardActions(this.ref);

  final Ref ref;
  ApiClient get _api => ref.read(apiProvider);

  Future<void> startShift(String communityId, String? gateId, String shift) async {
    await _api.post('/guard/shifts/start/', data: {'community': communityId, 'gate': gateId, 'shift': shift});
    ref.invalidate(guardContextProvider);
  }

  Future<void> endShift(String shiftId) async {
    await _api.post('/guard/shifts/$shiftId/end/');
    ref.invalidate(guardContextProvider);
  }

  Future<CodeLookup> verify(String code) async =>
      CodeLookup.fromJson(await _api.post('/guard/visitors/verify/', data: {'code': code}) as Json);

  Future<String> checkIn(String code, {String? gateId}) async {
    final res = await _api.post('/guard/visitors/check-in/', data: {'code': code, 'gate': ?gateId}) as Json;
    invalidateGuardData(ref);
    return _s(res['detail_message']);
  }

  Future<Visitor> walkIn(Json body, {XFile? photo}) async {
    final res = photo == null
        ? await _api.post('/guard/visitors/walk-in/', data: body)
        : await _api.upload('/guard/visitors/walk-in/', fields: body, files: {'photo': photo});
    invalidateGuardData(ref);
    return Visitor.fromJson(res as Json);
  }

  Future<void> checkOutVisitor(String id) async {
    await _api.post('/guard/visitors/$id/check-out/');
    invalidateGuardData(ref);
  }

  Future<void> checkOutHelper(String id) async {
    await _api.post('/guard/daily-help/$id/check-out/');
    invalidateGuardData(ref);
  }

  Future<void> staffAttendance(String id, {required bool checkIn}) async {
    await _api.post('/guard/staff/$id/${checkIn ? 'check-in' : 'check-out'}/');
    ref.invalidate(guardStaffProvider);
    ref.invalidate(guardSummaryProvider);
  }

  Future<void> reportIncident(Json body, {XFile? photo}) async {
    if (photo == null) {
      await _api.post('/guard/incidents/', data: body);
    } else {
      await _api.upload('/guard/incidents/', fields: body, files: {'photo': photo});
    }
    ref.invalidate(guardIncidentsProvider);
    ref.invalidate(guardSummaryProvider);
  }

  Future<void> updateIncident(String id, String status, String resolution) async {
    await _api.patch('/guard/incidents/$id/', data: {'status': status, 'resolution': resolution});
    ref.invalidate(guardIncidentsProvider);
    ref.invalidate(guardSummaryProvider);
  }

  Future<({bool registered, String? unit, String? model})> lookupVehicle(String number) async {
    final j = await _api.get('/guard/vehicles/lookup/', query: {'number': number}) as Json;
    return (registered: j['registered'] == true, unit: j['unit_label'] as String?, model: j['make_model'] as String?);
  }

  Future<VehicleLogEntry> logVehicle(String number, String direction, {String? gateId, String note = ''}) async {
    final res = await _api.post('/guard/vehicles/', data: {'number': number, 'direction': direction, 'gate': gateId, 'note': note});
    ref.invalidate(guardVehiclesProvider);
    ref.invalidate(guardSummaryProvider);
    return VehicleLogEntry.fromJson(res as Json);
  }

  Future<String> openGate(String gateId) async =>
      _s(((await _api.post('/guard/gates/$gateId/open/')) as Json)['detail']);

  Future<void> sosAction(String id, String action) async {
    await _api.post('/guard/sos/$id/$action/');
    ref.invalidate(guardSosProvider);
    ref.invalidate(guardSummaryProvider);
  }

  Future<List<DirectoryEntry>> searchUnits(String q) async {
    final data = await _api.get('/guard/directory/', query: {'search': q}) as List;
    return data.map((e) => DirectoryEntry.fromJson(e as Json)).toList();
  }
}

final guardActionsProvider = Provider<GuardActions>(GuardActions.new);
