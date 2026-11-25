import 'package:flutter/material.dart';

import '../../core/widgets/status_chip.dart';
import '../../data/models.dart';
import 'manage_kit.dart';

/// Every management area as a [ResourceSpec]. Paths match the Django /manage/ API.

String _s(Json j, String k) => '${j[k] ?? ''}';
(String, Tone) _status(Json j, [String key = 'status']) => (humanize(j[key]), toneFor(_s(j, key)));
String _join(List<Object?> parts) => parts.map((e) => '${e ?? ''}'.trim()).where((e) => e.isNotEmpty).join(' · ');

const _unitTypes = ['apartment', 'villa', 'townhouse', 'office', 'shop'];
const _note = [FieldSpec('note', 'Note to resident (optional)', type: FieldType.multiline)];

// ---------------------------------------------------------------------------
// Residents & property
// ---------------------------------------------------------------------------

final memberships = ResourceSpec(
  key: 'residents',
  title: 'Residents',
  icon: Icons.people_alt_rounded,
  path: '/manage/memberships/',
  titleOf: (j) => '${(j['user'] as Json?)?['full_name'] ?? ''}'.trim().isEmpty
      ? '${(j['user'] as Json?)?['phone'] ?? 'Resident'}'
      : '${(j['user'] as Json)['full_name']}',
  subtitleOf: (j) => _join([j['unit_label'], humanize(j['role']), (j['user'] as Json?)?['phone']]),
  chipOf: _status,
  detailsOf: (j) => [
    ('Flat', _s(j, 'unit_label')),
    ('Role', humanize(j['role'])),
    ('Phone', '${(j['user'] as Json?)?['phone'] ?? ''}'),
    ('Requested', fmtDate(j['created_at'])),
    ('Approved', fmtDate(j['approved_at'])),
    ('Note', _s(j, 'note')),
  ],
  filters: const [
    FilterSpec('Pending', {'status': 'pending'}),
    FilterSpec('Approved', {'status': 'approved'}),
    FilterSpec('Moved out', {'status': 'moved_out'}),
    FilterSpec('Rejected', {'status': 'rejected'}),
    FilterSpec('All', {}),
  ],
  towerFilter: 'unit__tower',
  sendCommunity: false,
  canEdit: false,
  createLabel: 'Add resident',
  emptyMessage: 'New sign-ups who request a flat appear here for approval.',
  fields: const [
    FieldSpec('unit', 'Flat', type: FieldType.ref, refPath: '/manage/units/', refLabel: 'label', required: true),
    FieldSpec('role', 'Role', type: FieldType.choice, choices: ['owner', 'tenant', 'family'], required: true, initial: 'owner'),
    FieldSpec('user_phone', 'Mobile number', type: FieldType.phone, required: true,
        hint: 'With country code, e.g. +919812345678. They log in with this number.'),
    FieldSpec('full_name', 'Full name'),
    FieldSpec('note', 'Note'),
  ],
  actions: [
    RowAction('Approve', icon: Icons.check_circle_rounded, path: 'approve/', tone: Tone.success,
        visible: (j) => j['status'] == 'pending' || j['status'] == 'rejected', success: 'Approved. The resident has been notified.'),
    RowAction('Reject', icon: Icons.cancel_rounded, path: 'reject/', tone: Tone.danger,
        visible: (j) => j['status'] == 'pending', confirm: 'Reject this request?'),
    RowAction('Mark moved out', icon: Icons.logout_rounded, path: 'move-out/', tone: Tone.warning,
        visible: (j) => j['status'] == 'approved', confirm: 'Mark this resident as moved out? They lose access to the flat.'),
  ],
);

