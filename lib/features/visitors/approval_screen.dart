import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/device.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Incoming entry request from the gate: approve, deny or leave at gate.
class ApprovalScreen extends ConsumerStatefulWidget {
  const ApprovalScreen({super.key, required this.visitorId});

  final String visitorId;

  @override
  ConsumerState<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends ConsumerState<ApprovalScreen> {
  bool _busy = false;

  Future<void> _respond(String action, String message) async {
    setState(() => _busy = true);
    final ok = await runAction(context, () async {
      await ref.read(actionsProvider).visitorAction(widget.visitorId, action);
      return true;
    }, success: message);
    if (!mounted) return;
    if (ok == true) {
      context.pop();
    } else {
      setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = visitorProvider(widget.visitorId);
    return Scaffold(
      appBar: AppBar(
        leading: IconButton(icon: const Icon(Icons.close_rounded), onPressed: () => context.pop()),
        title: const Text('Entry request'),
      ),
      body: AsyncView<Visitor>(
        value: ref.watch(provider),
        onRetry: () => ref.invalidate(provider),
        data: (v) => SafeArea(
          child: Padding(
            padding: const EdgeInsets.all(AppSpacing.xl),
            child: Column(
              children: [
                const Spacer(),
                StatusChip(
                  label: v.status == VisitorStatus.waiting ? 'Waiting at ${v.gate}' : v.status.label,
                  tone: v.status == VisitorStatus.waiting ? Tone.warning : v.status.tone,
                  icon: Icons.door_sliding_outlined,
                ),
                const SizedBox(height: AppSpacing.xl),
                Container(
                  padding: const EdgeInsets.all(AppSpacing.sm),
                  decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: context.palette.warning, width: 3)),
                  child: AppAvatar(name: v.name, icon: v.type.icon, size: 120),
                ),
                const SizedBox(height: AppSpacing.xl),
                Text(v.name, style: context.text.headlineSmall, textAlign: TextAlign.center),
                const SizedBox(height: AppSpacing.xs),
                Text(
                  [v.type.label, if (v.company != null) v.company!, 'Arrived ${Fmt.relative(v.time)}'].join(' · '),
                  style: context.text.bodyMedium?.copyWith(color: context.palette.textMuted),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: AppSpacing.lg),
                if (v.phone != null)
                  TextButton.icon(
                    onPressed: () => Device.call(context, v.phone!),
                    icon: const Icon(Icons.call_rounded),
                    label: Text(v.phone!),
                  ),
                const Spacer(),
                if (v.status != VisitorStatus.waiting)
                  Text('This request has already been handled.', style: context.text.bodyMedium)
                else ...[
                  if (v.type == VisitorType.delivery) ...[
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : () => _respond('leave-at-gate', 'Delivery will be left at the gate'),
                        icon: const Icon(Icons.inventory_rounded),
                        label: const Text('Leave at gate'),
                      ),
                    ),
                    const SizedBox(height: AppSpacing.md),
                  ],
                  Row(
                    children: [
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: context.palette.danger),
                          onPressed: _busy ? null : () => _respond('deny', 'Entry denied for ${v.name}'),
                          icon: const Icon(Icons.close_rounded),
                          label: const Text('Deny'),
                        ),
                      ),
                      const SizedBox(width: AppSpacing.md),
                      Expanded(
                        child: FilledButton.icon(
                          style: FilledButton.styleFrom(backgroundColor: context.palette.success),
                          onPressed: _busy ? null : () => _respond('approve', '${v.name} approved for entry'),
                          icon: const Icon(Icons.check_rounded),
                          label: const Text('Approve'),
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }
}
