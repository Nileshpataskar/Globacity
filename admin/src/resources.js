/* Every management area of the admin dashboard, driven by the Django /api/v1/manage/ API.
 * A resource describes its list columns, filters, form fields and row actions; ResourcePage renders it. */

export const F = {}; // helpers, filled below

F.s = (j, k) => (j[k] === null || j[k] === undefined ? '' : String(j[k]));
F.join = (...parts) => parts.map((p) => (p === null || p === undefined ? '' : String(p).trim())).filter(Boolean).join(' · ');
F.human = (v) => {
  const s = String(v ?? '').replace(/_/g, ' ').trim();
  return s ? s[0].toUpperCase() + s.slice(1) : '';
};
F.date = (v) => {
  if (!v) return '';
  const s = String(v);
  const d = new Date(s.length <= 10 ? s + 'T00:00:00' : s);
  if (isNaN(d)) return s;
  return s.length <= 10
    ? d.toLocaleDateString(undefined, { day: 'numeric', month: 'short', year: 'numeric' })
    : d.toLocaleString(undefined, { day: 'numeric', month: 'short', hour: 'numeric', minute: '2-digit' });
};
F.currency = 'INR';
F.money = (amount, currency) => {
  const n = Number(amount ?? 0);
  const code = currency || F.currency;
  try {
    return new Intl.NumberFormat(undefined, { style: 'currency', currency: code, maximumFractionDigits: code === 'KWD' ? 3 : 2 }).format(n);
  } catch (_) {
    return `${code} ${n.toFixed(2)}`;
  }
};
F.tone = (status) => ({
  approved: 'success', paid: 'success', success: 'success', resolved: 'success', completed: 'success', closed: 'success',
  confirmed: 'success', exited: 'success',
  pending: 'warning', unpaid: 'warning', open: 'warning', requested: 'warning', waiting: 'warning', acknowledged: 'warning',
  on_hold: 'warning', partially_paid: 'warning',
  rejected: 'danger', cancelled: 'danger', failed: 'danger', denied: 'danger', removed: 'danger', active: 'danger',
  urgent: 'danger', critical: 'danger', high: 'warning',
  in_progress: 'info', investigating: 'info', inside: 'info', expected: 'info', moved_out: '',
}[status] || '');
F.status = (key = 'status') => (j) => [F.human(j[key]), F.tone(F.s(j, key))];
F.userName = (j) => (j.user && (j.user.full_name || '').trim()) || (j.user && j.user.phone) || 'Resident';

const UNIT_TYPES = ['apartment', 'villa', 'townhouse', 'office', 'shop'];
const NOTE = [{ key: 'note', label: 'Note to resident (optional)', type: 'multiline' }];

export const R = {};

// ---------------------------------------------------------------- Residents & property
R.residents = {
  title: 'Residents', path: '/manage/memberships/', icon: '👥',
  columns: [
    { label: 'Resident', value: F.userName, sub: (j) => j.user && j.user.phone },
    { label: 'Flat', value: (j) => j.unit_label },
    { label: 'Role', value: (j) => F.human(j.role) },
    { label: 'Requested', value: (j) => F.date(j.created_at) },
    { label: 'Status', badge: F.status() },
  ],
  titleOf: F.userName,
  details: (j) => [['Flat', j.unit_label], ['Role', F.human(j.role)], ['Phone', j.user && j.user.phone],
    ['Requested', F.date(j.created_at)], ['Approved', F.date(j.approved_at)], ['Note', j.note]],
  filters: [['Pending', { status: 'pending' }], ['Approved', { status: 'approved' }], ['Moved out', { status: 'moved_out' }],
    ['Rejected', { status: 'rejected' }], ['All', {}]],
  towerFilter: 'unit__tower', sendCommunity: false, canEdit: false, createLabel: 'Add resident',
  empty: 'New sign-ups who request a flat appear here for approval.',
  fields: [
    { key: 'unit', label: 'Flat', type: 'ref', ref: '/manage/units/', refLabel: 'label', required: true },
    { key: 'role', label: 'Role', type: 'choice', choices: ['owner', 'tenant', 'family'], required: true, initial: 'owner' },
    { key: 'user_phone', label: 'Mobile number', type: 'phone', required: true, hint: 'With country code, e.g. +919812345678. They log in with this number.' },
    { key: 'full_name', label: 'Full name' },
    { key: 'note', label: 'Note' },
  ],
  actions: [
    { label: 'Approve', path: 'approve/', tone: 'success', visible: (j) => ['pending', 'rejected'].includes(j.status), success: 'Approved. The resident has been notified.' },
    { label: 'Reject', path: 'reject/', tone: 'danger', visible: (j) => j.status === 'pending', confirm: 'Reject this request?' },
    { label: 'Mark moved out', path: 'move-out/', tone: 'warning', visible: (j) => j.status === 'approved', confirm: 'Mark this resident as moved out? They lose access to the flat.' },
  ],
};