final towers = ResourceSpec(
  key: 'towers',
  title: 'Towers',
  icon: Icons.apartment_rounded,
  path: '/manage/towers/',
  titleOf: (j) => _s(j, 'name'),
  subtitleOf: (j) => _join([
    '${j['floors']} floors · ${j['units_count'] ?? 0} flats',
    j['maintenance_amount'] == null ? null : 'Maintenance ${fmtMoney(j['maintenance_amount'])}',
  ]),
  chipOf: (j) => j['approval_mode'] == 'auto' ? ('Auto-approve', Tone.info) : ('Manual approval', Tone.neutral),
  detailsOf: (j) => [
    ('Code', _s(j, 'code')),
    ('Floors', _s(j, 'floors')),
    ('Flats', _s(j, 'units_count')),
    ('Approval', j['approval_mode'] == 'auto' ? 'New residents are approved automatically' : 'Tower / community admin approves'),
    ('Maintenance', j['maintenance_amount'] == null ? 'Not set (uses charge type amount)' : fmtMoney(j['maintenance_amount'])),
    ('Lifts', _s(j, 'lifts')),
    ('Parking slots', _s(j, 'parking_slots')),
    ('Contact', _join([j['contact_name'], j['contact_phone']])),
  ],
  createLabel: 'Add tower',
  fields: const [
    FieldSpec('name', 'Tower name', required: true, hint: 'e.g. Tower C'),
    FieldSpec('code', 'Short code', hint: 'e.g. C'),
    FieldSpec('floors', 'Floors', type: FieldType.integer),
    FieldSpec('approval_mode', 'New resident approval', type: FieldType.choice, choices: ['manual', 'auto'], initial: 'manual',
        hint: 'Manual: the tower admin or community admin approves each request. Auto: residents get access right away.'),
    FieldSpec('maintenance_amount', 'Monthly maintenance per flat', type: FieldType.decimal,
        hint: 'Used automatically when you "Bill all flats" without entering an amount.'),
    FieldSpec('lifts', 'Lifts', type: FieldType.integer),
    FieldSpec('parking_slots', 'Parking slots', type: FieldType.integer),
    FieldSpec('contact_name', 'Tower contact person'),
    FieldSpec('contact_phone', 'Contact phone', type: FieldType.phone),
  ],
  actions: const [
    RowAction('Generate flats', icon: Icons.auto_awesome_mosaic_rounded, path: 'generate-units/',
        success: 'Flats created',
        fields: [
          FieldSpec('floor_from', 'From floor', type: FieldType.integer, required: true, initial: 1),
          FieldSpec('floor_to', 'To floor', type: FieldType.integer, required: true),
          FieldSpec('units_per_floor', 'Flats per floor', type: FieldType.integer, required: true, initial: 4),
          FieldSpec('unit_type', 'Type', type: FieldType.choice, choices: _unitTypes, initial: 'apartment'),
          FieldSpec('number_format', 'Numbering', initial: '{floor}{index:02d}',
              hint: '{floor}{index:02d} gives 101, 102 … Existing numbers are skipped.'),
        ]),
  ],
);

final units = ResourceSpec(
  key: 'units',
  title: 'Flats',
  icon: Icons.door_front_door_rounded,
  path: '/manage/units/',
  titleOf: (j) => _s(j, 'label'),
  subtitleOf: (j) => _join([humanize(j['unit_type']), j['floor'] == null ? null : 'Floor ${j['floor']}',
    j['bedrooms'] == null ? null : '${j['bedrooms']} BR', j['area_sqft'] == null ? null : '${j['area_sqft']} sqft']),
  towerFilter: 'tower',
  sendCommunity: false,
  createLabel: 'Add flat',
  fields: const [
    FieldSpec('tower', 'Tower', type: FieldType.ref, refPath: '/manage/towers/', required: true),
    FieldSpec('number', 'Flat number', required: true),
    FieldSpec('floor', 'Floor', type: FieldType.integer),
    FieldSpec('unit_type', 'Type', type: FieldType.choice, choices: _unitTypes, initial: 'apartment'),
    FieldSpec('bedrooms', 'Bedrooms', type: FieldType.integer),
    FieldSpec('area_sqft', 'Area (sq ft)', type: FieldType.integer),
  ],
);

final gates = ResourceSpec(
  key: 'gates',
  title: 'Gates',
  icon: Icons.fence_rounded,
  path: '/manage/gates/',
  titleOf: (j) => _s(j, 'name'),
  subtitleOf: (j) => j['iot_enabled'] == true ? 'Boom barrier connected' : 'Manual gate',
  chipOf: (j) => j['is_active'] == true ? ('Active', Tone.success) : ('Inactive', Tone.neutral),
  createLabel: 'Add gate',
  fields: const [
    FieldSpec('name', 'Gate name', required: true),
    FieldSpec('is_active', 'Active', type: FieldType.boolean, initial: true),
    FieldSpec('iot_enabled', 'Boom barrier / controller connected', type: FieldType.boolean),
    FieldSpec('iot_device_id', 'Device ID'),
  ],
);

// ---------------------------------------------------------------------------
// People
// ---------------------------------------------------------------------------

final staff = ResourceSpec(
  key: 'staff',
  title: 'Staff & roles',
  icon: Icons.badge_rounded,
  path: '/manage/staff/',
  titleOf: (j) => _s(j, 'name'),
  subtitleOf: (j) => _join([humanize(j['role']), j['designation'], j['phone']]),
  chipOf: (j) => j['is_active'] != true
      ? ('Inactive', Tone.neutral)
      : ((j['tower_names'] as List? ?? []).isEmpty
          ? (humanize(j['role']), Tone.primary)
          : ((j['tower_names'] as List).join(', '), Tone.info)),
  detailsOf: (j) => [
    ('Role', humanize(j['role'])),
    ('Manages', (j['tower_names'] as List? ?? []).isEmpty ? 'Whole community' : (j['tower_names'] as List).join(', ')),
    ('Designation', _s(j, 'designation')),
    ('Phone', _s(j, 'phone')),
    ('Shift', _s(j, 'shift')),
    ('App login', j['user'] == null ? 'No (directory only)' : 'Yes'),
  ],
  filters: const [
    FilterSpec('All', {}),
    FilterSpec('Admins', {'role': 'admin'}),
    FilterSpec('Managers', {'role': 'manager'}),
    FilterSpec('Guards', {'role': 'guard'}),
    FilterSpec('Facility', {'role': 'facility'}),
  ],
  createLabel: 'Add staff',
  emptyMessage: 'Add guards, managers and facility staff. Give a login phone to let them use the app.',
  fields: const [
    FieldSpec('name', 'Name', required: true),
    FieldSpec('role', 'Role', type: FieldType.choice, required: true, initial: 'guard',
        choices: ['admin', 'manager', 'guard', 'committee', 'facility', 'other']),
    FieldSpec('user_phone', 'App login phone', type: FieldType.phone, createOnly: true,
        hint: 'With country code, e.g. +919812345678. Admins, managers and guards log in with this number using OTP.'),
    FieldSpec('phone', 'Contact phone', type: FieldType.phone),
    FieldSpec('towers', 'Only these towers', type: FieldType.refMulti, refPath: '/manage/towers/',
        hint: 'Pick towers to make this person a tower admin: they see and approve only those towers. '
            'Leave empty for the whole community.'),
    FieldSpec('designation', 'Designation', hint: 'e.g. Security supervisor'),
    FieldSpec('shift', 'Shift', hint: 'e.g. Day 8am–8pm'),
    FieldSpec('show_in_directory', 'Show in resident directory', type: FieldType.boolean, initial: true),
    FieldSpec('is_active', 'Active', type: FieldType.boolean, initial: true),
  ],
);

