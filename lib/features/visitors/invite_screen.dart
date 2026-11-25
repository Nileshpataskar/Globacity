import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';
import '../../data/models.dart';

/// Pre-approve a guest, cab, delivery or service visit (or a recurring frequent entry).
class InviteScreen extends ConsumerStatefulWidget {
  const InviteScreen({super.key});

  @override
  ConsumerState<InviteScreen> createState() => _InviteScreenState();
}

class _InviteScreenState extends ConsumerState<InviteScreen> {
  final _formKey = GlobalKey<FormState>();
  final _name = TextEditingController();
  final _phone = TextEditingController();
  final _vehicle = TextEditingController();
  VisitorType _type = VisitorType.guest;
  String? _company;
  int _guests = 1;
  DateTime _date = DateTime.now();
  TimeOfDay _time = TimeOfDay.fromDateTime(DateTime.now().add(const Duration(hours: 1)));
  bool _frequent = false;
  bool _saving = false;

  static const _companies = {
    VisitorType.delivery: ['Amazon', 'Noon', 'Talabat', 'Deliveroo', 'Careem Now', 'Other'],
    VisitorType.cab: ['Careem', 'Uber', 'Taxi', 'Other'],
    VisitorType.service: ['AC repair', 'Plumber', 'Electrician', 'Internet', 'Pest control', 'Other'],
  };

  @override
  void dispose() {
    _name.dispose();
    _phone.dispose();
    _vehicle.dispose();
    super.dispose();
  }

  bool get _needsName => _type == VisitorType.guest || _company == 'Other';