R.towers = {
  title: 'Towers', path: '/manage/towers/', icon: '🏢',
  columns: [
    { label: 'Tower', value: (j) => j.name, sub: (j) => j.code && `Code ${j.code}` },
    { label: 'Flats', value: (j) => `${j.units_count ?? 0} flats · ${j.floors} floors` },
    { label: 'Maintenance', value: (j) => (j.maintenance_amount == null ? 'Not set' : F.money(j.maintenance_amount)) },
    { label: 'Contact', value: (j) => F.join(j.contact_name, j.contact_phone) },
    { label: 'Approval', badge: (j) => (j.approval_mode === 'auto' ? ['Auto-approve', 'info'] : ['Manual approval', '']) },
  ],
  titleOf: (j) => j.name,
  details: (j) => [['Code', j.code], ['Floors', j.floors], ['Flats', j.units_count],
    ['Approval', j.approval_mode === 'auto' ? 'New residents are approved automatically' : 'Tower / community admin approves'],
    ['Maintenance', j.maintenance_amount == null ? 'Not set (uses charge type amount)' : F.money(j.maintenance_amount)],
    ['Lifts', j.lifts], ['Parking slots', j.parking_slots], ['Contact', F.join(j.contact_name, j.contact_phone)]],
  createLabel: 'Add tower', communityOnlyCreate: true,
  fields: [
    { key: 'name', label: 'Tower name', required: true, hint: 'e.g. Tower C' },
    { key: 'code', label: 'Short code', hint: 'e.g. C' },
    { key: 'floors', label: 'Floors', type: 'integer', initial: 3 },
    { key: '_flats_per_floor', label: 'Flats per floor', type: 'integer', initial: 4, createOnly: true,
      hint: 'Flats are created automatically for every floor (e.g. 3 floors × 4 = 12 flats: 101–104, 201–204, 301–304). Leave empty to add them later.' },
    { key: '_numbering', label: 'Flat numbering', type: 'choice', createOnly: true, initial: 'plain', required: true,
      choices: ['plain', 'code', 'codeplain', 'dash'],
      labels: { plain: '101, 102, 201 …', code: 'A-101, A-102 … (short code first)', codeplain: 'A101, A102 …', dash: '1-1, 1-2, 2-1 …' } },
    { key: 'approval_mode', label: 'New resident approval', type: 'choice', choices: ['manual', 'auto'], initial: 'manual',
      labels: { manual: 'Manual: tower / community admin approves', auto: 'Auto: residents get access right away' } },
    { key: 'maintenance_amount', label: 'Monthly maintenance per flat', type: 'decimal', hint: 'Used automatically by "Bill all flats" when no amount is entered.' },
    { key: 'lifts', label: 'Lifts', type: 'integer' },
    { key: 'parking_slots', label: 'Parking slots', type: 'integer' },
    { key: 'contact_name', label: 'Tower contact person' },
    { key: 'contact_phone', label: 'Contact phone', type: 'phone' },
  ],
  actions: [{ label: 'Quick add flats', custom: 'quickFlats', tone: 'primary' }],
};

R.units = {
  title: 'Flats', path: '/manage/units/', icon: '🚪',
  columns: [
    { label: 'Flat', value: (j) => j.label },
    { label: 'Type', value: (j) => F.human(j.unit_type) },
    { label: 'Floor', value: (j) => F.s(j, 'floor') },
    { label: 'Size', value: (j) => F.join(j.bedrooms != null ? `${j.bedrooms} BR` : '', j.area_sqft != null ? `${j.area_sqft} sqft` : '') },
  ],
  titleOf: (j) => j.label,
  towerFilter: 'tower', sendCommunity: false, createLabel: 'Add one flat', quickAdd: true,
  empty: 'Use "Quick add flats" to create all flats of a tower at once (floors × flats per floor).',
  fields: [
    { key: 'tower', label: 'Tower', type: 'ref', ref: '/manage/towers/', required: true },
    { key: 'number', label: 'Flat number', required: true },
    { key: 'floor', label: 'Floor', type: 'integer' },
    { key: 'unit_type', label: 'Type', type: 'choice', choices: UNIT_TYPES, initial: 'apartment' },
    { key: 'bedrooms', label: 'Bedrooms', type: 'integer' },
    { key: 'area_sqft', label: 'Area (sq ft)', type: 'integer' },
  ],
};

R.gates = {
  title: 'Gates', path: '/manage/gates/', icon: '🚧', communityOnly: true,
  columns: [
    { label: 'Gate', value: (j) => j.name },
    { label: 'Type', value: (j) => (j.iot_enabled ? 'Boom barrier connected' : 'Manual gate') },
    { label: 'Status', badge: (j) => (j.is_active ? ['Active', 'success'] : ['Inactive', '']) },
  ],
  titleOf: (j) => j.name, createLabel: 'Add gate',
  fields: [
    { key: 'name', label: 'Gate name', required: true },
    { key: 'is_active', label: 'Active', type: 'boolean', initial: true },
    { key: 'iot_enabled', label: 'Boom barrier / controller connected', type: 'boolean' },
    { key: 'iot_device_id', label: 'Device ID' },
  ],
};