final emergencyContacts = ResourceSpec(
  key: 'emergency-contacts',
  title: 'Emergency contacts',
  icon: Icons.local_hospital_rounded,
  path: '/manage/emergency-contacts/',
  titleOf: (j) => _s(j, 'name'),
  subtitleOf: (j) => _s(j, 'phone'),
  createLabel: 'Add contact',
  fields: const [
    FieldSpec('name', 'Name', required: true, hint: 'e.g. Society office, Nearest hospital'),
    FieldSpec('phone', 'Phone', type: FieldType.phone, required: true),
    FieldSpec('order', 'Order', type: FieldType.integer, hint: 'Lower numbers show first'),
  ],
);

// ---------------------------------------------------------------------------
// Finance
// ---------------------------------------------------------------------------

final chargeTypes = ResourceSpec(
  key: 'charge-types',
  title: 'Charge types',
  icon: Icons.category_rounded,
  path: '/manage/charge-types/',
  titleOf: (j) => _s(j, 'name'),
  subtitleOf: (j) => _join([fmtMoney(j['default_amount']), humanize(j['frequency']), j['is_taxable'] == true ? 'Taxable' : 'No tax']),
  chipOf: (j) => j['is_active'] == true ? null : ('Inactive', Tone.neutral),
  createLabel: 'Add charge type',
  emptyMessage: 'e.g. Maintenance, Water, Parking, Clubhouse.',
  fields: const [
    FieldSpec('name', 'Name', required: true, hint: 'e.g. Monthly maintenance'),
    FieldSpec('default_amount', 'Default amount', type: FieldType.decimal),
    FieldSpec('frequency', 'Frequency', type: FieldType.choice, choices: ['one_time', 'monthly', 'quarterly', 'yearly'],
        initial: 'monthly'),
    FieldSpec('is_taxable', 'Add tax (GST / VAT)', type: FieldType.boolean, initial: true),
    FieldSpec('is_active', 'Active', type: FieldType.boolean, initial: true),
  ],
);

final invoices = ResourceSpec(
  key: 'invoices',
  title: 'Bills',
  icon: Icons.receipt_long_rounded,
  path: '/manage/invoices/',
  titleOf: (j) => _join([j['unit_label'], j['title']]),
  subtitleOf: (j) => _join([j['number'], fmtMoney(j['total'], j['currency']), 'Due ${fmtDate(j['due_date'])}']),
  chipOf: (j) => j['is_overdue'] == true ? ('Overdue', Tone.danger) : _status(j),
  detailsOf: (j) => [
    ('Bill no.', _s(j, 'number')),
    ('Flat', _s(j, 'unit_label')),
    ('Period', _s(j, 'period_label')),
    ('Amount', fmtMoney(j['amount'], j['currency'])),
    ('${j['tax_name'] ?? 'Tax'} (${j['tax_rate']}%)', fmtMoney(j['tax_amount'], j['currency'])),
    ('Total', fmtMoney(j['total'], j['currency'])),
    ('Paid', fmtMoney(j['paid_amount'], j['currency'])),
    ('Balance', fmtMoney(j['balance'], j['currency'])),
    ('Due', fmtDate(j['due_date'])),
  ],
  filters: const [
    FilterSpec('Unpaid', {'status': 'unpaid'}),
    FilterSpec('Part paid', {'status': 'partially_paid'}),
    FilterSpec('Paid', {'status': 'paid'}),
    FilterSpec('Cancelled', {'status': 'cancelled'}),
    FilterSpec('All', {}),
  ],
  towerFilter: 'unit__tower',
  sendCommunity: false,
  canEdit: false,
  canDelete: false,
  createLabel: 'Raise a bill',
  fields: const [
    FieldSpec('unit', 'Flat', type: FieldType.ref, refPath: '/manage/units/', refLabel: 'label', required: true),
    FieldSpec('charge_type', 'Charge type', type: FieldType.ref, refPath: '/manage/charge-types/'),
    FieldSpec('title', 'Title', hint: 'Leave empty to use the charge type name'),
    FieldSpec('period_label', 'Period', hint: 'e.g. December 2026'),
    FieldSpec('amount', 'Amount (before tax)', type: FieldType.decimal, hint: 'Leave empty to use the charge type amount'),
    FieldSpec('due_date', 'Due date', type: FieldType.date, required: true),
    FieldSpec('taxable', 'Add tax', type: FieldType.boolean, initial: true),
  ],
  actions: [
    RowAction('Record cash / cheque payment', icon: Icons.payments_rounded, path: 'record-payment/', tone: Tone.success,
        visible: (j) => j['status'] == 'unpaid' || j['status'] == 'partially_paid',
        success: 'Payment recorded',
        fields: const [
          FieldSpec('amount', 'Amount received', type: FieldType.decimal, required: true),
          FieldSpec('method', 'Method', type: FieldType.choice, choices: ['cash', 'cheque', 'bank_transfer'], required: true,
              initial: 'cash'),
          FieldSpec('reference', 'Reference', hint: 'Cheque no. or transfer ID'),
        ]),
    RowAction('Cancel bill', icon: Icons.block_rounded, path: 'cancel/', tone: Tone.danger,
        visible: (j) => j['status'] == 'unpaid', confirm: 'Cancel this bill? The resident will no longer see it as due.'),
  ],
);

