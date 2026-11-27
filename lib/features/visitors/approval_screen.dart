import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/gate_alerts.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/device.dart';
import '../../core/widgets/widgets.dart';
import '../../data/actions.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Incoming entry request from the gate, styled like an incoming call: allow, decline or leave at gate.
class ApprovalScreen extends ConsumerStatefulWidget {
  const ApprovalScreen({super.key, required this.visitorId});

  final String visitorId;

  @override
  ConsumerState<ApprovalScreen> createState() => _ApprovalScreenState();
}

class _ApprovalScreenState extends ConsumerState<ApprovalScreen> {
  bool _busy = false;
  String? _done; // result message once answered
  Timer? _ring;
  int _seconds = 0;

  static const _green = Color(0xFF22C55E);
  static const _red = Color(0xFFEF4444);

  @override
  void initState() {
    super.initState();
    // Vibrate like a ringing phone until answered (max ~1 minute).
    _ring = Timer.periodic(const Duration(seconds: 1), (t) {
      if (!mounted) return;
      setState(() => _seconds++);
      if (_done == null && _seconds % 2 == 0 && _seconds < 60) HapticFeedback.heavyImpact();
    });
    HapticFeedback.heavyImpact();
  }

  @override
  void dispose() {
    _ring?.cancel();
    super.dispose();
  }

  Future<void> _respond(String action, String message) async {
    HapticFeedback.mediumImpact();
    setState(() => _busy = true);
    try {
      await ref.read(actionsProvider).visitorAction(widget.visitorId, action);
      GateAlerts.dismiss(widget.visitorId);
      _ring?.cancel();
      if (!mounted) return;
      setState(() => _done = message);
      await Future<void>.delayed(const Duration(milliseconds: 1400));
      if (mounted && context.canPop()) context.pop();
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      context.showSnack(e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    final provider = visitorProvider(widget.visitorId);
    final visitor = ref.watch(provider);
    return Scaffold(
      body: BrandBackdrop(
        child: SafeArea(
          child: visitor.when(
            loading: () => const Center(child: BrandLoader(size: 64)),
            error: (e, _) => _Message(
              icon: Icons.cloud_off_rounded,
              text: 'Could not load this request.\n$e',
              action: 'Retry',
              onAction: () => ref.invalidate(provider),
            ),
            data: (v) {
              if (_done != null) return _Message(icon: Icons.check_circle_rounded, text: _done!, color: _green);
              if (v.status != VisitorStatus.waiting) {
                GateAlerts.dismiss(v.id);
                return _Message(
                  icon: Icons.info_outline_rounded,
                  text: 'Already handled: ${v.name} is ${v.status.label.toLowerCase()}.',
                );
              }
              return _call(context, v);
            },
          ),
        ),
      ),
    );
  }

  Widget _call(BuildContext context, Visitor v) {
    final waiting = '${_seconds ~/ 60}:${(_seconds % 60).toString().padLeft(2, '0')}';
    return Column(
      children: [
        Align(
          alignment: Alignment.centerLeft,
          child: IconButton(
            onPressed: () => context.pop(),
            icon: const Icon(Icons.keyboard_arrow_down_rounded, color: Colors.white, size: 30),
            tooltip: 'Decide later',
          ),
        ),
        const SizedBox(height: AppSpacing.md),
        Text('VISITOR AT THE GATE', style: context.text.labelMedium?.copyWith(color: Colors.white60, letterSpacing: 2)),
        const SizedBox(height: AppSpacing.xs),
        Text('Waiting $waiting', style: context.text.bodySmall?.copyWith(color: Colors.white54)),
        const Spacer(),
        _Rings(child: _Avatar(visitor: v)),
        const SizedBox(height: AppSpacing.xl),
        Text(v.name, textAlign: TextAlign.center, style: context.text.headlineMedium?.copyWith(color: Colors.white))
            .animate()
            .fadeIn(duration: 400.ms),
        const SizedBox(height: AppSpacing.xs),
        Text(
          [v.type.label, if (v.company != null && v.company!.isNotEmpty) v.company!].join(' · '),
          style: context.text.bodyLarge?.copyWith(color: Colors.white70),
        ),
        const SizedBox(height: AppSpacing.sm),
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(color: Colors.white.withValues(alpha: 0.1), borderRadius: BorderRadius.circular(99)),
          child: Row(mainAxisSize: MainAxisSize.min, children: [
            const Icon(Icons.door_sliding_rounded, size: 16, color: Colors.white70),
            const SizedBox(width: 6),
            Text('At ${v.gate} · for ${v.unitLabel}', style: context.text.labelMedium?.copyWith(color: Colors.white)),
          ]),
        ),
        if (v.phone != null || v.vehicleNo != null) ...[
          const SizedBox(height: AppSpacing.md),
          Wrap(spacing: AppSpacing.sm, children: [
            if (v.phone != null)
              TextButton.icon(
                onPressed: () => Device.call(context, v.phone!),
                style: TextButton.styleFrom(foregroundColor: Colors.white),
                icon: const Icon(Icons.call_rounded, size: 18),
                label: Text('Call ${v.phone}'),
              ),
            if (v.vehicleNo != null)
              Chip(
                avatar: const Icon(Icons.directions_car_rounded, size: 16),
                label: Text(v.vehicleNo!),
                visualDensity: VisualDensity.compact,
              ),
          ]),
        ],
        const Spacer(),
        if (v.type == VisitorType.delivery)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.xl),
            child: OutlinedButton.icon(
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white,
                side: BorderSide(color: Colors.white.withValues(alpha: 0.35)),
                minimumSize: const Size.fromHeight(50),
                shape: const StadiumBorder(),
              ),
              onPressed: _busy ? null : () => _respond('leave-at-gate', 'Got it. The delivery will be left at the gate.'),
              icon: const Icon(Icons.inventory_2_rounded),
              label: const Text('Leave it at the gate'),
            ),
          ),
        const SizedBox(height: AppSpacing.xl),
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceEvenly,
          children: [
            _RoundAction(
              color: _red,
              icon: Icons.close_rounded,
              label: 'Decline',
              onTap: _busy ? null : () => _respond('deny', 'Declined. The guard won\'t let ${v.name} in.'),
            ),
            _RoundAction(
              color: _green,
              icon: Icons.check_rounded,
              label: 'Allow',
              pulse: true,
              onTap: _busy ? null : () => _respond('approve', 'Allowed. ${v.name} can come in.'),
            ),
          ],
        ),
        const SizedBox(height: AppSpacing.xxl),
      ],
    );
  }
}