// ---------------------------------------------------------------- People
R.staff = {
  title: 'Staff & roles', path: '/manage/staff/', icon: '🪪', communityOnly: true,
  columns: [
    { label: 'Name', value: (j) => j.name, sub: (j) => j.designation },
    { label: 'Role', value: (j) => F.human(j.role) },
    { label: 'Manages', value: (j) => ((j.tower_names || []).length ? j.tower_names.join(', ') : (['admin', 'manager'].includes(j.role) ? 'Whole community' : '')) },
    { label: 'Phone', value: (j) => j.phone },
    { label: 'Login', badge: (j) => (!j.is_active ? ['Inactive', ''] : j.user ? ['App access', 'success'] : ['Directory only', '']) },
  ],
  titleOf: (j) => j.name,
  details: (j) => [['Role', F.human(j.role)], ['Manages', (j.tower_names || []).length ? j.tower_names.join(', ') : 'Whole community'],
    ['Designation', j.designation], ['Phone', j.phone], ['Shift', j.shift], ['App login', j.user ? 'Yes (OTP with their phone)' : 'No']],
  filters: [['All', {}], ['Admins', { role: 'admin' }], ['Managers', { role: 'manager' }], ['Guards', { role: 'guard' }], ['Facility', { role: 'facility' }]],
  createLabel: 'Add staff',
  empty: 'Add community admins, tower admins, guards and facility staff.',
  fields: [
    { key: 'name', label: 'Name', required: true },
    { key: 'role', label: 'Role', type: 'choice', required: true, initial: 'admin', choices: ['admin', 'manager', 'guard', 'committee', 'facility', 'other'],
      labels: { admin: 'Admin', manager: 'Manager', guard: 'Security guard', committee: 'Committee member', facility: 'Facility staff', other: 'Other' } },
    { key: 'towers', label: 'Only these towers (tower admin)', type: 'refMulti', ref: '/manage/towers/',
      hint: 'Pick towers to make this person a tower admin: they see and approve only those towers. Leave empty for the whole community.' },
    { key: 'user_phone', label: 'App login phone', type: 'phone', createOnly: true,
      hint: 'With country code, e.g. +919812345678. They log in to this dashboard (admins) or the app (guards) with an OTP on this number.' },
    { key: 'phone', label: 'Contact phone', type: 'phone' },
    { key: 'designation', label: 'Designation', hint: 'e.g. Tower A secretary' },
    { key: 'shift', label: 'Shift', hint: 'e.g. Day 8am–8pm' },
    { key: 'show_in_directory', label: 'Show in resident directory', type: 'boolean', initial: true },
    { key: 'is_active', label: 'Active', type: 'boolean', initial: true },
  ],
};

R['emergency-contacts'] = {
  title: 'Emergency contacts', path: '/manage/emergency-contacts/', icon: '🚑', communityOnly: true,
  columns: [{ label: 'Name', value: (j) => j.name }, { label: 'Phone', value: (j) => j.phone }, { label: 'Order', value: (j) => F.s(j, 'order') }],
  titleOf: (j) => j.name, createLabel: 'Add contact',
  fields: [
    { key: 'name', label: 'Name', required: true, hint: 'e.g. Society office, Nearest hospital' },
    { key: 'phone', label: 'Phone', type: 'phone', required: true },
    { key: 'order', label: 'Order', type: 'integer', hint: 'Lower numbers show first' },
  ],
};

// ---------------------------------------------------------------- Finance
R['charge-types'] = {
  title: 'Charge types', path: '/manage/charge-types/', icon: '🏷️', communityOnly: true,
  columns: [
    { label: 'Name', value: (j) => j.name },
    { label: 'Default amount', value: (j) => F.money(j.default_amount) },
    { label: 'Frequency', value: (j) => F.human(j.frequency) },
    { label: 'Tax', value: (j) => (j.is_taxable ? 'Taxable' : 'No tax') },
    { label: 'Status', badge: (j) => (j.is_active ? ['Active', 'success'] : ['Inactive', '']) },
  ],
  titleOf: (j) => j.name, createLabel: 'Add charge type', empty: 'e.g. Maintenance, Water, Parking, Clubhouse.',
  fields: [
    { key: 'name', label: 'Name', required: true, hint: 'e.g. Monthly maintenance' },
    { key: 'default_amount', label: 'Default amount', type: 'decimal' },
    { key: 'frequency', label: 'Frequency', type: 'choice', choices: ['one_time', 'monthly', 'quarterly', 'yearly'], initial: 'monthly' },
    { key: 'is_taxable', label: 'Add tax (GST / VAT)', type: 'boolean', initial: true },
    { key: 'is_active', label: 'Active', type: 'boolean', initial: true },
  ],
};