/// Form-only: raise the same bill for every flat (optionally one tower).
const bulkBillFields = [
  FieldSpec('charge_type', 'Charge type', type: FieldType.ref, refPath: '/manage/charge-types/'),
  FieldSpec('title', 'Title', hint: 'Leave empty to use the charge type name, or "Maintenance"'),
  FieldSpec('amount', 'Amount per flat (before tax)', type: FieldType.decimal,
      hint: "Leave empty to use each tower's own maintenance amount (set in Towers), else the charge type amount"),
  FieldSpec('period_label', 'Period', hint: 'e.g. December 2026'),
  FieldSpec('due_date', 'Due date', type: FieldType.date, required: true),
  FieldSpec('tower', 'Only this tower', type: FieldType.ref, refPath: '/manage/towers/'),
  FieldSpec('taxable', 'Add tax', type: FieldType.boolean, initial: true),
  FieldSpec('only_occupied', 'Only flats with an approved resident', type: FieldType.boolean, initial: true),
];

final payments = ResourceSpec(
  key: 'payments',
  title: 'Payments',
  icon: Icons.account_balance_wallet_rounded,
  path: '/manage/payments/',
  titleOf: (j) => _join([j['unit_label'], fmtMoney(j['amount'], j['currency'])]),
  subtitleOf: (j) => _join([humanize(j['method']), j['reference'], fmtDate(j['paid_at'] ?? j['created_at'])]),
  chipOf: _status,
  detailsOf: (j) => [
    ('Reference', _s(j, 'reference')),
    ('Flat', _s(j, 'unit_label')),
    ('Amount', fmtMoney(j['amount'], j['currency'])),
    ('Method', humanize(j['method'])),
    ('Gateway', _s(j, 'gateway')),
    ('Paid at', fmtDate(j['paid_at'])),
  ],
  filters: const [FilterSpec('Successful', {'status': 'success'}), FilterSpec('All', {})],
  canCreate: false,
  canEdit: false,
  canDelete: false,
);

final defaulters = ResourceSpec(
  key: 'defaulters',
  title: 'Defaulters',
  icon: Icons.warning_amber_rounded,
  path: '/manage/defaulters/',
  idKey: 'unit',
  titleOf: (j) => _s(j, 'unit_label'),
  subtitleOf: (j) => _join([(j['residents'] as List? ?? []).join(', '), '${j['overdue_invoices']} bills']),
  chipOf: (j) => (fmtMoney(j['overdue_amount'], j['currency']), Tone.danger),
  detailsOf: (j) => [
    ('Overdue', fmtMoney(j['overdue_amount'], j['currency'])),
    ('Bills', _s(j, 'overdue_invoices')),
    ('Oldest due', fmtDate(j['oldest_due_date'])),
    ('Days overdue', _s(j, 'days_overdue')),
    ('Residents', (j['residents'] as List? ?? []).join(', ')),
  ],
  filters: const [FilterSpec('All overdue', {}), FilterSpec('30+ days', {'min_days': '30'}), FilterSpec('90+ days', {'min_days': '90'})],
  canCreate: false,
  canEdit: false,
  canDelete: false,
  searchable: false,
  emptyMessage: 'No overdue bills. 🎉',
  actions: [
    RowAction('Send reminder', icon: Icons.notifications_active_rounded, path: '/manage/defaulters/remind/',
        body: (j) => {'units': [j['unit']]},
        sendCommunity: true,
        success: 'Reminder sent',
        fields: const [FieldSpec('message', 'Message (optional)', type: FieldType.multiline)]),
  ],
);

// ---------------------------------------------------------------------------
// Help desk
// ---------------------------------------------------------------------------

