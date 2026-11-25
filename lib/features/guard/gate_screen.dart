import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';
import 'package:mobile_scanner/mobile_scanner.dart';

import '../../app/router.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/widgets/widgets.dart';
import '../../data/guard.dart';

/// Gate console: verify a 6-digit code (typed or scanned), admit, raise walk-ins, open IoT gates.
class GateScreen extends ConsumerStatefulWidget {
  const GateScreen({super.key, this.initialCode});

  final String? initialCode;

  @override
  ConsumerState<GateScreen> createState() => _GateScreenState();
}

class _GateScreenState extends ConsumerState<GateScreen> {
  final _code = TextEditingController();
  CodeLookup? _result;
  String? _error;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    if (widget.initialCode != null) {
      _code.text = widget.initialCode!;
      WidgetsBinding.instance.addPostFrameCallback((_) => _verify());
    }
  }

  @override
  void dispose() {
    _code.dispose();
    super.dispose();
  }

  Future<void> _verify() async {
    if (_code.text.length != 6) return;
    setState(() {
      _busy = true;
      _error = null;
      _result = null;
    });
    try {
      final r = await ref.read(guardActionsProvider).verify(_code.text);
      if (mounted) setState(() => _result = r);
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _admit() async {
    final gateId = ref.read(guardContextProvider).value?.shift?.gateId;
    setState(() => _busy = true);
    final msg = await runAction(context, () => ref.read(guardActionsProvider).checkIn(_code.text, gateId: gateId));
    if (!mounted) return;
    setState(() => _busy = false);
    if (msg != null) {
      HapticFeedback.mediumImpact();
      context.showSnack(msg);
      setState(() {
        _result = null;
        _code.clear();
      });
    }
  }

  Future<void> _scan() async {
    final code = await context.push<String>(Routes.guardScan);
    if (code != null && mounted) {
      _code.text = code;
      await _verify();
    }
  }

  @override
  Widget build(BuildContext context) {
    final gates = ref.watch(guardContextProvider).value?.gates ?? [];
    return Scaffold(
      appBar: AppBar(title: const Text('Gate')),
      body: ListView(
        padding: AppSpacing.screenAll,
        children: [
          AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Text('Verify entry code', style: context.text.titleMedium),
                const SizedBox(height: AppSpacing.xs),
                Text('Visitor pass, frequent entry or daily help code', style: context.text.bodySmall),
                const SizedBox(height: AppSpacing.lg),
                TextField(
                  controller: _code,
                  keyboardType: TextInputType.number,
                  textAlign: TextAlign.center,
                  inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(6)],
                  style: context.text.headlineMedium?.copyWith(letterSpacing: 10),
                  decoration: const InputDecoration(hintText: '••••••', counterText: ''),
                  onChanged: (v) {
                    if (v.length == 6) _verify();
                  },
                ),
                const SizedBox(height: AppSpacing.md),
                Row(
                  children: [
                    Expanded(
                      child: OutlinedButton.icon(
                        onPressed: _busy ? null : _scan,
                        icon: const Icon(Icons.qr_code_scanner_rounded),
                        label: const Text('Scan QR'),
                      ),
                    ),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(
                      child: FilledButton(onPressed: _busy || _code.text.length != 6 ? null : _verify, child: const Text('Verify')),
                    ),
                  ],
                ),
              ],
            ),
          ),
          if (_busy) const Padding(padding: EdgeInsets.all(AppSpacing.lg), child: Center(child: CircularProgressIndicator())),
          if (_error != null) ...[
            const SizedBox(height: AppSpacing.lg),
            AppCard(
              color: context.palette.danger.withValues(alpha: 0.08),
              borderColor: context.palette.danger.withValues(alpha: 0.4),
              child: Row(
                children: [
                  Icon(Icons.gpp_bad_rounded, color: context.palette.danger, size: 32),
                  const SizedBox(width: AppSpacing.md),
                  Expanded(child: Text(_error!, style: context.text.titleSmall)),
                ],
              ),
            ),
          ],
          if (_result != null) ...[
            const SizedBox(height: AppSpacing.lg),
            _ResultCard(result: _result!, onAdmit: _busy ? null : _admit),
          ],
          const SizedBox(height: AppSpacing.lg),
          OutlinedButton.icon(
            onPressed: () => context.push(Routes.guardWalkIn),
            icon: const Icon(Icons.person_add_alt_rounded),
            label: const Text('Visitor without a pass (walk-in)'),
          ),
          if (gates.any((g) => g.iotEnabled)) ...[
            const SectionHeader(title: 'Boom barriers'),
            for (final g in gates.where((g) => g.iotEnabled)) ...[
              AppCard(
                child: Row(
                  children: [
                    IconBadge(icon: Icons.sensor_door_rounded, color: context.palette.success),
                    const SizedBox(width: AppSpacing.md),
                    Expanded(child: Text(g.name, style: context.text.titleSmall)),
                    FilledButton.tonal(
                      onPressed: () => runAction(context, () => ref.read(guardActionsProvider).openGate(g.id))
                          .then((msg) => msg != null && context.mounted ? context.showSnack(msg) : null),
                      child: const Text('Open'),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: AppSpacing.sm),
            ],
          ],
        ],
      ),
    );
  }
}

