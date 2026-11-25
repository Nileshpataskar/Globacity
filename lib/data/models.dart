import 'package:flutter/material.dart';

import '../core/widgets/status_chip.dart';
import 'api/json.dart';

export 'api/json.dart';

double _num(dynamic v) => v == null ? 0 : (v is num ? v.toDouble() : double.tryParse(v.toString()) ?? 0);
DateTime _date(dynamic v) => v == null ? DateTime.now() : DateTime.parse(v as String).toLocal();
DateTime? _dateOrNull(dynamic v) => v == null ? null : DateTime.parse(v as String).toLocal();
String _str(dynamic v) => v?.toString() ?? '';
String? _strOrNull(dynamic v) => (v == null || v.toString().isEmpty) ? null : v.toString();

T _enum<T extends Enum>(List<T> values, String? wire, T fallback, [String Function(T)? toWire]) {
  for (final v in values) {
    if ((toWire?.call(v) ?? v.name) == wire) return v;
  }
  return fallback;
}

Color? _hexColor(String? hex) {
  final h = hex?.replaceFirst('#', '');
  if (h == null || (h.length != 6 && h.length != 8)) return null;
  final v = int.tryParse(h.length == 6 ? 'FF$h' : h, radix: 16);
  return v == null ? null : Color(v);
}

String _snake(String camel) => camel.replaceAllMapped(RegExp('[A-Z]'), (m) => '_${m[0]!.toLowerCase()}');

// ---------------------------------------------------------------------------
// Account, properties, context
// ---------------------------------------------------------------------------

class UserProfile {
  const UserProfile({required this.id, required this.name, required this.phone, required this.email,
      this.isPlatformAdmin = false, this.avatarUrl});

  factory UserProfile.fromJson(Json j) => UserProfile(
        id: _str(j['id']),
        name: _str(j['full_name']).isEmpty ? _str(j['phone']) : _str(j['full_name']),
        phone: _str(j['phone']),
        email: _str(j['email']),
        isPlatformAdmin: j['is_platform_admin'] == true,
        avatarUrl: _strOrNull(j['avatar']),
      );

  final String id;
  final String name;
  final String phone;
  final String email;
  final bool isPlatformAdmin;
  final String? avatarUrl;
}

enum ResidentRole { owner, tenant, family }

extension ResidentRoleX on ResidentRole {
  String get label => switch (this) {
        ResidentRole.owner => 'Owner',
        ResidentRole.tenant => 'Tenant',
        ResidentRole.family => 'Family member',
      };
}

/// One of the user's units ("My properties"), from /me/units/.
class Property {
  const Property({
    required this.id,
    required this.membershipId,
    required this.communityId,
    required this.community,
    required this.tower,
    required this.unit,
    required this.city,
    required this.currency,
    required this.role,
    required this.status,
  });

  factory Property.fromJson(Json j) {
    final u = j['unit_detail'] as Json;
    final c = u['community'] as Json;
    return Property(
      id: _str(j['unit']),
      membershipId: _str(j['id']),
      communityId: _str(c['id']),
      community: _str(c['name']),
      tower: _str(u['tower']),
      unit: _str(u['number']),
      city: '${c['city']}, ${c['country']}',
      currency: _str(c['currency']),
      role: _enum(ResidentRole.values, j['role'] as String?, ResidentRole.owner),
      status: _str(j['status']),
    );
  }

  /// Unit id — what the API calls X-Unit-ID.
  final String id;
  final String membershipId;
  final String communityId;
  final String community;
  final String tower;
  final String unit;
  final String city;
  final String currency;
  final ResidentRole role;
  final String status;

  bool get isApproved => status == 'approved';
  String get shortLabel => '$tower · $unit';
}

/// Locale + branding of the selected unit, from /context/.
class AppContext {
  const AppContext({
    required this.currencyCode,
    required this.currencySymbol,
    required this.decimals,
    required this.taxName,
    required this.taxRate,
    required this.timezone,
    required this.communityName,
    required this.communityPhone,
    required this.settings,
    required this.primaryColor,
    required this.logoUrl,
    required this.emergencyPhone,
    required this.visitorsWaiting,
    required this.unreadNotifications,
    required this.outstanding,
  });