final tickets = ResourceSpec(
  key: 'tickets',
  title: 'Help desk',
  icon: Icons.support_agent_rounded,
  path: '/manage/tickets/',
  titleOf: (j) => _s(j, 'title'),
  subtitleOf: (j) => _join([j['number'], j['unit_label'], j['category_name'], humanize(j['priority'])]),
  chipOf: _status,
  detailsOf: (j) => [
    ('Ticket', _s(j, 'number')),
    ('Flat', _s(j, 'unit_label')),
    ('Raised by', _s(j, 'raised_by_name')),
    ('Category', _s(j, 'category_name')),
    ('Priority', humanize(j['priority'])),
    ('Assigned to', _s(j, 'assigned_to_name')),
    ('Raised', fmtDate(j['created_at'])),
    ('Details', _s(j, 'description')),
    if (j['rating'] != null) ('Rating', '${j['rating']}★ ${j['rating_comment'] ?? ''}'),
    ('History', [
      for (final u in (j['updates'] as List? ?? []).cast<Json>())
        '• ${fmtDate(u['created_at'])} ${u['author_name'] ?? ''}: ${(u['message'] ?? '').toString().isNotEmpty ? u['message'] : humanize(u['status_change'] ?? '')}'
            '${u['is_internal'] == true ? ' (internal)' : ''}',
    ].join('\n')),
  ],
  filters: const [
    FilterSpec('Open', {'status': 'open'}),
    FilterSpec('In progress', {'status': 'in_progress'}),
    FilterSpec('On hold', {'status': 'on_hold'}),
    FilterSpec('Resolved', {'status': 'resolved'}),
    FilterSpec('Closed', {'status': 'closed'}),
    FilterSpec('All', {}),
  ],
  canCreate: false,
  canDelete: false,
  canEdit: false,
  emptyMessage: 'Complaints and requests raised by residents appear here.',
  actions: const [
    RowAction('Update status / assign', icon: Icons.edit_note_rounded, method: 'patch', success: 'Ticket updated',
        fields: [
          FieldSpec('status', 'Status', type: FieldType.choice,
              choices: ['open', 'in_progress', 'on_hold', 'resolved', 'closed']),
          FieldSpec('priority', 'Priority', type: FieldType.choice, choices: ['low', 'medium', 'high', 'urgent']),
          FieldSpec('assigned_to', 'Assign to staff', type: FieldType.ref, refPath: '/manage/staff/'),
        ]),
    RowAction('Reply / add note', icon: Icons.chat_bubble_outline_rounded, path: 'comment/', success: 'Comment added',
        fields: [
          FieldSpec('message', 'Message', type: FieldType.multiline, required: true),
          FieldSpec('is_internal', 'Internal note (hidden from resident)', type: FieldType.boolean),
        ]),
  ],
);

final ticketCategories = ResourceSpec(
  key: 'ticket-categories',
  title: 'Help desk categories',
  icon: Icons.label_rounded,
  path: '/manage/ticket-categories/',
  titleOf: (j) => _s(j, 'name'),
  subtitleOf: (j) => j['sla_hours'] == null ? '' : 'Resolve within ${j['sla_hours']} h',
  createLabel: 'Add category',
  fields: const [
    FieldSpec('name', 'Name', required: true),
    FieldSpec('icon', 'Icon name', hint: 'Material icon, e.g. plumbing, electrical_services'),
    FieldSpec('sla_hours', 'Target resolution (hours)', type: FieldType.integer),
    FieldSpec('is_active', 'Active', type: FieldType.boolean, initial: true),
  ],
);

// ---------------------------------------------------------------------------
// Communication
// ---------------------------------------------------------------------------

final notices = ResourceSpec(
  key: 'notices',
  title: 'Notices',
  icon: Icons.campaign_rounded,
  path: '/manage/notices/',
  titleOf: (j) => _s(j, 'title'),
  subtitleOf: (j) => _join([humanize(j['category']), fmtDate(j['published_at'] ?? j['created_at'])]),
  chipOf: (j) => j['is_pinned'] == true ? ('Pinned', Tone.primary) : null,
  detailsOf: (j) => [('Message', _s(j, 'body')), ('Expires', fmtDate(j['expires_at'])), ('By', _s(j, 'author_label'))],
  createLabel: 'Post notice',
  fields: const [
    FieldSpec('title', 'Title', required: true),
    FieldSpec('body', 'Message', type: FieldType.multiline, required: true),
    FieldSpec('category', 'Category', type: FieldType.choice, initial: 'General',
        choices: ['General', 'Maintenance', 'Event', 'Security', 'Finance', 'Emergency']),
    FieldSpec('target_towers', 'Only for towers', type: FieldType.refMulti, refPath: '/manage/towers/'),
    FieldSpec('is_pinned', 'Pin to top', type: FieldType.boolean),
    FieldSpec('author_label', 'Signed as', hint: 'e.g. Management Committee'),
    FieldSpec('expires_at', 'Expires on', type: FieldType.dateTime),
    FieldSpec('notify', 'Send push notification', type: FieldType.boolean, initial: true, createOnly: true),
  ],
);