  Future<void> _pickDate() async {
    final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now(),
        lastDate: DateTime.now().add(const Duration(days: 90)));
    if (d != null) setState(() => _date = d);
  }

  Future<void> _pickTime() async {
    final t = await showTimePicker(context: context, initialTime: _time);
    if (t != null) setState(() => _time = t);
  }

  Future<void> _submit() async {
    if (_type != VisitorType.guest && _company == null) {
      context.showSnack('Select a company or service');
      return;
    }
    if (!_formKey.currentState!.validate()) return;
    final name = _needsName
        ? _name.text.trim()
        : '$_company${_type == VisitorType.delivery ? ' Delivery' : ''}';
    final when = DateTime(_date.year, _date.month, _date.day, _time.hour, _time.minute);
    final actions = ref.read(actionsProvider);
    setState(() => _saving = true);

    if (_frequent) {
      String hhmm(TimeOfDay t) => '${t.hour.toString().padLeft(2, '0')}:${t.minute.toString().padLeft(2, '0')}';
      final end = TimeOfDay(hour: (_time.hour + 1) % 24, minute: _time.minute);
      final ok = await runAction(context, () async {
        await actions.addFrequentEntry({
          'name': name,
          'phone': _phone.text,
          'visitor_type': _type.name,
          'company': _type == VisitorType.guest ? '' : _company,
          'valid_from': _date.toIso8601String().substring(0, 10),
          'valid_until': _date.add(const Duration(days: 30)).toIso8601String().substring(0, 10),
          'time_from': hhmm(_time),
          'time_to': hhmm(end),
        });
        return true;
      }, success: 'Frequent entry added for 30 days');
      if (!mounted) return;
      setState(() => _saving = false);
      if (ok == true) context.pushReplacement('${Routes.household}?tab=4');
      return;
    }

    final visitor = await runAction(context, () => actions.preApprove({
          'name': name,
          'phone': _phone.text,
          'visitor_type': _type.name,
          'company': _type == VisitorType.guest ? '' : _company,
          'vehicle_no': _vehicle.text,
          'guests': _guests,
          'expected_at': when.toUtc().toIso8601String(),
        }));
    if (!mounted) return;
    setState(() => _saving = false);
    if (visitor != null) context.pushReplacement(Routes.pass(visitor.id));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Pre-approve entry')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: AppSpacing.screenAll,
          child: FilledButton.icon(
            onPressed: _saving ? null : _submit,
            icon: const Icon(Icons.qr_code_2_rounded),
            label: Text(_frequent ? 'Add frequent entry' : 'Generate gate pass'),
          ),
        ),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: AppSpacing.screenAll,
          children: [
            LabeledField(
              label: 'Who is visiting?',
              child: Row(
                children: [
                  for (final t in [VisitorType.guest, VisitorType.cab, VisitorType.delivery, VisitorType.service])
                    Expanded(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.only(end: AppSpacing.sm),
                        child: _TypeCard(type: t, selected: _type == t, onTap: () => setState(() {
                              _type = t;
                              _company = null;
                            })),
                      ),
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
            if (_needsName)
              LabeledField(
                label: _type == VisitorType.guest ? 'Guest name' : 'Name',
                child: TextFormField(
                  controller: _name,
                  textCapitalization: TextCapitalization.words,
                  decoration: const InputDecoration(hintText: 'Full name', prefixIcon: Icon(Icons.person_outline_rounded)),
                  validator: (v) => (v == null || v.trim().isEmpty) ? 'Required' : null,
                ),
              ),
            if (_type == VisitorType.guest)
              LabeledField(
                label: 'Mobile number (optional)',
                child: TextFormField(
                  controller: _phone,
                  keyboardType: TextInputType.phone,
                  inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'[0-9+ ]'))],
                  decoration: const InputDecoration(hintText: '+971 50 123 4567', prefixIcon: Icon(Icons.phone_outlined)),
                ),
              ),
            if (!_frequent && (_type == VisitorType.cab || _type == VisitorType.guest))
              LabeledField(
                label: 'Vehicle number (optional)',
                child: TextFormField(
                  controller: _vehicle,
                  textCapitalization: TextCapitalization.characters,
                  decoration: const InputDecoration(hintText: 'e.g. D 12345', prefixIcon: Icon(Icons.directions_car_outlined)),
                ),
              ),
            Row(
              children: [
                Expanded(
                  child: LabeledField(
                    label: _frequent ? 'Starting' : 'Date',
                    child: _PickerField(icon: Icons.calendar_today_rounded, value: Fmt.date(_date), onTap: _pickDate),
                  ),
                ),
                const SizedBox(width: AppSpacing.md),
                Expanded(
                  child: LabeledField(
                    label: 'Expected at',
                    child: _PickerField(icon: Icons.schedule_rounded, value: _time.format(context), onTap: _pickTime),
                  ),
                ),
              ],
            ),
            if (_type == VisitorType.guest && !_frequent)
              LabeledField(
                label: 'Number of guests',
                child: AppCard(
                  padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
                  child: Row(
                    children: [
                      const SizedBox(width: AppSpacing.sm),
                      Icon(Icons.groups_outlined, color: context.palette.textMuted),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(child: Text('$_guests ${_guests == 1 ? 'guest' : 'guests'}', style: context.text.titleSmall)),
                      IconButton(onPressed: _guests > 1 ? () => setState(() => _guests--) : null,
                          icon: const Icon(Icons.remove_circle_outline_rounded)),
                      IconButton(onPressed: _guests < 20 ? () => setState(() => _guests++) : null,
                          icon: const Icon(Icons.add_circle_outline_rounded)),
                    ],
                  ),
                ),
              ),
            AppCard(
              padding: EdgeInsets.zero,
              child: SwitchListTile(
                value: _frequent,
                onChanged: (v) => setState(() => _frequent = v),
                title: const Text('Frequent entry'),
                subtitle: const Text('Allow entry daily for the next 30 days (1-hour window)'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _TypeCard extends StatelessWidget {
  const _TypeCard({required this.type, required this.selected, required this.onTap});

  final VisitorType type;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final c = selected ? context.scheme.primary : context.palette.textMuted;
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.md),
      color: selected ? context.scheme.primary.withValues(alpha: 0.08) : null,
      borderColor: selected ? context.scheme.primary : null,
      child: Column(
        children: [
          Icon(type.icon, color: c),
          const SizedBox(height: AppSpacing.xs),
          Text(type.label, style: context.text.labelMedium?.copyWith(color: c)),
        ],
      ),
    );
  }
}

class _PickerField extends StatelessWidget {
  const _PickerField({required this.icon, required this.value, required this.onTap});

  final IconData icon;
  final String value;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return AppCard(
      onTap: onTap,
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.lg - 1),
      child: Row(
        children: [
          Icon(icon, size: 18, color: context.palette.textMuted),
          const SizedBox(width: AppSpacing.sm),
          Expanded(child: Text(value, style: context.text.bodyMedium)),
        ],
      ),
    );
  }
}