  factory AppContext.fromJson(Json j) {
    final country = j['country'] as Json;
    final currency = country['currency'] as Json;
    final community = j['community'] as Json;
    final counts = j['counts'] as Json;
    return AppContext(
      currencyCode: _str(currency['code']),
      currencySymbol: _str(currency['symbol']),
      decimals: (currency['decimal_places'] as num).toInt(),
      taxName: _str(country['tax_name']),
      taxRate: _num(country['tax_rate']),
      timezone: _str(community['timezone']),
      communityName: _str(community['name']),
      communityPhone: _str(community['contact_phone']),
      settings: Map<String, dynamic>.from(community['settings'] as Map? ?? {}),
      primaryColor: _hexColor(community['primary_color'] as String?),
      logoUrl: _strOrNull(community['logo']),
      emergencyPhone: _strOrNull(community['contact_phone']),
      visitorsWaiting: (counts['visitors_waiting'] as num).toInt(),
      unreadNotifications: (counts['unread_notifications'] as num).toInt(),
      outstanding: _num(counts['outstanding_dues']),
    );
  }

  final String currencyCode;
  final String currencySymbol;
  final int decimals;
  final String taxName;
  final double taxRate;
  final String timezone;
  final String communityName;
  final String communityPhone;
  final Map<String, dynamic> settings;

  /// Community brand color (white-label), null = app default.
  final Color? primaryColor;
  final String? logoUrl;
  final String? emergencyPhone;
  final int visitorsWaiting;
  final int unreadNotifications;
  final double outstanding;
}

class CountryOption {
  const CountryOption({required this.name, required this.iso2, required this.phoneCode, required this.length});

  factory CountryOption.fromJson(Json j) => CountryOption(
        name: _str(j['name']),
        iso2: _str(j['iso2']),
        phoneCode: _str(j['phone_code']),
        length: (j['phone_number_length'] as num).toInt(),
      );

  final String name;
  final String iso2;
  final String phoneCode;
  final int length;

  /// Regional-indicator flag emoji from the ISO code.
  String get flag => iso2.toUpperCase().codeUnits.map((c) => String.fromCharCode(c + 127397)).join();
}

class Community {
  const Community({required this.id, required this.name, required this.area});

  factory Community.fromJson(Json j) => Community(
        id: _str(j['id']),
        name: _str(j['name']),
        area: [j['address'], j['city'], j['country']].where((e) => e != null && e.toString().isNotEmpty).join(', '),
      );

  final String id;
  final String name;
  final String area;
}

class TowerOption {
  const TowerOption({required this.id, required this.name});

  factory TowerOption.fromJson(Json j) => TowerOption(id: _str(j['id']), name: _str(j['name']));

  final String id;
  final String name;
}

class UnitOption {
  const UnitOption({required this.id, required this.number});

  factory UnitOption.fromJson(Json j) => UnitOption(id: _str(j['id']), number: _str(j['number']));

  final String id;
  final String number;
}

// ---------------------------------------------------------------------------
// Gate & visitors
// ---------------------------------------------------------------------------

enum VisitorType { guest, delivery, cab, service, other }

extension VisitorTypeX on VisitorType {
  String get label => switch (this) {
        VisitorType.guest => 'Guest',
        VisitorType.delivery => 'Delivery',
        VisitorType.cab => 'Cab',
        VisitorType.service => 'Service',
        VisitorType.other => 'Visitor',
      };

  IconData get icon => switch (this) {
        VisitorType.guest => Icons.person_rounded,
        VisitorType.delivery => Icons.inventory_2_rounded,
        VisitorType.cab => Icons.local_taxi_rounded,
        VisitorType.service => Icons.handyman_rounded,
        VisitorType.other => Icons.badge_rounded,
      };
}

enum VisitorStatus { expected, waiting, inside, exited, denied, leftAtGate, cancelled, expired }

extension VisitorStatusX on VisitorStatus {
  String get wire => _snake(name);