final polls = ResourceSpec(
  key: 'polls',
  title: 'Polls',
  icon: Icons.how_to_vote_rounded,
  path: '/manage/polls/',
  titleOf: (j) => _s(j, 'question'),
  subtitleOf: (j) => '${j['total_votes'] ?? 0} votes · closes ${fmtDate(j['closes_at'])}',
  chipOf: (j) => j['is_closed'] == true ? ('Closed', Tone.neutral) : ('Open', Tone.success),
  detailsOf: (j) => [
    ('Description', _s(j, 'description')),
    ('Results', [
      for (final o in (j['options'] as List? ?? []).cast<Json>())
        '${o['label']}: ${o['votes']} (${(num.tryParse('${o['percent']}') ?? 0).round()}%)',
    ].join('\n')),
    ('Voting', j['one_vote_per_unit'] == true ? 'One vote per flat' : 'One vote per person'),
  ],
  canEdit: false,
  createLabel: 'Create poll',
  fields: const [
    FieldSpec('question', 'Question', required: true),
    FieldSpec('description', 'Description', type: FieldType.multiline),
    FieldSpec('option_labels', 'Options (one per line)', type: FieldType.lines, required: true, hint: 'At least two'),
    FieldSpec('closes_at', 'Closes on', type: FieldType.dateTime, required: true),
    FieldSpec('one_vote_per_unit', 'One vote per flat', type: FieldType.boolean, initial: true),
  ],
);

final events = ResourceSpec(
  key: 'events',
  title: 'Events',
  icon: Icons.celebration_rounded,
  path: '/manage/events/',
  titleOf: (j) => _s(j, 'title'),
  subtitleOf: (j) => _join([fmtDate(j['starts_at']), j['venue'], '${j['attendees'] ?? 0} going']),
  detailsOf: (j) => [
    ('When', '${fmtDate(j['starts_at'])}${j['ends_at'] == null ? '' : ' – ${fmtDate(j['ends_at'])}'}'),
    ('Venue', _s(j, 'venue')),
    ('Going', _s(j, 'attendees')),
    ('Capacity', _s(j, 'capacity')),
    ('Details', _s(j, 'description')),
  ],
  createLabel: 'Create event',
  fields: const [
    FieldSpec('title', 'Title', required: true),
    FieldSpec('venue', 'Venue', required: true),
    FieldSpec('starts_at', 'Starts', type: FieldType.dateTime, required: true),
    FieldSpec('ends_at', 'Ends', type: FieldType.dateTime),
    FieldSpec('category', 'Category', hint: 'e.g. Festival, Sports, Meeting'),
    FieldSpec('capacity', 'Capacity', type: FieldType.integer),
    FieldSpec('description', 'Details', type: FieldType.multiline),
  ],
);

// ---------------------------------------------------------------------------
// Requests & services
// ---------------------------------------------------------------------------

final moveRequests = ResourceSpec(
  key: 'move-requests',
  title: 'Move in / out',
  icon: Icons.local_shipping_rounded,
  path: '/manage/move-requests/',
  titleOf: (j) => _join([humanize(j['move_type']), j['unit_label']]),
  subtitleOf: (j) => _join([fmtDate(j['move_date']), j['moving_company']]),
  chipOf: _status,
  detailsOf: (j) => [
    ('Flat', _s(j, 'unit_label')),
    ('Date', fmtDate(j['move_date'])),
    ('Movers', _s(j, 'moving_company')),
    ('Service lift', j['service_lift'] == true ? 'Needed' : 'No'),
    ('Notes', _s(j, 'notes')),
    ('Review note', _s(j, 'review_note')),
    ('Documents', '${(j['documents'] as List? ?? []).length}'),
  ],
  filters: const [
    FilterSpec('Pending', {'status': 'pending'}),
    FilterSpec('Approved', {'status': 'approved'}),
    FilterSpec('Completed', {'status': 'completed'}),
    FilterSpec('All', {}),
  ],
  canCreate: false,
  canEdit: false,
  canDelete: false,
  actions: [
    RowAction('Approve', icon: Icons.check_circle_rounded, path: 'approve/', tone: Tone.success, fields: _note,
        visible: (j) => j['status'] == 'pending'),
    RowAction('Reject', icon: Icons.cancel_rounded, path: 'reject/', tone: Tone.danger, fields: _note,
        visible: (j) => j['status'] == 'pending'),
    RowAction('Mark completed', icon: Icons.done_all_rounded, path: 'complete/', fields: _note,
        visible: (j) => j['status'] == 'approved'),
  ],
);

final vendors = ResourceSpec(
  key: 'vendors',
  title: 'Service vendors',
  icon: Icons.handyman_rounded,
  path: '/manage/vendors/',
  titleOf: (j) => _s(j, 'name'),
  subtitleOf: (j) => _join([j['category'], j['phone'], j['price_from'] == null ? null : 'From ${fmtMoney(j['price_from'], j['currency'])}']),
  chipOf: (j) => j['is_active'] == true ? null : ('Hidden', Tone.neutral),
  createLabel: 'Add vendor',
  fields: const [
    FieldSpec('name', 'Name', required: true),
    FieldSpec('category', 'Category', required: true, hint: 'e.g. Plumber, Electrician, Cleaning'),
    FieldSpec('phone', 'Phone', type: FieldType.phone),
    FieldSpec('price_from', 'Starting price', type: FieldType.decimal),
    FieldSpec('eta_text', 'Arrival time', hint: 'e.g. Within 2 hours'),
    FieldSpec('description', 'Description', type: FieldType.multiline),
    FieldSpec('is_active', 'Visible to residents', type: FieldType.boolean, initial: true),
  ],
);