R.invoices = {
  title: 'Bills', path: '/manage/invoices/', icon: '🧾',
  columns: [
    { label: 'Bill', value: (j) => j.title, sub: (j) => F.join(j.number, j.period_label) },
    { label: 'Flat', value: (j) => j.unit_label },
    { label: 'Total', value: (j) => F.money(j.total, j.currency), sub: (j) => (Number(j.paid_amount) > 0 ? `Paid ${F.money(j.paid_amount, j.currency)}` : '') },
    { label: 'Due', value: (j) => F.date(j.due_date) },
    { label: 'Status', badge: (j) => (j.is_overdue ? ['Overdue', 'danger'] : F.status()(j)) },
  ],
  titleOf: (j) => F.join(j.unit_label, j.title),
  details: (j) => [['Bill no.', j.number], ['Flat', j.unit_label], ['Period', j.period_label], ['Amount', F.money(j.amount, j.currency)],
    [`${j.tax_name || 'Tax'} (${j.tax_rate}%)`, F.money(j.tax_amount, j.currency)], ['Total', F.money(j.total, j.currency)],
    ['Paid', F.money(j.paid_amount, j.currency)], ['Balance', F.money(j.balance, j.currency)], ['Due', F.date(j.due_date)]],
  filters: [['Unpaid', { status: 'unpaid' }], ['Part paid', { status: 'partially_paid' }], ['Paid', { status: 'paid' }],
    ['Cancelled', { status: 'cancelled' }], ['All', {}]],
  towerFilter: 'unit__tower', sendCommunity: false, canEdit: false, canDelete: false, createLabel: 'Raise a bill',
  fields: [
    { key: 'unit', label: 'Flat', type: 'ref', ref: '/manage/units/', refLabel: 'label', required: true },
    { key: 'charge_type', label: 'Charge type', type: 'ref', ref: '/manage/charge-types/' },
    { key: 'title', label: 'Title', hint: 'Leave empty to use the charge type name' },
    { key: 'period_label', label: 'Period', hint: 'e.g. December 2026' },
    { key: 'amount', label: 'Amount (before tax)', type: 'decimal', hint: 'Leave empty to use the charge type amount' },
    { key: 'due_date', label: 'Due date', type: 'date', required: true },
    { key: 'taxable', label: 'Add tax', type: 'boolean', initial: true },
  ],
  actions: [
    { label: 'Record cash / cheque payment', path: 'record-payment/', tone: 'success', success: 'Payment recorded',
      visible: (j) => ['unpaid', 'partially_paid'].includes(j.status),
      fields: [
        { key: 'amount', label: 'Amount received', type: 'decimal', required: true, initialFrom: 'balance' },
        { key: 'method', label: 'Method', type: 'choice', choices: ['cash', 'cheque', 'bank_transfer'], required: true, initial: 'cash' },
        { key: 'reference', label: 'Reference', hint: 'Cheque no. or transfer ID' },
      ] },
    { label: 'Cancel bill', path: 'cancel/', tone: 'danger', visible: (j) => j.status === 'unpaid', confirm: 'Cancel this bill? The resident will no longer see it as due.' },
  ],
};

R.payments = {
  title: 'Payments', path: '/manage/payments/', icon: '💳',
  columns: [
    { label: 'Flat', value: (j) => j.unit_label, sub: (j) => j.reference },
    { label: 'Amount', value: (j) => F.money(j.amount, j.currency) },
    { label: 'Method', value: (j) => F.human(j.method) },
    { label: 'Paid at', value: (j) => F.date(j.paid_at || j.created_at) },
    { label: 'Status', badge: F.status() },
  ],
  titleOf: (j) => F.join(j.unit_label, F.money(j.amount, j.currency)),
  details: (j) => [['Reference', j.reference], ['Flat', j.unit_label], ['Amount', F.money(j.amount, j.currency)], ['Method', F.human(j.method)],
    ['Gateway', j.gateway], ['Paid at', F.date(j.paid_at)]],
  filters: [['Successful', { status: 'success' }], ['All', {}]],
  canCreate: false, canEdit: false, canDelete: false,
};

R.defaulters = {
  title: 'Defaulters', path: '/manage/defaulters/', icon: '⚠️', idKey: 'unit', searchable: false,
  columns: [
    { label: 'Flat', value: (j) => j.unit_label, sub: (j) => (j.residents || []).join(', ') },
    { label: 'Overdue', value: (j) => F.money(j.overdue_amount, j.currency) },
    { label: 'Bills', value: (j) => F.s(j, 'overdue_invoices') },
    { label: 'Oldest due', value: (j) => F.date(j.oldest_due_date) },
    { label: 'Days', badge: (j) => [`${j.days_overdue} days`, j.days_overdue > 60 ? 'danger' : 'warning'] },
  ],
  titleOf: (j) => j.unit_label,
  filters: [['All overdue', {}], ['30+ days', { min_days: '30' }], ['90+ days', { min_days: '90' }]],
  canCreate: false, canEdit: false, canDelete: false, empty: 'No overdue bills. 🎉',
  actions: [
    { label: 'Send reminder', path: '/manage/defaulters/remind/', sendCommunity: true, body: (j) => ({ units: [j.unit] }),
      success: 'Reminder sent', fields: [{ key: 'message', label: 'Message (optional)', type: 'multiline' }] },
  ],
};

