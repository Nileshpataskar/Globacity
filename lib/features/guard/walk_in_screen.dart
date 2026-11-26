import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:image_picker/image_picker.dart' show XFile;

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/device.dart';
import '../../core/widgets/widgets.dart';
import '../../data/guard.dart';
import '../../data/models.dart';

/// Manual entry for visitors without a pass. Residents get an approve/deny request instantly.
class WalkInScreen extends ConsumerStatefulWidget {
  const WalkInScreen({super.key, this.initialType});

  /// Pre-selected visitor type, e.g. delivery from the gate home's "Delivery" button.
  final VisitorType? initialType;

  @override
  ConsumerState<WalkInScreen> createState() => _WalkInScreenState();
}

class _WalkInScreenState extends ConsumerState<WalkInScreen> {
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _vehicle = TextEditingController();
  late VisitorType _type = widget.initialType ?? VisitorType.guest;
  String? _company;
  int _guests = 1;
  DirectoryEntry? _unit;
  XFile? _photo;
  bool _saving = false;

  /// Common companies by country, so the guard taps instead of typing.
  static const _companiesByCountry = {
    'IN': {
      VisitorType.delivery: ['Swiggy', 'Zomato', 'Amazon', 'Flipkart', 'Blinkit', 'Zepto', 'BigBasket', 'Swiggy Instamart',
          'Myntra', 'Blue Dart', 'Delhivery', 'Courier', 'Other'],
      VisitorType.cab: ['Ola', 'Uber', 'Rapido', 'Auto rickshaw', 'Other'],
      VisitorType.service: ['Plumber', 'Electrician', 'Carpenter', 'AC repair', 'Internet / cable', 'Pest control',
          'Gas cylinder', 'Water can', 'Other'],
    },
    'AE': {
      VisitorType.delivery: ['Amazon', 'Noon', 'Talabat', 'Deliveroo', 'Careem Now', 'Other'],
      VisitorType.cab: ['Careem', 'Uber', 'Taxi', 'Other'],
      VisitorType.service: ['AC repair', 'Plumber', 'Electrician', 'Internet', 'Pest control', 'Other'],
    },
  };

