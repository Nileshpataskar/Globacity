import '../../core/utils/device.dart';
import 'package:image_picker/image_picker.dart' show XFile;
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';
import '../../data/providers.dart';

/// Move-in / move-out permit request (reviewed by management).
class MoveRequestScreen extends ConsumerStatefulWidget {
  const MoveRequestScreen({super.key});

  @override
  ConsumerState<MoveRequestScreen> createState() => _MoveRequestScreenState();
}

class _MoveRequestScreenState extends ConsumerState<MoveRequestScreen> {
  bool _moveIn = true;
  DateTime _date = DateTime.now().add(const Duration(days: 7));
  bool _serviceLift = true;
  bool _saving = false;
  final _company = TextEditingController();
  final _notes = TextEditingController();
  final Map<String, XFile> _docs = {};

  static const _docTypes = ['ID card / Passport', 'Tenancy contract', 'Title deed (owners)', 'Moving company licence'];

  @override
  void dispose() {
    _company.dispose();
    _notes.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    final ok = await runAction(context, () async {
      await ref.read(actionsProvider).requestMove({
        'move_type': _moveIn ? 'move_in' : 'move_out',
        'move_date': _date.toIso8601String().substring(0, 10),
        'moving_company': _company.text.trim(),
        'service_lift': _serviceLift,
        'notes': _notes.text.trim(),
      }, documents: _docs);
      return true;
    }, success: 'Request submitted. Management will confirm shortly.');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    final property = ref.watch(currentPropertyProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Move in / out request')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: AppSpacing.screenAll,
          child: FilledButton(onPressed: _saving ? null : _submit, child: const Text('Submit request')),
        ),
      ),
      body: ListView(
        padding: AppSpacing.screenAll,
        children: [
          SegmentedButton<bool>(
            segments: const [
              ButtonSegment(value: true, label: Text('Move in'), icon: Icon(Icons.login_rounded)),
              ButtonSegment(value: false, label: Text('Move out'), icon: Icon(Icons.logout_rounded)),
            ],
            selected: {_moveIn},
            onSelectionChanged: (s) => setState(() => _moveIn = s.first),
          ),
          const SizedBox(height: AppSpacing.xl),
          AppCard(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
            child: Column(
              children: [
                InfoRow(icon: Icons.apartment_rounded, label: 'Unit',
                    value: property == null ? '-' : '${property.community}, ${property.shortLabel}'),
                InfoRow(icon: Icons.badge_outlined, label: 'Requested by', value: ref.watch(userProvider).name),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.lg),
          LabeledField(
            label: 'Preferred date',
            child: AppCard(
              onTap: () async {
                final d = await showDatePicker(context: context, initialDate: _date, firstDate: DateTime.now(),
                    lastDate: DateTime.now().add(const Duration(days: 120)));
                if (d != null) setState(() => _date = d);
              },
              child: Row(
                children: [
                  Icon(Icons.calendar_today_rounded, size: 18, color: context.palette.textMuted),
                  const SizedBox(width: AppSpacing.sm),
                  Text(Fmt.date(_date)),
                ],
              ),
            ),
          ),
          LabeledField(
            label: 'Moving company',
            child: TextField(controller: _company,
                decoration: const InputDecoration(hintText: 'Company name', prefixIcon: Icon(Icons.local_shipping_outlined))),
          ),
          LabeledField(
            label: 'Notes',
            child: TextField(controller: _notes, maxLines: 2, decoration: const InputDecoration(hintText: 'Anything management should know')),
          ),
          AppCard(
            padding: EdgeInsets.zero,
            child: SwitchListTile(
              value: _serviceLift,
              onChanged: (v) => setState(() => _serviceLift = v),
              title: const Text('Reserve service lift'),
              subtitle: const Text('4-hour slot, refundable deposit may apply'),
            ),
          ),
          const SectionHeader(title: 'Documents'),
          for (final d in _docTypes) ...[
            AppCard(
              padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.sm),
              onTap: () async {
                if (_docs.containsKey(d)) {
                  setState(() => _docs.remove(d));
                  return;
                }
                final photo = await Device.pickImage(context);
                if (photo != null) setState(() => _docs[d] = photo);
              },
              child: Row(
                children: [
                  if (_docs[d] != null) PickedThumb(file: _docs[d]!, size: 40)
                  else Icon(Icons.upload_file_rounded, color: context.palette.textMuted),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text(d, style: context.text.bodyMedium)),
                  Text(_docs.containsKey(d) ? 'Remove' : 'Upload',
                      style: context.text.labelMedium?.copyWith(color: _docs.containsKey(d) ? context.palette.danger : context.scheme.primary)),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.sm),
          ],
        ],
      ),
    );
  }
}