class _ResultCard extends StatelessWidget {
  const _ResultCard({required this.result, required this.onAdmit});

  final CodeLookup result;
  final VoidCallback? onAdmit;

  @override
  Widget build(BuildContext context) {
    final r = result;
    final c = r.allowed ? context.palette.success : context.palette.danger;
    return AppCard(
      color: c.withValues(alpha: 0.06),
      borderColor: c.withValues(alpha: 0.5),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(r.allowed ? Icons.verified_rounded : Icons.block_rounded, color: c, size: 36),
              const SizedBox(width: AppSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(r.kindLabel.toUpperCase(), style: context.text.labelSmall?.copyWith(color: c)),
                    Text(r.name, style: context.text.titleLarge),
                    Text(r.detail, style: context.text.bodySmall),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: AppSpacing.md),
          InfoRow(icon: Icons.apartment_rounded, label: r.units.length > 1 ? 'Units' : 'Unit', value: r.units.join(', ')),
          if (!r.allowed) InfoRow(icon: Icons.info_outline_rounded, label: 'Not allowed', value: r.reason),
          const SizedBox(height: AppSpacing.md),
          if (r.allowed)
            FilledButton.icon(
              style: FilledButton.styleFrom(backgroundColor: context.palette.success),
              onPressed: onAdmit,
              icon: const Icon(Icons.login_rounded),
              label: const Text('Allow entry'),
            ),
        ],
      ),
    );
  }
}

/// Camera QR scanner. Pops with the 6-digit code.
class ScanScreen extends StatefulWidget {
  const ScanScreen({super.key});

  @override
  State<ScanScreen> createState() => _ScanScreenState();
}

class _ScanScreenState extends State<ScanScreen> {
  bool _done = false;

  void _onDetect(BarcodeCapture capture) {
    if (_done) return;
    for (final b in capture.barcodes) {
      final match = RegExp(r'\d{6}').firstMatch(b.rawValue ?? '');
      if (match != null) {
        _done = true;
        HapticFeedback.mediumImpact();
        context.pop(match.group(0));
        return;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(backgroundColor: Colors.black, foregroundColor: Colors.white, title: const Text('Scan visitor pass')),
      body: Stack(
        alignment: Alignment.center,
        children: [
          MobileScanner(
            onDetect: _onDetect,
            errorBuilder: (context, error) => Center(
              child: Padding(
                padding: const EdgeInsets.all(AppSpacing.xl),
                child: Text('Camera unavailable: ${error.errorCode.name}. Type the code instead.',
                    textAlign: TextAlign.center, style: const TextStyle(color: Colors.white)),
              ),
            ),
          ),
          IgnorePointer(
            child: Container(
              width: 240,
              height: 240,
              decoration: BoxDecoration(border: Border.all(color: Colors.white, width: 3), borderRadius: BorderRadius.circular(24)),
            ),
          ),
          const Positioned(
            bottom: 48,
            child: Text('Point the camera at the QR code', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
  }
}