  Map<VisitorType, List<String>> get _companies =>
      _companiesByCountry[ref.watch(guardContextProvider).value?.country] ?? _companiesByCountry['IN']!;

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _vehicle.dispose();
    super.dispose();
  }

  Future<void> _pickUnit() async {
    final picked = await showModalBottomSheet<DirectoryEntry>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      builder: (_) => const _UnitPicker(),
    );
    if (picked != null) setState(() => _unit = picked);
  }

  Future<void> _submit() async {
    final name = _type == VisitorType.guest || _company == 'Other' || _company == null
        ? _name.text.trim()
        : '$_company${_type == VisitorType.delivery ? ' Delivery' : ''}';
    if (_unit == null || name.isEmpty) {
      context.showSnack('Select the unit and enter the visitor name');
      return;
    }
    setState(() => _saving = true);
    final v = await runAction(context, () => ref.read(guardActionsProvider).walkIn({
          'unit': _unit!.unitId,
          'name': name,
          'phone': _phone.text.trim(),
          'visitor_type': _type.name,
          'company': _type == VisitorType.guest ? '' : (_company ?? ''),
          'vehicle_no': _vehicle.text.trim(),
          'guests': _guests,
          'gate': ?ref.read(guardContextProvider).value?.shift?.gateId,
        }, photo: _photo));
    if (!mounted) return;
    setState(() => _saving = false);
    if (v != null) {
      context.showSnack(v.status == VisitorStatus.waiting
          ? 'Approval request sent to ${_unit!.unitLabel}'
          : '${v.name} checked in');
      context.pop();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Walk-in visitor')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: AppSpacing.screenAll,
          child: FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: const Icon(Icons.send_rounded),
            label: const Text('Request approval'),
          ),
        ),
      ),
      body: ListView(
        padding: AppSpacing.screenAll,
        children: [
          LabeledField(
            label: 'Visiting unit',
            child: AppCard(
              onTap: _pickUnit,
              child: Row(
                children: [
                  IconBadge(icon: Icons.apartment_rounded, color: _unit == null ? context.palette.textMuted : null),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(_unit?.unitLabel ?? 'Search unit, resident or vehicle', style: context.text.titleSmall),
                        if (_unit != null && _unit!.residents.isNotEmpty)
                          Text(_unit!.residents.map((r) => r.name).join(', '), style: context.text.bodySmall),
                      ],
                    ),
                  ),
                  const Icon(Icons.search_rounded),
                ],
              ),
            ),
          ),
          LabeledField(
            label: 'Visitor type',
            child: Wrap(
              spacing: AppSpacing.sm,
              runSpacing: AppSpacing.sm,
              children: [
                for (final t in [VisitorType.guest, VisitorType.delivery, VisitorType.cab, VisitorType.service])
                  ChoiceChip(
                    avatar: Icon(t.icon, size: 18),
                    label: Text(t.label),
                    selected: _type == t,
                    onSelected: (_) => setState(() {
                      _type = t;
                      _company = null;
                    }),
                  ),
              ],
            ),
          ),
          if (_type != VisitorType.guest)
            LabeledField(
              label: _type == VisitorType.service ? 'Service' : 'Company',
              child: Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final c in _companies[_type]!)
                    ChoiceChip(label: Text(c), selected: _company == c, onSelected: (_) => setState(() => _company = c)),
                ],
              ),
            ),
          if (_type == VisitorType.guest || _company == 'Other')
            LabeledField(
              label: 'Visitor name',
              child: TextField(controller: _name, textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(prefixIcon: Icon(Icons.person_outline_rounded))),
            ),
          LabeledField(
            label: 'Mobile number',
            child: TextField(controller: _phone, keyboardType: TextInputType.phone,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.phone_outlined))),
          ),
          LabeledField(
            label: 'Vehicle number (optional)',
            child: TextField(controller: _vehicle, textCapitalization: TextCapitalization.characters,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.directions_car_outlined))),
          ),
          if (_type == VisitorType.guest)
            LabeledField(
              label: 'Number of people',
              child: Row(
                children: [
                  IconButton(onPressed: _guests > 1 ? () => setState(() => _guests--) : null,
                      icon: const Icon(Icons.remove_circle_outline_rounded)),
                  Text('$_guests', style: context.text.titleMedium),
                  IconButton(onPressed: () => setState(() => _guests++), icon: const Icon(Icons.add_circle_outline_rounded)),
                ],
              ),
            ),
          LabeledField(
            label: 'Visitor photo (optional)',
            child: PhotoPickerRow(photos: [?_photo], max: 1, onChanged: (p) => setState(() => _photo = p.isEmpty ? null : p.first)),
          ),
        ],
      ),
    );
  }
}

class _UnitPicker extends ConsumerStatefulWidget {
  const _UnitPicker();

  @override
  ConsumerState<_UnitPicker> createState() => _UnitPickerState();
}

class _UnitPickerState extends ConsumerState<_UnitPicker> {
  String _q = '';
  Timer? _debounce;

  @override
  void dispose() {
    _debounce?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SizedBox(
        height: MediaQuery.sizeOf(context).height * 0.75,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, AppSpacing.sm),
              child: TextField(
                autofocus: true,
                onChanged: (v) {
                  _debounce?.cancel();
                  _debounce = Timer(const Duration(milliseconds: 300), () => setState(() => _q = v.trim()));
                },
                decoration: const InputDecoration(hintText: 'Unit number, resident name or plate', prefixIcon: Icon(Icons.search_rounded)),
              ),
            ),
            Expanded(
              child: _q.isEmpty
                  ? const EmptyState(icon: Icons.apartment_rounded, title: 'Search for the unit')
                  : AsyncView<List<DirectoryEntry>>(
                      value: ref.watch(guardDirectoryProvider(_q)),
                      data: (rows) => rows.isEmpty
                          ? const EmptyState(icon: Icons.search_off_rounded, title: 'No matching unit')
                          : ListView(
                              children: [
                                for (final r in rows)
                                  ListTile(
                                    leading: const IconBadge(icon: Icons.apartment_rounded, size: 40),
                                    title: Text(r.unitLabel),
                                    subtitle: Text(r.residents.isEmpty ? 'No residents' : r.residents.map((e) => e.name).join(', ')),
                                    onTap: () => Navigator.pop(context, r),
                                  ),
                              ],
                            ),
                    ),
            ),
          ],
        ),
      ),
    );
  }
}

/// Quick dial helper used by guard screens.
Future<void> callResident(BuildContext context, String? phone) async {
  if (phone == null) {
    context.showSnack('The resident has not shared a number with the guard');
    return;
  }
  await Device.call(context, phone);
}