  String get label => switch (this) {
        VisitorStatus.expected => 'Pre-approved',
        VisitorStatus.waiting => 'At gate',
        VisitorStatus.inside => 'Inside',
        VisitorStatus.exited => 'Exited',
        VisitorStatus.denied => 'Denied',
        VisitorStatus.leftAtGate => 'Left at gate',
        VisitorStatus.cancelled => 'Cancelled',
        VisitorStatus.expired => 'Expired',
      };

  Tone get tone => switch (this) {
        VisitorStatus.expected => Tone.info,
        VisitorStatus.waiting => Tone.warning,
        VisitorStatus.inside => Tone.success,
        VisitorStatus.denied => Tone.danger,
        _ => Tone.neutral,
      };
}

class Visitor {
  const Visitor({
    required this.id,
    required this.name,
    required this.type,
    required this.status,
    required this.time,
    required this.passCode,
    required this.unitLabel,
    this.phone,
    this.company,
    this.vehicleNo,
    this.guests = 1,
    this.gate = 'Main Gate',
    this.validUntil,
  });

  factory Visitor.fromJson(Json j) => Visitor(
        id: _str(j['id']),
        name: _str(j['name']),
        type: _enum(VisitorType.values, j['visitor_type'] as String?, VisitorType.other),
        status: _enum(VisitorStatus.values, j['status'] as String?, VisitorStatus.expected, (s) => s.wire),
        time: _date(j['checked_in_at'] ?? j['expected_at'] ?? j['created_at']),
        passCode: _str(j['pass_code']),
        unitLabel: _str(j['unit_label']),
        phone: _strOrNull(j['phone']),
        company: _strOrNull(j['company']),
        vehicleNo: _strOrNull(j['vehicle_no']),
        guests: (j['guests'] as num?)?.toInt() ?? 1,
        gate: _strOrNull(j['gate_name']) ?? 'Main Gate',
        validUntil: _dateOrNull(j['valid_until']),
      );

  final String id;
  final String name;
  final VisitorType type;
  final VisitorStatus status;
  final DateTime time;
  final String passCode;
  final String unitLabel;
  final String? phone;
  final String? company;
  final String? vehicleNo;
  final int guests;
  final String gate;
  final DateTime? validUntil;
}

// ---------------------------------------------------------------------------
// Household
// ---------------------------------------------------------------------------

class FamilyMember {
  const FamilyMember({required this.id, required this.name, required this.relation, this.phone, this.isMinor = false});

  factory FamilyMember.fromJson(Json j) => FamilyMember(
        id: _str(j['id']),
        name: _str(j['name']),
        relation: _str(j['relation']),
        phone: _strOrNull(j['phone']),
        isMinor: j['is_minor'] == true,
      );

  final String id;
  final String name;
  final String relation;
  final String? phone;
  final bool isMinor;
}

class Vehicle {
  const Vehicle({required this.id, required this.number, required this.model, required this.isCar, this.parkingSlot});

  factory Vehicle.fromJson(Json j) => Vehicle(
        id: _str(j['id']),
        number: _str(j['number']),
        model: [j['make_model'], j['color']].where((e) => e != null && e.toString().isNotEmpty).join(' · '),
        isCar: j['vehicle_type'] != 'bike',
        parkingSlot: _strOrNull(j['parking_slot']),
      );

  final String id;
  final String number;
  final String model;
  final bool isCar;
  final String? parkingSlot;
}

class Pet {
  const Pet({required this.id, required this.name, required this.breed, required this.species, this.vaccinated = true});

  factory Pet.fromJson(Json j) => Pet(
        id: _str(j['id']),
        name: _str(j['name']),
        breed: _str(j['breed']),
        species: _str(j['species']),
        vaccinated: j['vaccinated'] == true,
      );

  final String id;
  final String name;
  final String breed;
  final String species;
  final bool vaccinated;
}

class FrequentEntry {
  const FrequentEntry({required this.id, required this.name, required this.type, required this.validTill,
      required this.schedule, required this.passCode});

