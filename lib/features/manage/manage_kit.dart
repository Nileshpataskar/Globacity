import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:intl/intl.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/manage.dart';
import '../../data/models.dart';

/// Generic list / form / action screens driven by a [ResourceSpec]. Every management
/// area (towers, staff, notices, invoices...) is described as a spec in resources.dart.

// ---------------------------------------------------------------------------
// Specs
// ---------------------------------------------------------------------------

enum FieldType { text, multiline, integer, decimal, boolean, choice, date, dateTime, ref, refMulti, lines, phone }

class FieldSpec {
  const FieldSpec(
    this.key,
    this.label, {
    this.type = FieldType.text,
    this.required = false,
    this.choices = const [],
    this.refPath,
    this.refLabel = 'name',
    this.refCommunity = true,
    this.hint,
    this.createOnly = false,
    this.initial,
  });

  /// API field name. A dot (`settings.allow_forum`) writes into a nested object.
  final String key;
  final String label;
  final FieldType type;
  final bool required;
  final List<String> choices;

  /// For [FieldType.ref] / [FieldType.refMulti]: list endpoint and the label field.
  final String? refPath;
  final String refLabel;
  final bool refCommunity;
  final String? hint;

  /// Only shown when creating (e.g. the login phone of a new staff member).
  final bool createOnly;
  final Object? initial;
}

class RowAction {
  const RowAction(
    this.label, {
    required this.icon,
    this.path,
    this.method = 'post',
    this.fields = const [],
    this.visible,
    this.confirm,
    this.tone = Tone.primary,
    this.body,
    this.success,
    this.sendCommunity = false,
  });

  final String label;
  final IconData icon;

  /// Suffix after the item URL (`approve/`), or an absolute path with `{id}` (`/guard/sos/{id}/resolve/`).
  /// Null means the item URL itself (used with `patch`).
  final String? path;
  final String method;

  /// Inputs asked for before running (e.g. a review note). Pre-filled from the item.
  final List<FieldSpec> fields;
  final bool Function(Json item)? visible;

  /// Confirmation question; null runs straight away (or after the field sheet).
  final String? confirm;
  final Tone tone;

  /// Extra body values built from the item.
  final Json Function(Json item)? body;
  final String? success;

  /// Adds the selected community id to the body.
  final bool sendCommunity;
}

class FilterSpec {
  const FilterSpec(this.label, this.query);

  final String label;
  final Map<String, String> query;
}

class ResourceSpec {
  const ResourceSpec({
    required this.key,
    required this.title,
    required this.icon,
    required this.path,
    required this.titleOf,
    this.subtitleOf,
    this.chipOf,
    this.detailsOf,
    this.fields = const [],
    this.canCreate = true,
    this.canEdit = true,
    this.canDelete = true,
    this.sendCommunity = true,
    this.filterByCommunity = true,
    this.filters = const [],
    this.towerFilter,
    this.actions = const [],
    this.idKey = 'id',
    this.createLabel,
    this.emptyMessage,
    this.searchable = true,
  });

  final String key;
  final String title;
  final IconData icon;
  final String path;
  final String Function(Json) titleOf;
  final String Function(Json)? subtitleOf;
  final (String, Tone)? Function(Json)? chipOf;

  /// Label/value rows shown on the detail sheet.
  final List<(String, String)> Function(Json)? detailsOf;
  final List<FieldSpec> fields;
  final bool canCreate;
  final bool canEdit;
  final bool canDelete;

  /// Adds `community` to the body on create.
  final bool sendCommunity;

  /// Adds `?community=` to list requests.
  final bool filterByCommunity;
  final List<FilterSpec> filters;

  /// Query param to filter by tower (e.g. `unit__tower`), shown as chips.
  final String? towerFilter;
  final List<RowAction> actions;
  final String idKey;
  final String? createLabel;
  final String? emptyMessage;
  final bool searchable;

  bool get hasForm => fields.isNotEmpty;
}

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

/// Keeps content at a readable width on laptops / desktops (web dashboard).
class ManageWidth extends StatelessWidget {
  const ManageWidth({super.key, required this.child, this.maxWidth = 1000});

  final Widget child;
  final double maxWidth;