final bookings = ResourceSpec(
  key: 'bookings',
  title: 'Service bookings',
  icon: Icons.event_available_rounded,
  path: '/manage/bookings/',
  titleOf: (j) => _join([j['vendor_name'], j['unit_label']]),
  subtitleOf: (j) => _join([fmtDate(j['slot_start']), j['notes']]),
  chipOf: _status,
  canCreate: false,
  canEdit: false,
  canDelete: false,
);

// ---------------------------------------------------------------------------
// Security
// ---------------------------------------------------------------------------

final visitorLog = ResourceSpec(
  key: 'visitor-log',
  title: 'Visitor log',
  icon: Icons.groups_rounded,
  path: '/manage/visitor-log/',
  titleOf: (j) => _s(j, 'name'),
  subtitleOf: (j) => _join([humanize(j['visitor_type']), j['unit_label'], fmtDate(j['checked_in_at'] ?? j['expected_at'] ?? j['created_at'])]),
  chipOf: (j) => (_s(j, 'status_label').isEmpty ? humanize(j['status']) : _s(j, 'status_label'), toneFor(_s(j, 'status'))),
  detailsOf: (j) => [
    ('Phone', _s(j, 'phone')),
    ('Type', humanize(j['visitor_type'])),
    ('Company', _s(j, 'company')),
    ('Vehicle', _s(j, 'vehicle_no')),
    ('Flat', _s(j, 'unit_label')),
    ('Gate', _s(j, 'gate_name')),
    ('In', fmtDate(j['checked_in_at'])),
    ('Out', fmtDate(j['checked_out_at'])),
    ('Walk-in', j['is_walk_in'] == true ? 'Yes' : 'No (pre-approved)'),
  ],
  filters: const [
    FilterSpec('All', {}),
    FilterSpec('Inside now', {'status': 'inside'}),
    FilterSpec('Waiting', {'status': 'waiting'}),
    FilterSpec('Expected', {'status': 'expected'}),
    FilterSpec('Exited', {'status': 'exited'}),
    FilterSpec('Denied', {'status': 'denied'}),
  ],
  towerFilter: 'unit__tower',
  canCreate: false,
  canEdit: false,
  canDelete: false,
);

final sos = ResourceSpec(
  key: 'sos',
  title: 'SOS alerts',
  icon: Icons.sos_rounded,
  path: '/manage/sos/',
  titleOf: (j) => _join([humanize(j['alert_type']), j['unit_label']]),
  subtitleOf: (j) => _join([j['raised_by_name'], j['raised_by_phone'], fmtDate(j['created_at'])]),
  chipOf: _status,
  detailsOf: (j) => [('Message', _s(j, 'message')), ('Acknowledged', fmtDate(j['acknowledged_at'])), ('Resolved', fmtDate(j['resolved_at']))],
  filters: const [FilterSpec('Active', {'status': 'active'}), FilterSpec('Acknowledged', {'status': 'acknowledged'}), FilterSpec('All', {})],
  canCreate: false,
  canEdit: false,
  canDelete: false,
  searchable: false,
  actions: [
    RowAction('Acknowledge', icon: Icons.visibility_rounded, path: '/guard/sos/{id}/acknowledge/',
        visible: (j) => j['status'] == 'active'),
    RowAction('Mark resolved', icon: Icons.check_circle_rounded, path: '/guard/sos/{id}/resolve/', tone: Tone.success,
        visible: (j) => j['status'] == 'active' || j['status'] == 'acknowledged'),
  ],
);

final incidents = ResourceSpec(
  key: 'incidents',
  title: 'Incidents',
  icon: Icons.report_gmailerrorred_rounded,
  path: '/manage/incidents/',
  titleOf: (j) => _s(j, 'title'),
  subtitleOf: (j) => _join([j['category'], j['location'], fmtDate(j['created_at'])]),
  chipOf: (j) => (humanize(j['severity']), toneFor(j['status'] == 'resolved' ? 'resolved' : _s(j, 'severity'))),
  detailsOf: (j) => [
    ('Status', humanize(j['status'])),
    ('Severity', humanize(j['severity'])),
    ('Location', _s(j, 'location')),
    ('Flat', _s(j, 'unit_label')),
    ('Reported by', _s(j, 'reported_by_name')),
    ('Details', _s(j, 'description')),
    ('Resolution', _s(j, 'resolution')),
  ],
  filters: const [
    FilterSpec('Open', {'status': 'open'}),
    FilterSpec('Investigating', {'status': 'investigating'}),
    FilterSpec('Resolved', {'status': 'resolved'}),
    FilterSpec('All', {}),
  ],
  canCreate: false,
  canEdit: false,
  canDelete: false,
  actions: const [
    RowAction('Update', icon: Icons.edit_note_rounded, path: '/guard/incidents/{id}/', method: 'patch', success: 'Incident updated',
        fields: [
          FieldSpec('status', 'Status', type: FieldType.choice, choices: ['open', 'investigating', 'resolved']),
          FieldSpec('resolution', 'Resolution / notes', type: FieldType.multiline),
        ]),
  ],
);