// ---------------------------------------------------------------- Help desk
R.tickets = {
  title: 'Help desk', path: '/manage/tickets/', icon: '🛠️',
  columns: [
    { label: 'Ticket', value: (j) => j.title, sub: (j) => F.join(j.number, j.category_name) },
    { label: 'Flat', value: (j) => j.unit_label, sub: (j) => j.raised_by_name },
    { label: 'Priority', badge: (j) => [F.human(j.priority), F.tone(j.priority)] },
    { label: 'Assigned', value: (j) => j.assigned_to_name || '—' },
    { label: 'Status', badge: F.status() },
  ],
  titleOf: (j) => j.title,
  details: (j) => [['Ticket', j.number], ['Flat', j.unit_label], ['Raised by', j.raised_by_name], ['Category', j.category_name],
    ['Priority', F.human(j.priority)], ['Assigned to', j.assigned_to_name], ['Raised', F.date(j.created_at)], ['Details', j.description],
    ['Rating', j.rating != null ? `${j.rating}★ ${j.rating_comment || ''}` : ''],
    ['History', (j.updates || []).map((u) => `• ${F.date(u.created_at)} ${u.author_name || ''}: ${u.message || F.human(u.status_change || '')}${u.is_internal ? ' (internal)' : ''}`).join('\n')]],
  filters: [['Open', { status: 'open' }], ['In progress', { status: 'in_progress' }], ['On hold', { status: 'on_hold' }],
    ['Resolved', { status: 'resolved' }], ['Closed', { status: 'closed' }], ['All', {}]],
  canCreate: false, canEdit: false, canDelete: false, empty: 'Complaints and requests raised by residents appear here.',
  actions: [
    { label: 'Update status / assign', method: 'patch', success: 'Ticket updated', fields: [
      { key: 'status', label: 'Status', type: 'choice', choices: ['open', 'in_progress', 'on_hold', 'resolved', 'closed'] },
      { key: 'priority', label: 'Priority', type: 'choice', choices: ['low', 'medium', 'high', 'urgent'] },
      { key: 'assigned_to', label: 'Assign to staff', type: 'ref', ref: '/manage/staff/' },
    ] },
    { label: 'Reply / add note', path: 'comment/', success: 'Comment added', fields: [
      { key: 'message', label: 'Message', type: 'multiline', required: true },
      { key: 'is_internal', label: 'Internal note (hidden from resident)', type: 'boolean' },
    ] },
  ],
};

R['ticket-categories'] = {
  title: 'Help desk categories', path: '/manage/ticket-categories/', icon: '🔖', communityOnly: true,
  columns: [{ label: 'Name', value: (j) => j.name }, { label: 'Target', value: (j) => (j.sla_hours ? `${j.sla_hours} h` : '') },
    { label: 'Status', badge: (j) => (j.is_active ? ['Active', 'success'] : ['Inactive', '']) }],
  titleOf: (j) => j.name, createLabel: 'Add category',
  fields: [
    { key: 'name', label: 'Name', required: true },
    { key: 'icon', label: 'Icon name', hint: 'Material icon, e.g. plumbing' },
    { key: 'sla_hours', label: 'Target resolution (hours)', type: 'integer' },
    { key: 'is_active', label: 'Active', type: 'boolean', initial: true },
  ],
};

// ---------------------------------------------------------------- Communication
R.notices = {
  title: 'Notices', path: '/manage/notices/', icon: '📢',
  columns: [
    { label: 'Notice', value: (j) => j.title, sub: (j) => (j.body || '').slice(0, 90) },
    { label: 'Category', value: (j) => F.human(j.category) },
    { label: 'Published', value: (j) => F.date(j.published_at || j.created_at) },
    { label: '', badge: (j) => (j.is_pinned ? ['Pinned', 'primary'] : null) },
  ],
  titleOf: (j) => j.title,
  details: (j) => [['Message', j.body], ['Category', j.category], ['Expires', F.date(j.expires_at)], ['Signed as', j.author_label]],
  createLabel: 'Post notice',
  fields: [
    { key: 'title', label: 'Title', required: true },
    { key: 'body', label: 'Message', type: 'multiline', required: true },
    { key: 'category', label: 'Category', type: 'choice', initial: 'General', choices: ['General', 'Maintenance', 'Event', 'Security', 'Finance', 'Emergency'] },
    { key: 'target_towers', label: 'Only for towers', type: 'refMulti', ref: '/manage/towers/', hint: 'None selected = whole community. Tower admins must pick their tower.' },
    { key: 'is_pinned', label: 'Pin to top', type: 'boolean' },
    { key: 'author_label', label: 'Signed as', hint: 'e.g. Management Committee' },
    { key: 'expires_at', label: 'Expires on', type: 'datetime' },
    { key: 'notify', label: 'Send push notification to residents', type: 'boolean', initial: true, createOnly: true },
  ],
};

R.polls = {
  title: 'Polls', path: '/manage/polls/', icon: '🗳️', communityOnly: true,
  columns: [
    { label: 'Question', value: (j) => j.question },
    { label: 'Votes', value: (j) => F.s(j, 'total_votes') },
    { label: 'Closes', value: (j) => F.date(j.closes_at) },
    { label: 'Status', badge: (j) => (j.is_closed ? ['Closed', ''] : ['Open', 'success']) },
  ],
  titleOf: (j) => j.question,
  details: (j) => [['Description', j.description],
    ['Results', (j.options || []).map((o) => `${o.label}: ${o.votes} (${Math.round(o.percent || 0)}%)`).join('\n')],
    ['Voting', j.one_vote_per_unit ? 'One vote per flat' : 'One vote per person']],
  canEdit: false, createLabel: 'Create poll',
  fields: [
    { key: 'question', label: 'Question', required: true },
    { key: 'description', label: 'Description', type: 'multiline' },
    { key: 'option_labels', label: 'Options (one per line)', type: 'lines', required: true, hint: 'At least two' },
    { key: 'closes_at', label: 'Closes on', type: 'datetime', required: true },
    { key: 'one_vote_per_unit', label: 'One vote per flat', type: 'boolean', initial: true },
  ],
};