  @override
  Widget build(BuildContext context) => Align(
        alignment: Alignment.topCenter,
        child: ConstrainedBox(constraints: BoxConstraints(maxWidth: maxWidth), child: child),
      );
}

String humanize(Object? v) {
  final s = '${v ?? ''}'.replaceAll('_', ' ').trim();
  return s.isEmpty ? '' : '${s[0].toUpperCase()}${s.substring(1)}';
}

String fmtDate(Object? v) {
  if (v == null || '$v'.isEmpty) return '';
  final d = DateTime.tryParse('$v');
  if (d == null) return '$v';
  return '$v'.length <= 10 ? Fmt.date(d) : Fmt.dateTime(d.toLocal());
}

String fmtMoney(Object? amount, [Object? currency]) {
  final n = num.tryParse('${amount ?? 0}') ?? 0;
  return Fmt.money(n, currency?.toString());
}

Tone toneFor(String status) => switch (status) {
      'approved' || 'paid' || 'success' || 'resolved' || 'completed' || 'closed' || 'confirmed' || 'active_ok' =>
        Tone.success,
      'pending' || 'unpaid' || 'open' || 'requested' || 'waiting' || 'acknowledged' || 'on_hold' || 'partially_paid' =>
        Tone.warning,
      'rejected' || 'cancelled' || 'failed' || 'denied' || 'removed' || 'active' || 'urgent' || 'critical' =>
        Tone.danger,
      'in_progress' || 'investigating' || 'inside' || 'expected' => Tone.info,
      _ => Tone.neutral,
    };

dynamic _read(Json item, String key) {
  dynamic v = item;
  for (final part in key.split('.')) {
    if (v is! Map) return null;
    v = v[part];
  }
  return v;
}

void _write(Json body, String key, dynamic value) {
  final parts = key.split('.');
  var m = body;
  for (final p in parts.take(parts.length - 1)) {
    m = (m[p] ??= <String, dynamic>{}) as Json;
  }
  m[parts.last] = value;
}

String _resolvePath(String base, Json item, String idKey, String? suffix) {
  final id = '${item[idKey]}';
  if (suffix != null && suffix.startsWith('/')) return suffix.replaceAll('{id}', id);
  return '$base$id/${suffix ?? ''}';
}

Future<bool> confirmDialog(BuildContext context, String message, {String action = 'Confirm', bool danger = false}) async {
  final ok = await showDialog<bool>(
    context: context,
    builder: (ctx) => AlertDialog(
      content: Text(message),
      actions: [
        TextButton(onPressed: () => Navigator.pop(ctx, false), child: const Text('Cancel')),
        FilledButton(
          style: danger ? FilledButton.styleFrom(backgroundColor: ctx.palette.danger) : null,
          onPressed: () => Navigator.pop(ctx, true),
          child: Text(action),
        ),
      ],
    ),
  );
  return ok == true;
}

// ---------------------------------------------------------------------------
// List screen
// ---------------------------------------------------------------------------

class ResourceListScreen extends ConsumerStatefulWidget {
  const ResourceListScreen({super.key, required this.spec, this.initialFilter = 0, this.initialTower, this.embedded = false,
      this.header});

  final ResourceSpec spec;
  final int initialFilter;

  /// Pre-selected tower id (for specs with a tower filter).
  final String? initialTower;

  /// Shown as a bottom-nav tab: no back button.
  final bool embedded;

  /// Optional widget above the list (e.g. a summary card).
  final Widget? header;

  @override
  ConsumerState<ResourceListScreen> createState() => _ResourceListScreenState();
}

class _ResourceListScreenState extends ConsumerState<ResourceListScreen> {
  late int _filter = widget.initialFilter;
  late String? _tower = widget.initialTower;
  String _search = '';
  Timer? _debounce;
  late Future<List<Json>> _items = _load();
  Future<List<Json>>? _towers;

  ResourceSpec get spec => widget.spec;