// ---------------------------------------------------------------------------
// Moderation
// ---------------------------------------------------------------------------

final forum = ResourceSpec(
  key: 'forum',
  title: 'Forum posts',
  icon: Icons.forum_rounded,
  path: '/manage/forum/',
  titleOf: (j) => _s(j, 'title'),
  subtitleOf: (j) => _join([j['author_name'], j['unit_label'], '${j['replies_count'] ?? 0} replies', fmtDate(j['created_at'])]),
  chipOf: (j) => j['is_locked'] == true ? ('Locked', Tone.neutral) : null,
  detailsOf: (j) => [('Post', _s(j, 'body'))],
  canCreate: false,
  canEdit: false,
  actions: [
    RowAction('Lock / unlock replies', icon: Icons.lock_rounded, path: 'lock/', tone: Tone.warning),
  ],
);

final classifieds = ResourceSpec(
  key: 'classifieds',
  title: 'Classifieds',
  icon: Icons.sell_rounded,
  path: '/manage/classifieds/',
  titleOf: (j) => _s(j, 'title'),
  subtitleOf: (j) => _join([fmtMoney(j['price'], j['currency']), j['seller_name'], j['unit_label']]),
  chipOf: _status,
  detailsOf: (j) => [('Description', _s(j, 'description')), ('Category', _s(j, 'category'))],
  filters: const [FilterSpec('Active', {'status': 'active'}), FilterSpec('All', {})],
  canCreate: false,
  canEdit: false,
  canDelete: false,
  actions: [
    RowAction('Remove listing', icon: Icons.delete_sweep_rounded, path: 'remove/', tone: Tone.danger,
        visible: (j) => j['status'] == 'active', confirm: 'Remove this listing from the marketplace?'),
  ],
);

// ---------------------------------------------------------------------------
// Settings & platform
// ---------------------------------------------------------------------------

const communitySettingsFields = [
  FieldSpec('name', 'Community name', required: true),
  FieldSpec('address', 'Address', type: FieldType.multiline),
  FieldSpec('contact_phone', 'Office phone', type: FieldType.phone),
  FieldSpec('contact_email', 'Office email'),
  FieldSpec('primary_color', 'Brand colour', hint: 'Hex, e.g. #2563EB'),
  FieldSpec('secondary_color', 'Accent colour', hint: 'Hex, e.g. #0EA5A4'),
  FieldSpec('settings.require_visitor_approval', 'Walk-in visitors need resident approval', type: FieldType.boolean),
  FieldSpec('settings.allow_forum', 'Community forum', type: FieldType.boolean),
  FieldSpec('settings.allow_classifieds', 'Buy & sell marketplace', type: FieldType.boolean),
  FieldSpec('settings.kid_exit_control', 'Kid exit control at the gate', type: FieldType.boolean),
];

final platformCommunities = ResourceSpec(
  key: 'platform-communities',
  title: 'All communities',
  icon: Icons.location_city_rounded,
  path: '/platform/communities/',
  titleOf: (j) => _s(j, 'name'),
  subtitleOf: (j) => _join([j['city_name'], j['country'], j['currency']]),
  chipOf: (j) => j['is_active'] == true ? null : ('Inactive', Tone.neutral),
  sendCommunity: false,
  filterByCommunity: false,
  canDelete: false,
  createLabel: 'Add community',
  emptyMessage: 'After adding a community, add its admin under Staff & roles.',
  fields: const [
    FieldSpec('name', 'Name', required: true),
    FieldSpec('city', 'City', type: FieldType.ref, refPath: '/platform/cities/', refCommunity: false, required: true),
    FieldSpec('address', 'Address', type: FieldType.multiline),
    FieldSpec('contact_phone', 'Office phone', type: FieldType.phone),
    FieldSpec('is_active', 'Active', type: FieldType.boolean, initial: true),
  ],
);

final platformCities = ResourceSpec(
  key: 'platform-cities',
  title: 'Cities',
  icon: Icons.map_rounded,
  path: '/platform/cities/',
  titleOf: (j) => _s(j, 'name'),
  subtitleOf: (j) => _join([j['state'], j['country_name'] ?? j['country']]),
  sendCommunity: false,
  filterByCommunity: false,
  createLabel: 'Add city',
  fields: const [
    FieldSpec('country', 'Country', type: FieldType.ref, refPath: '/platform/countries/', refCommunity: false, required: true),
    FieldSpec('name', 'City', required: true),
    FieldSpec('state', 'State / region'),
    FieldSpec('is_active', 'Active', type: FieldType.boolean, initial: true),
  ],
);

final allResources = {
  for (final r in [
    memberships, towers, units, gates, staff, emergencyContacts, chargeTypes, invoices, payments, defaulters, tickets,
    ticketCategories, notices, polls, events, moveRequests, vendors, bookings, visitorLog, sos, incidents, forum,
    classifieds, platformCommunities, platformCities,
  ])
    r.key: r,
};