  factory FrequentEntry.fromJson(Json j) {
    const days = ['Mon', 'Tue', 'Wed', 'Thu', 'Fri', 'Sat', 'Sun'];
    final dow = (j['days_of_week'] as List? ?? []).cast<num>();
    String t(dynamic v) => v.toString().substring(0, 5);
    final when = j['time_from'] != null && j['time_to'] != null ? ' · ${t(j['time_from'])} – ${t(j['time_to'])}' : '';
    return FrequentEntry(
      id: _str(j['id']),
      name: _str(j['name']),
      type: _enum(VisitorType.values, j['visitor_type'] as String?, VisitorType.other),
      validTill: DateTime.parse(j['valid_until'] as String),
      schedule: '${dow.isEmpty || dow.length == 7 ? 'Daily' : dow.map((d) => days[d.toInt()]).join(', ')}$when',
      passCode: _str(j['pass_code']),
    );
  }

  final String id;
  final String name;
  final VisitorType type;
  final DateTime validTill;
  final String schedule;
  final String passCode;
}

class Review {
  const Review({required this.author, required this.unit, required this.rating, required this.comment, required this.date});

  factory Review.fromJson(Json j) => Review(
        author: _str(j['author_name']),
        unit: _str(j['unit_label']),
        rating: (j['rating'] as num).toInt(),
        comment: _str(j['comment']),
        date: _date(j['created_at']),
      );

  final String author;
  final String unit;
  final int rating;
  final String comment;
  final DateTime date;
}

class DailyHelp {
  const DailyHelp({
    required this.id,
    required this.name,
    required this.role,
    required this.phone,
    required this.rating,
    required this.reviewsCount,
    required this.since,
    required this.timing,
    required this.homesServed,
    required this.passCode,
    this.isInside = false,
    this.idVerified = false,
    this.lastEntry,
  });

  factory DailyHelp.fromJson(Json j) => DailyHelp(
        id: _str(j['id']),
        name: _str(j['name']),
        role: _str(j['role']),
        phone: _str(j['phone']),
        rating: _num(j['rating']),
        reviewsCount: (j['reviews_count'] as num?)?.toInt() ?? 0,
        since: _date(j['created_at']),
        timing: _str(j['my_timing']).isEmpty ? 'Not set' : _str(j['my_timing']),
        homesServed: (j['homes_served'] as num?)?.toInt() ?? 1,
        passCode: _str(j['pass_code']),
        isInside: j['is_inside'] == true,
        idVerified: j['id_verified'] == true,
        lastEntry: _dateOrNull(j['last_entry']),
      );

  final String id;
  final String name;
  final String role;
  final String phone;
  final double rating;
  final int reviewsCount;
  final DateTime since;
  final String timing;
  final int homesServed;
  final String passCode;
  final bool isInside;
  final bool idVerified;
  final DateTime? lastEntry;
}

class AttendanceMonth {
  const AttendanceMonth({required this.presentDays});

  factory AttendanceMonth.fromJson(Json j) =>
      AttendanceMonth(presentDays: (j['present_days'] as List).map((e) => (e as num).toInt()).toSet());

  final Set<int> presentDays;
}

// ---------------------------------------------------------------------------
// Finance (amounts carry their own currency)
// ---------------------------------------------------------------------------

class Due {
  const Due({
    required this.id,
    required this.title,
    required this.amount,
    required this.total,
    required this.taxLabel,
    required this.currency,
    required this.dueDate,
    required this.period,
    required this.isOverdue,
  });

  factory Due.fromJson(Json j) {
    final taxRate = _num(j['tax_rate']);
    return Due(
      id: _str(j['id']),
      title: _str(j['title']),
      amount: _num(j['balance']),
      total: _num(j['total']),
      taxLabel: taxRate > 0 ? 'incl. ${j['tax_name']} ${taxRate.toStringAsFixed(taxRate % 1 == 0 ? 0 : 2)}%' : '',
      currency: _str(j['currency']),
      dueDate: DateTime.parse(j['due_date'] as String),
      period: _str(j['period_label']),
      isOverdue: j['is_overdue'] == true,
    );
  }

  final String id;
  final String title;

