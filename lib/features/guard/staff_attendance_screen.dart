import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/device.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/guard.dart';

/// Mark community staff in / out for the day.
class StaffAttendanceScreen extends ConsumerStatefulWidget {
  const StaffAttendanceScreen({super.key});

  @override
  ConsumerState<StaffAttendanceScreen> createState() => _StaffAttendanceScreenState();
}

class _StaffAttendanceScreenState extends ConsumerState<StaffAttendanceScreen> {
  String _q = '';

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Staff attendance')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.lg, AppSpacing.sm, AppSpacing.lg, 0),
            child: TextField(
              onChanged: (v) => setState(() => _q = v.toLowerCase()),
              decoration: const InputDecoration(hintText: 'Search staff', prefixIcon: Icon(Icons.search_rounded)),
            ),
          ),
          Expanded(
            child: RefreshIndicator(
              onRefresh: () => ref.refresh(guardStaffProvider.future),
              child: AsyncView<List<StaffStatus>>(
                value: ref.watch(guardStaffProvider),
                onRetry: () => ref.invalidate(guardStaffProvider),
                data: (all) {
                  final staff = all.where((s) => s.name.toLowerCase().contains(_q) || s.designation.toLowerCase().contains(_q)).toList();
                  final inside = staff.where((s) => s.isInside).length;
                  if (staff.isEmpty) return ListView(children: const [EmptyState(icon: Icons.badge_outlined, title: 'No staff found')]);
                  return ListView(
                    padding: AppSpacing.screenAll,
                    children: [
                      Text('$inside of ${staff.length} on duty today', style: context.text.labelMedium),
                      const SizedBox(height: AppSpacing.md),
                      for (final s in staff) ...[
                        AppCard(
                          child: Row(
                            children: [
                              AppAvatar(name: s.name),
                              const SizedBox(width: AppSpacing.md),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(s.name, style: context.text.titleSmall),
                                    Text([s.designation.isEmpty ? s.role : s.designation, if (s.shift.isNotEmpty) s.shift].join(' · '),
                                        style: context.text.bodySmall),
                                    if (s.checkIn != null)
                                      Text(
                                        s.isInside ? 'In since ${Fmt.time(s.checkIn!)}' : 'Out at ${Fmt.time(s.checkOut!)}',
                                        style: context.text.labelSmall?.copyWith(
                                            color: s.isInside ? context.palette.success : context.palette.textMuted),
                                      ),
                                  ],
                                ),
                              ),
                              if (s.phone.isNotEmpty)
                                IconButton(onPressed: () => Device.call(context, s.phone), icon: const Icon(Icons.call_outlined)),
                              s.isInside
                                  ? OutlinedButton(
                                      style: OutlinedButton.styleFrom(minimumSize: const Size(0, 38)),
                                      onPressed: () => runAction(context,
                                          () => ref.read(guardActionsProvider).staffAttendance(s.id, checkIn: false),
                                          success: '${s.name} checked out'),
                                      child: const Text('Out'),
                                    )
                                  : FilledButton(
                                      style: FilledButton.styleFrom(minimumSize: const Size(0, 38)),
                                      onPressed: s.checkOut != null
                                          ? null
                                          : () => runAction(context,
                                              () => ref.read(guardActionsProvider).staffAttendance(s.id, checkIn: true),
                                              success: '${s.name} checked in'),
                                      child: const Text('In'),
                                    ),
                            ],
                          ),
                        ),
                        const SizedBox(height: AppSpacing.sm),
                      ],
                    ],
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }
}