class _Avatar extends StatelessWidget {
  const _Avatar({required this.visitor});

  final Visitor visitor;

  @override
  Widget build(BuildContext context) {
    final photo = visitor.photoUrl;
    return Container(
      width: 128,
      height: 128,
      decoration: BoxDecoration(
        shape: BoxShape.circle,
        border: Border.all(color: Colors.white, width: 3),
        color: Colors.white.withValues(alpha: 0.12),
      ),
      clipBehavior: Clip.antiAlias,
      child: photo != null
          ? Image.network(photo, fit: BoxFit.cover,
              errorBuilder: (_, _, _) => Icon(visitor.type.icon, color: Colors.white, size: 56))
          : Center(child: Icon(visitor.type.icon, color: Colors.white, size: 56)),
    );
  }
}

/// Expanding rings behind the avatar, like a ringing phone.
class _Rings extends StatelessWidget {
  const _Rings({required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) {
    Widget ring(int i) => Container(
          width: 128,
          height: 128,
          decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: const Color(0xFF38BDF8), width: 2)),
        )
            .animate(onPlay: (c) => c.repeat(), delay: (i * 600).ms)
            .scaleXY(begin: 1, end: 2.1, duration: 1800.ms, curve: Curves.easeOut)
            .fadeOut(begin: 0.7, duration: 1800.ms);
    return SizedBox(
      width: 270,
      height: 270,
      child: Stack(alignment: Alignment.center, children: [ring(0), ring(1), ring(2), child]),
    );
  }
}

class _RoundAction extends StatelessWidget {
  const _RoundAction({required this.color, required this.icon, required this.label, this.onTap, this.pulse = false});

  final Color color;
  final IconData icon;
  final String label;
  final VoidCallback? onTap;
  final bool pulse;

  @override
  Widget build(BuildContext context) {
    Widget button = Material(
      color: color,
      shape: const CircleBorder(),
      elevation: 0,
      child: InkWell(
        customBorder: const CircleBorder(),
        onTap: onTap,
        child: SizedBox(width: 76, height: 76, child: Icon(icon, color: Colors.white, size: 36)),
      ),
    );
    if (pulse && onTap != null) {
      button = button.animate(onPlay: (c) => c.repeat(reverse: true)).scaleXY(begin: 1, end: 1.08, duration: 700.ms);
    }
    return Column(children: [
      DecoratedBox(
        decoration: BoxDecoration(shape: BoxShape.circle, boxShadow: [
          BoxShadow(color: color.withValues(alpha: 0.45), blurRadius: 24, offset: const Offset(0, 8)),
        ]),
        child: Opacity(opacity: onTap == null ? 0.5 : 1, child: button),
      ),
      const SizedBox(height: AppSpacing.sm),
      Text(label, style: context.text.titleSmall?.copyWith(color: Colors.white)),
    ]);
  }
}

class _Message extends StatelessWidget {
  const _Message({required this.icon, required this.text, this.color = Colors.white, this.action, this.onAction});

  final IconData icon;
  final String text;
  final Color color;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.xl),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, color: color, size: 72).animate().scaleXY(begin: 0.5, end: 1, duration: 500.ms, curve: Curves.elasticOut),
            const SizedBox(height: AppSpacing.lg),
            Text(text, textAlign: TextAlign.center, style: context.text.titleMedium?.copyWith(color: Colors.white)),
            const SizedBox(height: AppSpacing.xl),
            if (action != null)
              FilledButton.tonal(onPressed: onAction, child: Text(action!))
            else
              TextButton(
                onPressed: () => context.canPop() ? context.pop() : null,
                style: TextButton.styleFrom(foregroundColor: Colors.white70),
                child: const Text('Close'),
              ),
          ]),
        ),
      );
}