R.events = {
  title: 'Events', path: '/manage/events/', icon: '🎉', communityOnly: true,
  columns: [
    { label: 'Event', value: (j) => j.title, sub: (j) => j.category },
    { label: 'When', value: (j) => F.date(j.starts_at) },
    { label: 'Venue', value: (j) => j.venue },
    { label: 'Going', value: (j) => `${j.attendees ?? 0}${j.capacity ? ' / ' + j.capacity : ''}` },
  ],
  titleOf: (j) => j.title,
  details: (j) => [['When', F.join(F.date(j.starts_at), F.date(j.ends_at))], ['Venue', j.venue], ['Going', j.attendees], ['Capacity', j.capacity], ['Details', j.description]],
  createLabel: 'Create event',
  fields: [
    { key: 'title', label: 'Title', required: true },
    { key: 'venue', label: 'Venue', required: true },
    { key: 'starts_at', label: 'Starts', type: 'datetime', required: true },
    { key: 'ends_at', label: 'Ends', type: 'datetime' },
    { key: 'category', label: 'Category', hint: 'e.g. Festival, Sports, Meeting' },
    { key: 'capacity', label: 'Capacity', type: 'integer' },
    { key: 'description', label: 'Details', type: 'multiline' },
  ],
};

// ---------------------------------------------------------------- Requests & services
R['move-requests'] = {
  title: 'Move in / out', path: '/manage/move-requests/', icon: '🚚',
  columns: [
    { label: 'Request', value: (j) => F.human(j.move_type), sub: (j) => j.moving_company },
    { label: 'Flat', value: (j) => j.unit_label },
    { label: 'Date', value: (j) => F.date(j.move_date) },
    { label: 'Status', badge: F.status() },
  ],
  titleOf: (j) => F.join(F.human(j.move_type), j.unit_label),
  details: (j) => [['Flat', j.unit_label], ['Date', F.date(j.move_date)], ['Movers', j.moving_company], ['Service lift', j.service_lift ? 'Needed' : 'No'],
    ['Notes', j.notes], ['Review note', j.review_note], ['Documents', (j.documents || []).length]],
  filters: [['Pending', { status: 'pending' }], ['Approved', { status: 'approved' }], ['Completed', { status: 'completed' }], ['All', {}]],
  canCreate: false, canEdit: false, canDelete: false,
  actions: [
    { label: 'Approve', path: 'approve/', tone: 'success', fields: NOTE, visible: (j) => j.status === 'pending' },
    { label: 'Reject', path: 'reject/', tone: 'danger', fields: NOTE, visible: (j) => j.status === 'pending' },
    { label: 'Mark completed', path: 'complete/', fields: NOTE, visible: (j) => j.status === 'approved' },
  ],
};

R.vendors = {
  title: 'Service vendors', path: '/manage/vendors/', icon: '🧰', communityOnly: true,
  columns: [
    { label: 'Vendor', value: (j) => j.name, sub: (j) => j.description },
    { label: 'Category', value: (j) => j.category },
    { label: 'Phone', value: (j) => j.phone },
    { label: 'From', value: (j) => (j.price_from != null ? F.money(j.price_from, j.currency) : '') },
    { label: '', badge: (j) => (j.is_active ? null : ['Hidden', '']) },
  ],
  titleOf: (j) => j.name, createLabel: 'Add vendor',
  fields: [
    { key: 'name', label: 'Name', required: true },
    { key: 'category', label: 'Category', required: true, hint: 'e.g. Plumber, Electrician, Cleaning' },
    { key: 'phone', label: 'Phone', type: 'phone' },
    { key: 'price_from', label: 'Starting price', type: 'decimal' },
    { key: 'eta_text', label: 'Arrival time', hint: 'e.g. Within 2 hours' },
    { key: 'description', label: 'Description', type: 'multiline' },
    { key: 'is_active', label: 'Visible to residents', type: 'boolean', initial: true },
  ],
};

R.bookings = {
  title: 'Service bookings', path: '/manage/bookings/', icon: '📅', communityOnly: true,
  columns: [{ label: 'Vendor', value: (j) => j.vendor_name }, { label: 'Flat', value: (j) => j.unit_label },
    { label: 'Slot', value: (j) => F.date(j.slot_start) }, { label: 'Status', badge: F.status() }],
  titleOf: (j) => F.join(j.vendor_name, j.unit_label),
  canCreate: false, canEdit: false, canDelete: false,
};

// ---------------------------------------------------------------- Security
R['visitor-log'] = {
  title: 'Visitor log', path: '/manage/visitor-log/', icon: '🧍',
  columns: [
    { label: 'Visitor', value: (j) => j.name, sub: (j) => F.join(F.human(j.visitor_type), j.company) },
    { label: 'Flat', value: (j) => j.unit_label },
    { label: 'In', value: (j) => F.date(j.checked_in_at || j.expected_at || j.created_at) },
    { label: 'Out', value: (j) => F.date(j.checked_out_at) },
    { label: 'Status', badge: (j) => [j.status_label || F.human(j.status), F.tone(j.status)] },
  ],
  titleOf: (j) => j.name,
  details: (j) => [['Phone', j.phone], ['Type', F.human(j.visitor_type)], ['Company', j.company], ['Vehicle', j.vehicle_no], ['Flat', j.unit_label],
    ['Gate', j.gate_name], ['In', F.date(j.checked_in_at)], ['Out', F.date(j.checked_out_at)], ['Walk-in', j.is_walk_in ? 'Yes' : 'No (pre-approved)']],
  filters: [['All', {}], ['Inside now', { status: 'inside' }], ['Waiting', { status: 'waiting' }], ['Expected', { status: 'expected' }],
    ['Exited', { status: 'exited' }], ['Denied', { status: 'denied' }]],
  towerFilter: 'unit__tower', canCreate: false, canEdit: false, canDelete: false,
};