  @override
  void initState() {
    super.initState();
    if (spec.towerFilter != null) _towers = ref.read(manageApiProvider).listAll('/manage/towers/');
  }

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  Future<List<Json>> _load() => ref.read(manageApiProvider).listAll(spec.path, community: spec.filterByCommunity, query: {
        if (spec.filters.isNotEmpty) ...spec.filters[_filter].query,
        if (_tower != null && spec.towerFilter != null) spec.towerFilter!: _tower,
        if (_search.isNotEmpty) 'search': _search,
      });

  Future<void> _reload() async {
    final f = _load();
    setState(() => _items = f);
    ref.invalidate(manageSummaryProvider);
    await f.catchError((_) => <Json>[]);
  }

  Future<void> _openForm([Json? item]) async {
    final saved = await Navigator.of(context).push<bool>(MaterialPageRoute(
      builder: (_) => ResourceFormScreen(spec: spec, item: item),
    ));
    if (saved == true) _reload();
  }

  @override
  Widget build(BuildContext context) {
    ref.listen(manageCommunityProvider, (prev, next) {
      if (prev?['id'] != next?['id']) _reload();
    });
    return Scaffold(
      appBar: AppBar(
        automaticallyImplyLeading: !widget.embedded,
        title: Text(spec.title),
        actions: [IconButton(onPressed: _reload, icon: const Icon(Icons.refresh_rounded), tooltip: 'Refresh')],
      ),
      floatingActionButton: spec.canCreate && spec.hasForm
          ? FloatingActionButton.extended(
              onPressed: () => _openForm(),
              icon: const Icon(Icons.add_rounded),
              label: Text(spec.createLabel ?? 'Add'),
            )
          : null,
      body: ManageWidth(child: RefreshIndicator(
        onRefresh: _reload,
        child: ListView(
          padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, 96),
          children: [
            ?widget.header,
            if (spec.searchable) ...[
              TextField(
                onChanged: (q) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 350), () {
                    _search = q.trim();
                    _reload();
                  });
                },
                decoration: const InputDecoration(hintText: 'Search', prefixIcon: Icon(Icons.search_rounded), isDense: true),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
            if (spec.filters.length > 1)
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                child: Row(children: [
                  for (var i = 0; i < spec.filters.length; i++)
                    Padding(
                      padding: const EdgeInsets.only(right: AppSpacing.sm),
                      child: ChoiceChip(
                        label: Text(spec.filters[i].label),
                        selected: _filter == i,
                        onSelected: (_) {
                          _filter = i;
                          _reload();
                        },
                      ),
                    ),
                ]),
              ),
            if (_towers != null)
              FutureBuilder<List<Json>>(
                future: _towers,
                builder: (context, snap) {
                  final towers = snap.data ?? [];
                  if (towers.length < 2 && _tower == null) return const SizedBox.shrink();
                  return SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final t in [null, ...towers])
                        Padding(
                          padding: const EdgeInsets.only(right: AppSpacing.sm),
                          child: FilterChip(
                            label: Text(t == null ? 'All towers' : '${t['name']}'),
                            selected: _tower == t?['id'],
                            onSelected: (_) {
                              _tower = t?['id'] as String?;
                              _reload();
                            },
                          ),
                        ),
                    ]),
                  );
                },
              ),
            const SizedBox(height: AppSpacing.sm),
            FutureBuilder<List<Json>>(
              future: _items,
              builder: (context, snap) {
                if (snap.connectionState != ConnectionState.done) {
                  return const Padding(padding: EdgeInsets.all(48), child: Center(child: CircularProgressIndicator()));
                }
                if (snap.hasError) {
                  return EmptyState(icon: Icons.cloud_off_rounded, title: "Couldn't load", message: '${snap.error}',
                      action: 'Retry', onAction: _reload);
                }
                final items = snap.data!;
                if (items.isEmpty) {
                  return EmptyState(icon: spec.icon, title: 'Nothing here yet', message: spec.emptyMessage);
                }
                return Column(children: [
                  Align(
                    alignment: Alignment.centerLeft,
                    child: Padding(
                      padding: const EdgeInsets.only(bottom: AppSpacing.sm, left: AppSpacing.xs),
                      child: Text('${items.length} ${items.length == 1 ? 'item' : 'items'}', style: context.text.labelSmall),
                    ),
                  ),
                  for (final item in items) ...[
                    _ItemCard(spec: spec, item: item, onTap: () => _openDetail(item)),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ]);
              },
            ),
          ],
        ),
      )),
    );
  }

  Future<void> _openDetail(Json item) async {
    final changed = await showAppSheet<bool>(context, title: spec.titleOf(item), child: _DetailSheet(spec: spec, item: item, onEdit: () {
      Navigator.pop(context);
      _openForm(item);
    }));
    if (changed == true) _reload();
  }
}