  /// Amount still to pay.
  final double amount;
  final double total;
  final String taxLabel;
  final String currency;
  final DateTime dueDate;
  final String period;
  final bool isOverdue;
}

class DuesSummary {
  const DuesSummary({required this.currency, required this.outstanding, required this.overdue,
      required this.pendingCount, this.nextDue});

  factory DuesSummary.fromJson(Json j) => DuesSummary(
        currency: _str(j['currency']),
        outstanding: _num(j['outstanding']),
        overdue: _num(j['overdue']),
        pendingCount: (j['pending_count'] as num).toInt(),
        nextDue: j['next_due_date'] == null ? null : DateTime.parse(j['next_due_date'] as String),
      );

  final String currency;
  final double outstanding;
  final double overdue;
  final int pendingCount;
  final DateTime? nextDue;
}

class Payment {
  const Payment({required this.id, required this.title, required this.amount, required this.currency,
      required this.date, required this.method, required this.reference, required this.status});

  factory Payment.fromJson(Json j) {
    final allocations = (j['allocations'] as List? ?? []).cast<Json>();
    const methods = {'card': 'Card', 'apple_pay': 'Apple Pay', 'google_pay': 'Google Pay',
        'bank_transfer': 'Bank transfer', 'cash': 'Cash', 'cheque': 'Cheque'};
    return Payment(
      id: _str(j['id']),
      title: allocations.isEmpty
          ? 'Payment'
          : allocations.length == 1
              ? _str(allocations.first['title'])
              : '${allocations.length} invoices',
      amount: _num(j['amount']),
      currency: _str(j['currency']),
      date: _date(j['paid_at'] ?? j['created_at']),
      method: methods[j['method']] ?? _str(j['method']),
      reference: _str(j['reference']),
      status: _str(j['status']),
    );
  }

  final String id;
  final String title;
  final double amount;
  final String currency;
  final DateTime date;
  final String method;
  final String reference;
  final String status;
}

class LedgerEntry {
  const LedgerEntry({required this.date, required this.description, required this.balance, this.debit = 0,
      this.credit = 0});

  factory LedgerEntry.fromJson(Json j) => LedgerEntry(
        date: DateTime.parse(j['date'] as String),
        description: _str(j['description']),
        debit: _num(j['debit']),
        credit: _num(j['credit']),
        balance: _num(j['balance']),
      );

  final DateTime date;
  final String description;
  final double debit;
  final double credit;
  final double balance;
}

class Statement {
  const Statement({required this.currency, required this.closingBalance, required this.entries});

  factory Statement.fromJson(Json j) => Statement(
        currency: _str(j['currency']),
        closingBalance: _num(j['closing_balance']),
        entries: (j['entries'] as List).map((e) => LedgerEntry.fromJson(e as Json)).toList(),
      );

  final String currency;
  final double closingBalance;
  final List<LedgerEntry> entries;
}

// ---------------------------------------------------------------------------
// Community
// ---------------------------------------------------------------------------

class Notice {
  const Notice({required this.id, required this.title, required this.body, required this.author, required this.date,
      required this.category, this.pinned = false});

  factory Notice.fromJson(Json j) => Notice(
        id: _str(j['id']),
        title: _str(j['title']),
        body: _str(j['body']),
        author: _str(j['author_label']),
        date: _date(j['published_at']),
        category: _str(j['category']),
        pinned: j['is_pinned'] == true,
      );

  final String id;
  final String title;
  final String body;
  final String author;
  final DateTime date;
  final String category;
  final bool pinned;
}

class PollOption {
  const PollOption({required this.id, required this.label, required this.votes, required this.percent});

  factory PollOption.fromJson(Json j) => PollOption(
        id: (j['id'] as num).toInt(),
        label: _str(j['label']),
        votes: (j['votes'] as num).toInt(),
        percent: _num(j['percent']),
      );

  final int id;
  final String label;
  final int votes;
  final double percent;
}

class Poll {
  const Poll({required this.id, required this.question, required this.options, required this.endsAt,
      required this.totalVotes, required this.isClosed, this.myVote});

