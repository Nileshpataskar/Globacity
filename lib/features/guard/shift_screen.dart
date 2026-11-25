import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/guard.dart';

/// Shift selection: choose gate + shift to go on duty, or end the current shift.
class ShiftScreen extends ConsumerStatefulWidget {
  const ShiftScreen({super.key});

  @override
  ConsumerState<ShiftScreen> createState() => _ShiftScreenState();
}

class _ShiftScreenState extends ConsumerState<ShiftScreen> {
  String? _gate;
  String _shift = _defaultShift();
  bool _busy = false;

  static const _shifts = [
    ('morning', 'Morning', '6 AM – 2 PM', Icons.wb_sunny_outlined),
    ('evening', 'Evening', '2 PM – 10 PM', Icons.wb_twilight_rounded),
    ('night', 'Night', '10 PM – 6 AM', Icons.nightlight_outlined),
  ];

  static String _defaultShift() {
    final h = DateTime.now().hour;
    return h >= 6 && h < 14 ? 'morning' : (h >= 14 && h < 22 ? 'evening' : 'night');
  }

  Future<void> _start(GuardContext c) async {
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      await ref.read(guardActionsProvider).startShift(c.communityId, _gate ?? (c.gates.isEmpty ? null : c.gates.first.id), _shift);
      return true;
    }, success: 'Shift started. Stay alert!');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) context.pop();
  }

  Future<void> _end(GuardShift s) async {
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      await ref.read(guardActionsProvider).endShift(s.id);
      return true;
    }, success: 'Shift ended');
    if (!mounted) return;
    setState(() => _busy = false);
    if (ok == true) context.pop();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('My shift')),
      body: AsyncView<GuardContext>(
        value: ref.watch(guardContextProvider),
        onRetry: () => ref.invalidate(guardContextProvider),
        data: (c) {
          final current = c.shift;
          if (current != null) {
            return ListView(
              padding: AppSpacing.screenAll,
              children: [
                AppCard(
                  child: Column(
                    children: [
                      IconBadge(icon: Icons.verified_user_rounded, color: context.palette.success, size: 64),
                      const SizedBox(height: AppSpacing.md),
                      Text('On duty', style: context.text.titleLarge),
                      const SizedBox(height: AppSpacing.xs),
                      Text(current.shiftLabel, style: context.text.bodyMedium),
                      const SizedBox(height: AppSpacing.md),
                      InfoRow(icon: Icons.door_sliding_outlined, label: 'Gate', value: current.gateName ?? 'All gates'),
                      InfoRow(icon: Icons.schedule_rounded, label: 'Started', value: Fmt.dateTime(current.startedAt)),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.xl),
                FilledButton.icon(
                  style: FilledButton.styleFrom(backgroundColor: context.palette.danger),
                  onPressed: _busy ? null : () => _end(current),
                  icon: const Icon(Icons.logout_rounded),
                  label: const Text('End shift'),
                ),
              ],
            );
          }
          return ListView(
            padding: AppSpacing.screenAll,
            children: [
              Text(c.communityName, style: context.text.titleMedium),
              const SizedBox(height: AppSpacing.xs),
              Text('Choose where and when you are on duty.', style: context.text.bodySmall),
              const SectionHeader(title: 'Gate'),
              Wrap(
                spacing: AppSpacing.sm,
                runSpacing: AppSpacing.sm,
                children: [
                  for (final g in c.gates)
                    ChoiceChip(
                      avatar: Icon(g.iotEnabled ? Icons.sensors_rounded : Icons.door_sliding_outlined, size: 18),
                      label: Text(g.name),
                      selected: (_gate ?? c.gates.first.id) == g.id,
                      onSelected: (_) => setState(() => _gate = g.id),
                    ),
                ],
              ),
              const SectionHeader(title: 'Shift'),
              for (final (id, label, hours, icon) in _shifts) ...[
                AppCard(
                  onTap: () => setState(() => _shift = id),
                  borderColor: _shift == id ? context.scheme.primary : null,
                  color: _shift == id ? context.scheme.primary.withValues(alpha: 0.06) : null,
                  child: Row(
                    children: [
                      IconBadge(icon: icon, color: _shift == id ? context.scheme.primary : context.palette.textMuted),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [Text(label, style: context.text.titleSmall), Text(hours, style: context.text.bodySmall)],
                        ),
                      ),
                      Icon(_shift == id ? Icons.radio_button_checked_rounded : Icons.radio_button_off_rounded,
                          color: _shift == id ? context.scheme.primary : context.palette.textMuted),
                    ],
                  ),
                ),
                const SizedBox(height: AppSpacing.sm),
              ],
              const SizedBox(height: AppSpacing.lg),
              FilledButton.icon(
                onPressed: _busy ? null : () => _start(c),
                icon: const Icon(Icons.login_rounded),
                label: const Text('Start shift'),
              ),
            ],
          );
        },
      ),
    );
  }
}
