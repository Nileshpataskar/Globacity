import '../../data/providers.dart';
import '../../core/utils/device.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';

/// Panic alert: press and hold to notify security, managers and your household.
class SosScreen extends ConsumerStatefulWidget {
  const SosScreen({super.key});

  @override
  ConsumerState<SosScreen> createState() => _SosScreenState();
}

class _SosScreenState extends ConsumerState<SosScreen> with SingleTickerProviderStateMixin {
  late final _hold = AnimationController(vsync: this, duration: const Duration(seconds: 3))
    ..addStatusListener((s) {
      if (s == AnimationStatus.completed) _send();
    });

  static const _types = [
    (Icons.medical_services_rounded, 'Medical', 'medical'),
    (Icons.local_fire_department_rounded, 'Fire', 'fire'),
    (Icons.privacy_tip_rounded, 'Theft / Intruder', 'theft'),
    (Icons.elevator_rounded, 'Stuck in lift', 'lift'),
    (Icons.pets_rounded, 'Animal threat', 'animal'),
    (Icons.warning_amber_rounded, 'Other', 'other'),
  ];

  int _type = 0;
  String? _alertId;
  bool _sending = false;

  @override
  void dispose() {
    _hold.dispose();
    super.dispose();
  }

  Future<void> _send() async {
    HapticFeedback.heavyImpact();
    setState(() => _sending = true);
    final id = await runAction(context, () => ref.read(actionsProvider).raiseSos(_types[_type].$3, ''));
    if (!mounted) return;
    setState(() {
      _sending = false;
      _alertId = id;
    });
    if (id == null) _hold.reset();
  }

  @override
  Widget build(BuildContext context) {
    final danger = context.palette.danger;
    return Scaffold(
      appBar: AppBar(title: const Text('Emergency alert')),
      body: SafeArea(
        child: Padding(padding: AppSpacing.screenAll, child: _alertId != null ? _buildSent(danger) : _buildTrigger(danger)),
      ),
    );
  }

  Widget _buildTrigger(Color danger) {
    return Column(
      children: [
        Text("What's the emergency?", style: context.text.titleMedium),
        const SizedBox(height: AppSpacing.md),
        Wrap(
          alignment: WrapAlignment.center,
          spacing: AppSpacing.sm,
          runSpacing: AppSpacing.sm,
          children: [
            for (var i = 0; i < _types.length; i++)
              ChoiceChip(
                avatar: Icon(_types[i].$1, size: 18, color: _type == i ? danger : null),
                label: Text(_types[i].$2),
                selected: _type == i,
                selectedColor: danger.withValues(alpha: 0.12),
                onSelected: (_) => setState(() => _type = i),
              ),
          ],
        ),
        const Spacer(),
        GestureDetector(
          onTapDown: (_) => _sending ? null : _hold.forward(),
          onTapUp: (_) => _hold.isCompleted ? null : _hold.reverse(),
          onTapCancel: () => _hold.isCompleted ? null : _hold.reverse(),
          child: AnimatedBuilder(
            animation: _hold,
            builder: (context, _) => Stack(
              alignment: Alignment.center,
              children: [
                Container(width: 240 + 30 * _hold.value, height: 240 + 30 * _hold.value,
                    decoration: BoxDecoration(shape: BoxShape.circle, color: danger.withValues(alpha: 0.08))),
                SizedBox(
                  width: 210,
                  height: 210,
                  child: CircularProgressIndicator(value: _sending ? null : _hold.value, strokeWidth: 8, color: danger,
                      backgroundColor: danger.withValues(alpha: 0.15)),
                ),
                Container(
                  width: 180,
                  height: 180,
                  decoration: BoxDecoration(shape: BoxShape.circle, color: danger,
                      boxShadow: [BoxShadow(color: danger.withValues(alpha: 0.4), blurRadius: 30, offset: const Offset(0, 10))]),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.sos_rounded, color: Colors.white, size: 56),
                      Text(_sending ? 'SENDING…' : 'HOLD 3 SEC', style: context.text.labelMedium?.copyWith(color: Colors.white)),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),
        const Spacer(),
        Text('Security, your household and the community team are notified instantly with your unit.',
            textAlign: TextAlign.center, style: context.text.bodySmall),
        const SizedBox(height: AppSpacing.lg),
        OutlinedButton.icon(
          onPressed: () => context.push(Routes.emergencyContacts),
          icon: const Icon(Icons.contact_phone_outlined),
          label: const Text('Emergency contacts'),
        ),
      ],
    );
  }

  Widget _buildSent(Color danger) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        const Spacer(),
        Center(
          child: Container(
            width: 120,
            height: 120,
            decoration: BoxDecoration(shape: BoxShape.circle, color: danger.withValues(alpha: 0.12)),
            child: Icon(Icons.notifications_active_rounded, size: 60, color: danger),
          ),
        ),
        const SizedBox(height: AppSpacing.xl),
        Text('Alert sent', style: context.text.headlineSmall, textAlign: TextAlign.center),
        const SizedBox(height: AppSpacing.sm),
        Text('${_types[_type].$2} alert sent to the security control room. Stay where you are if it is safe.',
            style: context.text.bodyMedium?.copyWith(color: context.palette.textMuted), textAlign: TextAlign.center),
        const Spacer(),
        FilledButton.icon(
          style: FilledButton.styleFrom(backgroundColor: context.palette.success),
          onPressed: () {
            final phone = ref.read(contextProvider).value?.emergencyPhone;
            phone == null ? context.push(Routes.emergencyContacts) : Device.call(context, phone);
          },
          icon: const Icon(Icons.call_rounded),
          label: const Text('Call security'),
        ),
        const SizedBox(height: AppSpacing.md),
        OutlinedButton(
          onPressed: () async {
            final ok = await runAction(context, () async {
              await ref.read(actionsProvider).cancelSos(_alertId!);
              return true;
            }, success: 'Alert cancelled');
            if (ok == true && mounted) context.pop();
          },
          child: const Text("Cancel alert — I'm safe"),
        ),
      ],
    );
  }
}