  factory Poll.fromJson(Json j) => Poll(
        id: _str(j['id']),
        question: _str(j['question']),
        options: (j['options'] as List).map((e) => PollOption.fromJson(e as Json)).toList(),
        endsAt: _date(j['closes_at']),
        totalVotes: (j['total_votes'] as num).toInt(),
        isClosed: j['is_closed'] == true,
        myVote: (j['my_vote'] as num?)?.toInt(),
      );

  final String id;
  final String question;
  final List<PollOption> options;
  final DateTime endsAt;
  final int totalVotes;
  final bool isClosed;

  /// Option id voted by you (or your unit).
  final int? myVote;
}

class CommunityEvent {
  const CommunityEvent({
    required this.id,
    required this.title,
    required this.description,
    required this.date,
    required this.venue,
    required this.category,
    required this.attendees,
    this.going = false,
  });

  factory CommunityEvent.fromJson(Json j) => CommunityEvent(
        id: _str(j['id']),
        title: _str(j['title']),
        description: _str(j['description']),
        date: _date(j['starts_at']),
        venue: _str(j['venue']),
        category: _str(j['category']),
        attendees: (j['attendees'] as num?)?.toInt() ?? 0,
        going: j['going'] == true,
      );

  final String id;
  final String title;
  final String description;
  final DateTime date;
  final String venue;
  final String category;
  final int attendees;
  final bool going;
}

class ForumReply {
  const ForumReply({required this.author, required this.body, required this.time});

  factory ForumReply.fromJson(Json j) =>
      ForumReply(author: _str(j['author_name']), body: _str(j['body']), time: _date(j['created_at']));

  final String author;
  final String body;
  final DateTime time;
}

class ForumPost {
  const ForumPost({
    required this.id,
    required this.author,
    required this.unit,
    required this.title,
    required this.body,
    required this.tag,
    required this.time,
    required this.likes,
    required this.repliesCount,
    required this.liked,
    required this.isLocked,
  });

  factory ForumPost.fromJson(Json j) => ForumPost(
        id: _str(j['id']),
        author: _str(j['author_name']),
        unit: _str(j['unit_label']),
        title: _str(j['title']),
        body: _str(j['body']),
        tag: _str(j['tag']),
        time: _date(j['created_at']),
        likes: (j['likes_count'] as num?)?.toInt() ?? 0,
        repliesCount: (j['replies_count'] as num?)?.toInt() ?? 0,
        liked: j['liked'] == true,
        isLocked: j['is_locked'] == true,
      );

  final String id;
  final String author;
  final String unit;
  final String title;
  final String body;
  final String tag;
  final DateTime time;
  final int likes;
  final int repliesCount;
  final bool liked;
  final bool isLocked;
}

/// Directory entry (resident or staff).
class Person {
  const Person({required this.name, required this.subtitle, this.phone, this.tag, this.userId, this.canMessage = false});

  factory Person.resident(Json j) => Person(
        userId: _strOrNull(j['user_id']),
        name: _str(j['name']),
        subtitle: _strOrNull(j['unit']) ?? 'Resident',
        phone: _strOrNull(j['phone']),
        tag: _str(j['role']).isEmpty ? null : '${_str(j['role'])[0].toUpperCase()}${_str(j['role']).substring(1)}',
        canMessage: j['can_message'] == true,
      );

  factory Person.staff(Json j) => Person(
        userId: _strOrNull(j['user']),
        name: _str(j['name']),
        subtitle: _strOrNull(j['designation']) ?? _str(j['role_label']),
        phone: _strOrNull(j['phone']),
        tag: _strOrNull(j['shift']),
        canMessage: j['user'] != null,
      );

  final String? userId;
  final String name;
  final String subtitle;
  final String? phone;
  final String? tag;
  final bool canMessage;
}

class Classified {
  const Classified({
    required this.id,
    required this.title,
    required this.price,
    required this.currency,
    required this.category,
    required this.seller,
    required this.sellerId,
    required this.unit,
    required this.posted,
    required this.description,
    required this.status,
    this.imageUrl,
  });

