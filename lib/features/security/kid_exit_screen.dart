import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Pre-authorise children to leave the premises unaccompanied.
class KidExitScreen extends ConsumerStatefulWidget {
  const KidExitScreen({super.key});

  @override
  ConsumerState<KidExitScreen> createState() => _KidExitScreenState();
}

class _KidExitScreenState extends ConsumerState<KidExitScreen> {
  final Set<String> _kids = {};
  int _minutes = 60;
  bool _saving = false;
  final _note = TextEditingController();

  static const _durations = [(30, '30 min'), (60, '1 hour'), (120, '2 hours'), (240, '4 hours'), (720, '12 hours')];

  @override
  void dispose() {
    _note.dispose();
    super.dispose();
  }

  Future<void> _submit() async {
    setState(() => _saving = true);
    final ok = await runAction(context, () async {
      await ref.read(actionsProvider).allowKidExit(_kids.toList(), _minutes, _note.text.trim());
      return true;
    }, success: 'Security notified');
    if (!mounted) return;
    setState(() => _saving = false);
    if (ok == true) context.pop();
  }

  void _toggle(String id) => setState(() => _kids.contains(id) ? _kids.remove(id) : _kids.add(id));

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Allow kid exit')),
      bottomNavigationBar: SafeArea(
        child: Padding(
          padding: AppSpacing.screenAll,
          child: FilledButton(onPressed: _kids.isEmpty || _saving ? null : _submit, child: const Text('Allow exit')),
        ),
      ),
      body: ListView(
        padding: AppSpacing.screenAll,
        children: [
          AppCard(
            color: context.palette.info.withValues(alpha: 0.08),
            borderColor: context.palette.info.withValues(alpha: 0.3),
            child: Row(
              children: [
                Icon(Icons.shield_outlined, color: context.palette.info),
                const SizedBox(width: AppSpacing.md),
                Expanded(child: Text('Guards will stop children from leaving alone unless you allow it here.', style: context.text.bodySmall)),
              ],
            ),
          ),
          const SectionHeader(title: 'Select child'),
          AsyncView<List<FamilyMember>>(
            value: ref.watch(familyProvider),
            compact: true,
            onRetry: () => ref.invalidate(familyProvider),
            data: (family) {
              final kids = family.where((m) => m.isMinor).toList();
              if (kids.isEmpty) {
                return const EmptyState(icon: Icons.child_care_rounded, title: 'No children added',
                    message: 'Add children under My household → Family and mark them as "Child".');
              }
              return Column(
                children: [
                  for (final k in kids) ...[
                    AppCard(
                      onTap: () => _toggle(k.id),
                      borderColor: _kids.contains(k.id) ? context.scheme.primary : null,
                      child: Row(
                        children: [
                          AppAvatar(name: k.name),
                          const SizedBox(width: AppSpacing.md),
                          Expanded(child: Text(k.name, style: context.text.titleSmall)),
                          Checkbox(value: _kids.contains(k.id), onChanged: (_) => _toggle(k.id)),
                        ],
                      ),
                    ),
                    const SizedBox(height: AppSpacing.sm),
                  ],
                ],
              );
            },
          ),
          const SectionHeader(title: 'Allowed for'),
          Wrap(
            spacing: AppSpacing.sm,
            runSpacing: AppSpacing.sm,
            children: [
              for (final (m, label) in _durations)
                ChoiceChip(label: Text(label), selected: _minutes == m, onSelected: (_) => setState(() => _minutes = m)),
            ],
          ),
          const SectionHeader(title: 'Note for guard'),
          TextField(controller: _note, maxLines: 2, decoration: const InputDecoration(hintText: 'e.g. Going to the supermarket with a friend')),
        ],
      ),
    );
  }
}