class _ItemCard extends StatelessWidget {
  const _ItemCard({required this.spec, required this.item, required this.onTap});

  final ResourceSpec spec;
  final Json item;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final chip = spec.chipOf?.call(item);
    final subtitle = spec.subtitleOf?.call(item) ?? '';
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.md),
      child: Row(
        children: [
          IconBadge(icon: spec.icon, size: 38),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(spec.titleOf(item), style: context.text.titleSmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                if (subtitle.isNotEmpty) ...[
                  const SizedBox(height: 2),
                  Text(subtitle, style: context.text.bodySmall, maxLines: 2, overflow: TextOverflow.ellipsis),
                ],
              ],
            ),
          ),
          if (chip != null) ...[const SizedBox(width: AppSpacing.sm), StatusChip(label: chip.$1, tone: chip.$2)],
        ],
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Detail sheet with actions
// ---------------------------------------------------------------------------

class _DetailSheet extends ConsumerStatefulWidget {
  const _DetailSheet({required this.spec, required this.item, required this.onEdit});

  final ResourceSpec spec;
  final Json item;
  final VoidCallback onEdit;

  @override
  ConsumerState<_DetailSheet> createState() => _DetailSheetState();
}

class _DetailSheetState extends ConsumerState<_DetailSheet> {
  bool _busy = false;

  ResourceSpec get spec => widget.spec;
  Json get item => widget.item;

  Future<void> _run(RowAction a) async {
    Json body = {...?a.body?.call(item)};
    if (a.fields.isNotEmpty) {
      final values = await Navigator.of(context).push<Json>(MaterialPageRoute(
        builder: (_) => ValuesFormScreen(title: a.label, fields: a.fields, initial: item, submitLabel: a.label),
      ));
      if (values == null) return;
      body.addAll(values);
    } else if (a.confirm != null) {
      if (!mounted || !await confirmDialog(context, a.confirm!, action: a.label, danger: a.tone == Tone.danger)) return;
    }
    if (!mounted) return;
    setState(() => _busy = true);
    final api = ref.read(manageApiProvider);
    if (a.sendCommunity && api.communityId != null) body['community'] = api.communityId;
    final url = _resolvePath(spec.path, item, spec.idKey, a.path);
    final ok = await runAction(context, () async {
      a.method == 'patch' ? await api.patch(url, body) : await api.post(url, body);
      return true;
    }, success: a.success ?? '${a.label}: done');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) Navigator.pop(context, true);
  }

  Future<void> _delete() async {
    if (!await confirmDialog(context, 'Delete "${spec.titleOf(item)}"? This cannot be undone.', action: 'Delete', danger: true)) {
      return;
    }
    if (!mounted) return;
    final ok = await runAction(context, () async {
      await ref.read(manageApiProvider).delete(_resolvePath(spec.path, item, spec.idKey, null));
      return true;
    }, success: 'Deleted');
    if (ok == true && mounted) Navigator.pop(context, true);
  }

  @override
  Widget build(BuildContext context) {
    final details = spec.detailsOf?.call(item) ?? [];
    final actions = spec.actions.where((a) => a.visible?.call(item) ?? true).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (spec.subtitleOf != null) ...[
          Text(spec.subtitleOf!(item), style: context.text.bodyMedium?.copyWith(color: context.palette.textMuted)),
          const SizedBox(height: AppSpacing.md),
        ],
        for (final (label, value) in details)
          if (value.trim().isNotEmpty)
            Padding(
              padding: const EdgeInsets.only(bottom: AppSpacing.sm),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  SizedBox(width: 120, child: Text(label, style: context.text.bodySmall)),
                  Expanded(child: SelectableText(value, style: context.text.bodyMedium)),
                ],
              ),
            ),
        if (_busy) const Padding(padding: EdgeInsets.all(AppSpacing.md), child: Center(child: CircularProgressIndicator())),
        const SizedBox(height: AppSpacing.md),
        for (final a in actions)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: FilledButton.tonalIcon(
              style: FilledButton.styleFrom(foregroundColor: a.tone.resolve(context)),
              onPressed: _busy ? null : () => _run(a),
              icon: Icon(a.icon),
              label: Text(a.label),
            ),
          ),
        if (spec.canEdit && spec.hasForm)
          Padding(
            padding: const EdgeInsets.only(bottom: AppSpacing.sm),
            child: OutlinedButton.icon(onPressed: _busy ? null : widget.onEdit, icon: const Icon(Icons.edit_outlined), label: const Text('Edit')),
          ),
        if (spec.canDelete)
          TextButton.icon(
            style: TextButton.styleFrom(foregroundColor: context.palette.danger),
            onPressed: _busy ? null : _delete,
            icon: const Icon(Icons.delete_outline_rounded),
            label: const Text('Delete'),
          ),
      ],
    );
  }
}