  factory Classified.fromJson(Json j) => Classified(
        id: _str(j['id']),
        title: _str(j['title']),
        price: _num(j['price']),
        currency: _str(j['currency']),
        category: _str(j['category']),
        seller: _str(j['seller_name']),
        sellerId: _str(j['seller_id']),
        unit: _str(j['unit_label']),
        posted: _date(j['created_at']),
        description: _str(j['description']),
        status: _str(j['status']),
        imageUrl: _strOrNull(j['image']),
      );

  final String id;
  final String title;
  final double price;
  final String currency;
  final String category;
  final String seller;
  final String sellerId;
  final String unit;
  final DateTime posted;
  final String description;
  final String status;
  final String? imageUrl;
}

class ServiceVendor {
  const ServiceVendor({required this.id, required this.name, required this.category, required this.rating,
      required this.priceFrom, required this.currency, required this.eta});

  factory ServiceVendor.fromJson(Json j) => ServiceVendor(
        id: _str(j['id']),
        name: _str(j['name']),
        category: _str(j['category']),
        rating: _num(j['rating']),
        priceFrom: _num(j['price_from']),
        currency: _str(j['currency']),
        eta: _str(j['eta_text']),
      );

  final String id;
  final String name;
  final String category;
  final double rating;
  final double priceFrom;
  final String currency;
  final String eta;
}

// ---------------------------------------------------------------------------
// Help desk, security, notifications, chat
// ---------------------------------------------------------------------------

enum TicketStatus { open, inProgress, onHold, resolved, closed }

extension TicketStatusX on TicketStatus {
  String get label => switch (this) {
        TicketStatus.open => 'Open',
        TicketStatus.inProgress => 'In progress',
        TicketStatus.onHold => 'On hold',
        TicketStatus.resolved => 'Resolved',
        TicketStatus.closed => 'Closed',
      };

  Tone get tone => switch (this) {
        TicketStatus.open => Tone.warning,
        TicketStatus.inProgress => Tone.info,
        TicketStatus.onHold => Tone.neutral,
        TicketStatus.resolved => Tone.success,
        TicketStatus.closed => Tone.neutral,
      };

  bool get isActive => this == TicketStatus.open || this == TicketStatus.inProgress || this == TicketStatus.onHold;
}

IconData iconFromName(String name) => switch (name) {
      'plumbing' => Icons.plumbing_rounded,
      'electrical' => Icons.electrical_services_rounded,
      'ac_unit' => Icons.ac_unit_rounded,
      'elevator' => Icons.elevator_rounded,
      'cleaning' => Icons.cleaning_services_rounded,
      'parking' => Icons.local_parking_rounded,
      'report' => Icons.report_problem_rounded,
      'police' => Icons.local_police_rounded,
      'ambulance' => Icons.medical_services_rounded,
      'fire' => Icons.local_fire_department_rounded,
      'emergency' => Icons.emergency_rounded,
      'shield' => Icons.shield_rounded,
      'engineering' => Icons.engineering_rounded,
      'favorite' => Icons.favorite_rounded,
      _ => Icons.more_horiz_rounded,
    };

class TicketCategory {
  const TicketCategory({required this.id, required this.name, required this.icon});

  factory TicketCategory.fromJson(Json j) =>
      TicketCategory(id: _str(j['id']), name: _str(j['name']), icon: iconFromName(_str(j['icon'])));

  final String id;
  final String name;
  final IconData icon;
}

class TicketUpdate {
  const TicketUpdate(this.message, this.time, {this.by = 'Facility team'});

  factory TicketUpdate.fromJson(Json j) =>
      TicketUpdate(_str(j['message']), _date(j['created_at']), by: _strOrNull(j['author_name']) ?? 'System');

  final String message;
  final DateTime time;
  final String by;
}

class Ticket {
  const Ticket({
    required this.id,
    required this.number,
    required this.title,
    required this.category,
    required this.description,
    required this.status,
    required this.createdAt,
    required this.priority,
    required this.updates,
    this.rating,
    this.attachments = const [],
  });