R.sos = {
  title: 'SOS alerts', path: '/manage/sos/', icon: '🆘', searchable: false,
  columns: [
    { label: 'Alert', value: (j) => F.human(j.alert_type), sub: (j) => j.message },
    { label: 'Flat', value: (j) => j.unit_label, sub: (j) => F.join(j.raised_by_name, j.raised_by_phone) },
    { label: 'Raised', value: (j) => F.date(j.created_at) },
    { label: 'Status', badge: F.status() },
  ],
  titleOf: (j) => F.join(F.human(j.alert_type), j.unit_label),
  details: (j) => [['Message', j.message], ['Raised by', F.join(j.raised_by_name, j.raised_by_phone)], ['Acknowledged', F.date(j.acknowledged_at)], ['Resolved', F.date(j.resolved_at)]],
  filters: [['Active', { status: 'active' }], ['Acknowledged', { status: 'acknowledged' }], ['All', {}]],
  canCreate: false, canEdit: false, canDelete: false,
  actions: [
    { label: 'Acknowledge', path: '/guard/sos/{id}/acknowledge/', visible: (j) => j.status === 'active' },
    { label: 'Mark resolved', path: '/guard/sos/{id}/resolve/', tone: 'success', visible: (j) => ['active', 'acknowledged'].includes(j.status) },
  ],
};

R.incidents = {
  title: 'Incidents', path: '/manage/incidents/', icon: '🚨',
  columns: [
    { label: 'Incident', value: (j) => j.title, sub: (j) => F.join(j.category, j.location) },
    { label: 'Reported', value: (j) => F.date(j.created_at), sub: (j) => j.reported_by_name },
    { label: 'Severity', badge: (j) => [F.human(j.severity), F.tone(j.severity)] },
    { label: 'Status', badge: F.status() },
  ],
  titleOf: (j) => j.title,
  details: (j) => [['Status', F.human(j.status)], ['Severity', F.human(j.severity)], ['Location', j.location], ['Flat', j.unit_label],
    ['Reported by', j.reported_by_name], ['Details', j.description], ['Resolution', j.resolution]],
  filters: [['Open', { status: 'open' }], ['Investigating', { status: 'investigating' }], ['Resolved', { status: 'resolved' }], ['All', {}]],
  canCreate: false, canEdit: false, canDelete: false,
  actions: [
    { label: 'Update', path: '/guard/incidents/{id}/', method: 'patch', success: 'Incident updated', fields: [
      { key: 'status', label: 'Status', type: 'choice', choices: ['open', 'investigating', 'resolved'] },
      { key: 'resolution', label: 'Resolution / notes', type: 'multiline' },
    ] },
  ],
};

// ---------------------------------------------------------------- Moderation
R.forum = {
  title: 'Forum posts', path: '/manage/forum/', icon: '💬', communityOnly: true,
  columns: [
    { label: 'Post', value: (j) => j.title, sub: (j) => (j.body || '').slice(0, 90) },
    { label: 'By', value: (j) => j.author_name, sub: (j) => j.unit_label },
    { label: 'Replies', value: (j) => F.s(j, 'replies_count') },
    { label: '', badge: (j) => (j.is_locked ? ['Locked', ''] : null) },
  ],
  titleOf: (j) => j.title, details: (j) => [['Post', j.body]],
  canCreate: false, canEdit: false,
  actions: [{ label: 'Lock / unlock replies', path: 'lock/', tone: 'warning' }],
};

R.classifieds = {
  title: 'Classifieds', path: '/manage/classifieds/', icon: '🏷', communityOnly: true,
  columns: [
    { label: 'Listing', value: (j) => j.title, sub: (j) => j.category },
    { label: 'Price', value: (j) => F.money(j.price, j.currency) },
    { label: 'Seller', value: (j) => j.seller_name, sub: (j) => j.unit_label },
    { label: 'Status', badge: F.status() },
  ],
  titleOf: (j) => j.title, details: (j) => [['Description', j.description]],
  filters: [['Active', { status: 'active' }], ['All', {}]],
  canCreate: false, canEdit: false, canDelete: false,
  actions: [{ label: 'Remove listing', path: 'remove/', tone: 'danger', visible: (j) => j.status === 'active', confirm: 'Remove this listing from the marketplace?' }],
};