// ---------------------------------------------------------------------------
// Forms
// ---------------------------------------------------------------------------

/// Create / edit form for a resource. Pops `true` when saved.
class ResourceFormScreen extends ConsumerWidget {
  const ResourceFormScreen({super.key, required this.spec, this.item});

  final ResourceSpec spec;
  final Json? item;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final editing = item != null;
    return ValuesFormScreen(
      title: editing ? 'Edit ${spec.titleOf(item!)}' : (spec.createLabel ?? 'Add ${spec.title.toLowerCase()}'),
      fields: [for (final f in spec.fields) if (!(editing && f.createOnly)) f],
      initial: item,
      submitLabel: editing ? 'Save changes' : (spec.createLabel ?? 'Create'),
      onSubmit: (values) async {
        final api = ref.read(manageApiProvider);
        if (editing) {
          await api.patch(_resolvePath(spec.path, item!, spec.idKey, null), values);
        } else {
          await api.post(spec.path, {if (spec.sendCommunity && api.communityId != null) 'community': api.communityId, ...values});
        }
        ref.invalidate(manageSummaryProvider);
        return true;
      },
    );
  }
}

/// Generic form built from [fields]. With [onSubmit] it saves and pops `true`;
/// without it, it pops the collected values.
class ValuesFormScreen extends ConsumerStatefulWidget {
  const ValuesFormScreen({
    super.key,
    required this.title,
    required this.fields,
    this.initial,
    this.submitLabel = 'Save',
    this.onSubmit,
    this.intro,
    this.successMessage,
  });

  final String title;
  final List<FieldSpec> fields;
  final Json? initial;
  final String submitLabel;
  final Future<Object?> Function(Json values)? onSubmit;
  final String? intro;
  final String Function(Object? result)? successMessage;

  @override
  ConsumerState<ValuesFormScreen> createState() => _ValuesFormScreenState();
}

class _ValuesFormScreenState extends ConsumerState<ValuesFormScreen> {
  final _formKey = GlobalKey<FormState>();
  final Map<String, dynamic> _values = {};
  final Map<String, TextEditingController> _text = {};
  final Map<String, Future<List<Json>>> _refs = {};
  bool _saving = false;

  static final _dateFmt = DateFormat('yyyy-MM-dd');

  @override
  void initState() {
    super.initState();
    for (final f in widget.fields) {
      final v = widget.initial == null ? f.initial : (_read(widget.initial!, f.key) ?? f.initial);
      switch (f.type) {
        case FieldType.boolean:
          _values[f.key] = v == true;
        case FieldType.choice || FieldType.ref:
          _values[f.key] = v?.toString();
        case FieldType.refMulti:
          _values[f.key] = <String>{for (final e in (v as List? ?? [])) '$e'};
        case FieldType.date || FieldType.dateTime:
          _values[f.key] = v == null ? null : DateTime.tryParse('$v')?.toLocal();
        case FieldType.lines:
          _text[f.key] = TextEditingController(
              text: (v as List? ?? []).map((e) => e is Map ? '${e['label'] ?? ''}' : '$e').join('\n'));
        default:
          _text[f.key] = TextEditingController(text: v == null ? '' : '$v');
      }
      if (f.type == FieldType.ref || f.type == FieldType.refMulti) {
        _refs[f.key] = ref.read(manageApiProvider).listAll(f.refPath!, community: f.refCommunity);
      }
    }
  }