  factory Ticket.fromJson(Json j) => Ticket(
        id: _str(j['id']),
        number: _str(j['number']),
        title: _str(j['title']),
        category: _str(j['category_name']),
        description: _str(j['description']),
        status: _enum(TicketStatus.values, j['status'] as String?, TicketStatus.open, (s) => _snake(s.name)),
        createdAt: _date(j['created_at']),
        priority: '${_str(j['priority'])[0].toUpperCase()}${_str(j['priority']).substring(1)}',
        updates: (j['updates'] as List? ?? []).map((e) => TicketUpdate.fromJson(e as Json)).toList(),
        rating: (j['rating'] as num?)?.toInt(),
        attachments: [for (final a in (j['attachments'] as List? ?? [])) _str((a as Json)['file'])],
      );

  final String id;
  final String number;
  final String title;
  final String category;
  final String description;
  final TicketStatus status;
  final DateTime createdAt;
  final String priority;
  final List<TicketUpdate> updates;
  final int? rating;
  final List<String> attachments;
}

class EmergencyContact {
  const EmergencyContact({required this.id, required this.name, required this.phone, required this.group,
      required this.icon});

  factory EmergencyContact.fromJson(Json j) {
    const groups = {'public': 'Public services', 'community': 'Community', 'personal': 'Personal'};
    return EmergencyContact(
      id: _strOrNull(j['id']),
      name: _str(j['name']),
      phone: _str(j['phone']),
      group: groups[j['group']] ?? _str(j['group']),
      icon: iconFromName(_str(j['icon'])),
    );
  }

  final String? id;
  final String name;
  final String phone;
  final String group;
  final IconData icon;
}

class AppNotification {
  const AppNotification({required this.id, required this.title, required this.body, required this.time,
      required this.category, required this.data, this.read = false});

  factory AppNotification.fromJson(Json j) => AppNotification(
        id: _str(j['id']),
        title: _str(j['title']),
        body: _str(j['body']),
        time: _date(j['created_at']),
        category: _str(j['category']),
        data: Map<String, dynamic>.from(j['data'] as Map? ?? {}),
        read: j['is_read'] == true,
      );

  final String id;
  final String title;
  final String body;
  final DateTime time;
  final String category;
  final Map<String, dynamic> data;
  final bool read;

  IconData get icon => switch (category) {
        'gate' => Icons.door_sliding_rounded,
        'daily_help' => Icons.cleaning_services_rounded,
        'payment' => Icons.receipt_long_rounded,
        'notice' => Icons.campaign_rounded,
        'helpdesk' => Icons.support_agent_rounded,
        'security' => Icons.sos_rounded,
        'message' => Icons.chat_bubble_rounded,
        _ => Icons.notifications_rounded,
      };

  Tone get tone => switch (category) {
        'gate' => Tone.warning,
        'daily_help' => Tone.success,
        'payment' => Tone.danger,
        'notice' => Tone.info,
        'security' => Tone.danger,
        _ => Tone.primary,
      };
}

class Conversation {
  const Conversation({required this.id, required this.otherName, this.lastMessage, this.unread = 0});

  factory Conversation.fromJson(Json j) => Conversation(
        id: _str(j['id']),
        otherName: _str((j['other_user'] as Json)['name']),
        lastMessage: _strOrNull(j['last_message']),
        unread: (j['unread'] as num?)?.toInt() ?? 0,
      );

  final String id;
  final String otherName;
  final String? lastMessage;
  final int unread;
}

class ChatMessage {
  const ChatMessage({required this.text, required this.time, required this.mine});

  factory ChatMessage.fromJson(Json j) =>
      ChatMessage(text: _str(j['body']), time: _date(j['created_at']), mine: j['is_mine'] == true);

  final String text;
  final DateTime time;
  final bool mine;
}

class SearchResult {
  const SearchResult({required this.type, required this.id, required this.title, required this.subtitle});

  factory SearchResult.fromJson(Json j) =>
      SearchResult(type: _str(j['type']), id: _str(j['id']), title: _str(j['title']), subtitle: _str(j['subtitle']));

  final String type;
  final String id;
  final String title;
  final String subtitle;
}