// ---------------------------------------------------------------- Platform
R['platform-communities'] = {
  title: 'All communities', path: '/platform/communities/', icon: '🏙️', platformOnly: true,
  columns: [
    { label: 'Community', value: (j) => j.name, sub: (j) => j.address },
    { label: 'City', value: (j) => F.join(j.city_name, j.country) },
    { label: 'Currency', value: (j) => j.currency },
    { label: 'Status', badge: (j) => (j.is_active ? ['Active', 'success'] : ['Inactive', '']) },
  ],
  titleOf: (j) => j.name, sendCommunity: false, filterByCommunity: false, canDelete: false, createLabel: 'Add community',
  empty: 'After adding a community, add its admin under Staff & roles.',
  fields: [
    { key: 'name', label: 'Name', required: true },
    { key: 'city', label: 'City', type: 'ref', ref: '/platform/cities/', refCommunity: false, required: true },
    { key: 'address', label: 'Address', type: 'multiline' },
    { key: 'contact_phone', label: 'Office phone', type: 'phone' },
    { key: 'is_active', label: 'Active', type: 'boolean', initial: true },
  ],
};

R['platform-cities'] = {
  title: 'Cities', path: '/platform/cities/', icon: '🗺️', platformOnly: true,
  columns: [{ label: 'City', value: (j) => j.name }, { label: 'State', value: (j) => j.state }, { label: 'Country', value: (j) => j.country_name }],
  titleOf: (j) => j.name, sendCommunity: false, filterByCommunity: false, createLabel: 'Add city',
  fields: [
    { key: 'country', label: 'Country', type: 'ref', ref: '/platform/countries/', refCommunity: false, required: true },
    { key: 'name', label: 'City', required: true },
    { key: 'state', label: 'State / region' },
    { key: 'is_active', label: 'Active', type: 'boolean', initial: true },
  ],
};

export const BULK_BILL_FIELDS = [
  { key: 'charge_type', label: 'Charge type', type: 'ref', ref: '/manage/charge-types/' },
  { key: 'title', label: 'Title', hint: 'Leave empty to use the charge type name, or "Maintenance"' },
  { key: 'amount', label: 'Amount per flat (before tax)', type: 'decimal',
    hint: "Leave empty to use each tower's own maintenance amount (set in Towers), else the charge type amount" },
  { key: 'period_label', label: 'Period', hint: 'e.g. December 2026' },
  { key: 'due_date', label: 'Due date', type: 'date', required: true },
  { key: 'tower', label: 'Only this tower', type: 'ref', ref: '/manage/towers/' },
  { key: 'taxable', label: 'Add tax (GST / VAT)', type: 'boolean', initial: true },
  { key: 'only_occupied', label: 'Only flats with an approved resident', type: 'boolean', initial: true },
];

export const COMMUNITY_SETTINGS_FIELDS = [
  { key: 'name', label: 'Community name', required: true },
  { key: 'address', label: 'Address', type: 'multiline' },
  { key: 'contact_phone', label: 'Office phone', type: 'phone' },
  { key: 'contact_email', label: 'Office email' },
  { key: 'primary_color', label: 'Brand colour', hint: 'Hex, e.g. #2563EB (used in the resident app)' },
  { key: 'secondary_color', label: 'Accent colour', hint: 'Hex, e.g. #0EA5A4' },
  { key: 'settings.require_visitor_approval', label: 'Walk-in visitors need resident approval', type: 'boolean' },
  { key: 'settings.allow_forum', label: 'Community forum', type: 'boolean' },
  { key: 'settings.allow_classifieds', label: 'Buy & sell marketplace', type: 'boolean' },
  { key: 'settings.kid_exit_control', label: 'Kid exit control at the gate', type: 'boolean' },
];

/* Sidebar: [group, [[route, label, resourceKey?]]] */
export const NAV = [
  ['', [['overview', 'Overview']]],
  ['Residents', [['r/residents', 'Approvals & residents', 'residents']]],
  ['Property', [['r/towers', 'Towers', 'towers'], ['r/units', 'Flats', 'units'], ['r/gates', 'Gates', 'gates'], ['settings', 'Community settings']]],
  ['Finance', [['bulk-bill', 'Bill all flats'], ['r/invoices', 'Bills', 'invoices'], ['r/payments', 'Payments', 'payments'],
    ['r/defaulters', 'Defaulters', 'defaulters'], ['r/charge-types', 'Charge types', 'charge-types']]],
  ['Help desk', [['r/tickets', 'Tickets', 'tickets'], ['r/ticket-categories', 'Categories', 'ticket-categories']]],
  ['Communication', [['r/notices', 'Notices', 'notices'], ['r/polls', 'Polls', 'polls'], ['r/events', 'Events', 'events']]],
  ['Requests', [['r/move-requests', 'Move in / out', 'move-requests'], ['r/vendors', 'Vendors', 'vendors'], ['r/bookings', 'Bookings', 'bookings']]],
  ['Security', [['r/visitor-log', 'Visitor log', 'visitor-log'], ['r/sos', 'SOS alerts', 'sos'], ['r/incidents', 'Incidents', 'incidents']]],
  ['Moderation', [['r/forum', 'Forum', 'forum'], ['r/classifieds', 'Classifieds', 'classifieds']]],
  ['People', [['r/staff', 'Staff & roles', 'staff'], ['r/emergency-contacts', 'Emergency contacts', 'emergency-contacts']]],
  ['Platform', [['r/platform-communities', 'All communities', 'platform-communities'], ['r/platform-cities', 'Cities', 'platform-cities']]],
];

for (const [key, r] of Object.entries(R)) r.key = key;