  @override
  void dispose() {
    for (final c in _text.values) {
      c.dispose();
    }
    super.dispose();
  }

  Json _collect() {
    final body = <String, dynamic>{};
    for (final f in widget.fields) {
      final dynamic value;
      switch (f.type) {
        case FieldType.text || FieldType.multiline || FieldType.phone:
          value = _text[f.key]!.text.trim();
        case FieldType.integer:
          final t = _text[f.key]!.text.trim();
          value = t.isEmpty ? null : int.tryParse(t);
        case FieldType.decimal:
          final t = _text[f.key]!.text.trim();
          value = t.isEmpty ? null : t;
        case FieldType.lines:
          value = _text[f.key]!.text.split('\n').map((e) => e.trim()).where((e) => e.isNotEmpty).toList();
        case FieldType.date:
          final d = _values[f.key] as DateTime?;
          value = d == null ? null : _dateFmt.format(d);
        case FieldType.dateTime:
          final d = _values[f.key] as DateTime?;
          value = d?.toUtc().toIso8601String();
        case FieldType.refMulti:
          value = (_values[f.key] as Set<String>).toList();
        default:
          value = _values[f.key];
      }
      // Leave out empty optional values so the server keeps its defaults; when editing,
      // only send a blank if the user actually cleared a field that had a value.
      if (value == null) continue;
      if (value is String && value.isEmpty) {
        final before = widget.initial == null ? null : _read(widget.initial!, f.key);
        if (before == null || '$before'.isEmpty) continue;
      }
      _write(body, f.key, value);
    }
    return body;
  }

  Future<void> _submit() async {
    if (!_formKey.currentState!.validate()) return;
    for (final f in widget.fields) {
      if (f.required && (f.type == FieldType.date || f.type == FieldType.dateTime || f.type == FieldType.ref ||
          f.type == FieldType.choice) && _values[f.key] == null) {
        context.showSnack('${f.label} is required');
        return;
      }
    }
    final values = _collect();
    if (widget.onSubmit == null) {
      Navigator.pop(context, values);
      return;
    }
    setState(() => _saving = true);
    final result = await runAction(context, () => widget.onSubmit!(values));
    if (!mounted) return;
    setState(() => _saving = false);
    if (result != null) {
      if (widget.successMessage != null) context.showSnack(widget.successMessage!(result));
      Navigator.pop(context, true);
    }
  }

  Future<void> _pickDate(FieldSpec f) async {
    final now = DateTime.now();
    final current = _values[f.key] as DateTime? ?? now;
    final date = await showDatePicker(
      context: context,
      initialDate: current,
      firstDate: DateTime(now.year - 5),
      lastDate: DateTime(now.year + 5),
    );
    if (date == null || !mounted) return;
    var result = date;
    if (f.type == FieldType.dateTime) {
      final time = await showTimePicker(context: context, initialTime: TimeOfDay.fromDateTime(current));
      if (time == null) return;
      result = DateTime(date.year, date.month, date.day, time.hour, time.minute);
    }
    setState(() => _values[f.key] = result);
  }

  Widget _field(FieldSpec f) {
    final label = f.required ? '${f.label} *' : f.label;
    String? req(String? v) => f.required && (v == null || v.trim().isEmpty) ? 'Required' : null;
    switch (f.type) {
      case FieldType.text || FieldType.phone:
        return TextFormField(
          controller: _text[f.key],
          keyboardType: f.type == FieldType.phone ? TextInputType.phone : TextInputType.text,
          decoration: InputDecoration(labelText: label, helperText: f.hint, helperMaxLines: 3),
          validator: req,
        );
      case FieldType.multiline || FieldType.lines:
        return TextFormField(
          controller: _text[f.key],
          minLines: 3,
          maxLines: 8,
          decoration: InputDecoration(labelText: label, helperText: f.hint, alignLabelWithHint: true, helperMaxLines: 3),
          validator: req,
        );
      case FieldType.integer || FieldType.decimal:
        return TextFormField(
          controller: _text[f.key],
          keyboardType: TextInputType.numberWithOptions(decimal: f.type == FieldType.decimal),
          decoration: InputDecoration(labelText: label, helperText: f.hint),
          validator: (v) {
            final r = req(v);
            if (r != null || v == null || v.trim().isEmpty) return r;
            return num.tryParse(v.trim()) == null ? 'Enter a number' : null;
          },
        );
      case FieldType.boolean:
        return SwitchListTile(
          contentPadding: EdgeInsets.zero,
          title: Text(f.label),
          subtitle: f.hint == null ? null : Text(f.hint!),
          value: _values[f.key] as bool,
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
      case FieldType.choice:
        return DropdownButtonFormField<String>(
          initialValue: f.choices.contains(_values[f.key]) ? _values[f.key] as String : null,
          decoration: InputDecoration(labelText: label, helperText: f.hint),
          items: [for (final c in f.choices) DropdownMenuItem(value: c, child: Text(humanize(c)))],
          onChanged: (v) => setState(() => _values[f.key] = v),
        );
      case FieldType.date || FieldType.dateTime:
        final d = _values[f.key] as DateTime?;
        return InkWell(
          onTap: () => _pickDate(f),
          child: InputDecorator(
            decoration: InputDecoration(
              labelText: label,
              helperText: f.hint,
              suffixIcon: const Icon(Icons.event_rounded),
            ),
            child: Text(d == null ? 'Select' : (f.type == FieldType.date ? Fmt.date(d) : Fmt.dateTime(d))),
          ),
        );
      case FieldType.ref || FieldType.refMulti:
        return FutureBuilder<List<Json>>(
          future: _refs[f.key],
          builder: (context, snap) {
            if (snap.hasError) return Text('${f.label}: ${snap.error}', style: TextStyle(color: context.palette.danger));
            if (!snap.hasData) return const LinearProgressIndicator();
            final options = snap.data!;
            String labelOf(Json o) => '${_read(o, f.refLabel) ?? o['name'] ?? o['id']}';
            if (f.type == FieldType.refMulti) {
              final selected = _values[f.key] as Set<String>;
              return InputDecorator(
                decoration: InputDecoration(labelText: label, helperText: f.hint ?? 'None selected = everyone'),
                child: Wrap(spacing: AppSpacing.sm, runSpacing: AppSpacing.xs, children: [
                  for (final o in options)
                    FilterChip(
                      label: Text(labelOf(o)),
                      selected: selected.contains('${o['id']}'),
                      onSelected: (on) => setState(() => on ? selected.add('${o['id']}') : selected.remove('${o['id']}')),
                    ),
                ]),
              );
            }
            final ids = options.map((o) => '${o['id']}').toSet();
            return DropdownButtonFormField<String>(
              initialValue: ids.contains(_values[f.key]) ? _values[f.key] as String : null,
              isExpanded: true,
              decoration: InputDecoration(labelText: label, helperText: f.hint),
              items: [
                if (!f.required) const DropdownMenuItem<String>(value: null, child: Text('— None —')),
                for (final o in options) DropdownMenuItem(value: '${o['id']}', child: Text(labelOf(o), overflow: TextOverflow.ellipsis)),
              ],
              onChanged: (v) => setState(() => _values[f.key] = v),
            );
          },
        );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.title)),
      body: ManageWidth(maxWidth: 720, child: SafeArea(
        child: Form(
          key: _formKey,
          child: ListView(
            padding: AppSpacing.screenAll,
            children: [
              if (widget.intro != null) ...[
                Text(widget.intro!, style: context.text.bodyMedium?.copyWith(color: context.palette.textMuted)),
                const SizedBox(height: AppSpacing.lg),
              ],
              for (final f in widget.fields) ...[_field(f), const SizedBox(height: AppSpacing.md)],
              const SizedBox(height: AppSpacing.md),
              FilledButton(
                onPressed: _saving ? null : _submit,
                child: _saving
                    ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4))
                    : Text(widget.submitLabel),
              ),
            ],
          ),
        ),
      )),
    );
  }
}
