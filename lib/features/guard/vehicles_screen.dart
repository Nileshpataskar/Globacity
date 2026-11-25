import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/guard.dart';

/// Vehicle entry / exit. Resident vehicles are recognised from the plate.
class VehiclesScreen extends ConsumerStatefulWidget {
  const VehiclesScreen({super.key});

  @override
  ConsumerState<VehiclesScreen> createState() => _VehiclesScreenState();
}

class _VehiclesScreenState extends ConsumerState<VehiclesScreen> {
  final _plate = TextEditingController();
  final _note = TextEditingController();
  String _direction = 'in';
  ({bool registered, String? unit, String? model})? _lookup;
  bool _busy = false;

  @override
  void dispose() {
    _plate.dispose();
    _note.dispose();
    super.dispose();
  }

  Future<void> _check() async {
    if (_plate.text.trim().length < 3) return;
    final r = await runAction(context, () => ref.read(guardActionsProvider).lookupVehicle(_plate.text.trim()));
    if (mounted) setState(() => _lookup = r);
  }

  Future<void> _log() async {
    if (_plate.text.trim().isEmpty) return;
    setState(() => _busy = true);
    final gateId = ref.read(guardContextProvider).value?.shift?.gateId;
    final entry = await runAction(context,
        () => ref.read(guardActionsProvider).logVehicle(_plate.text.trim(), _direction, gateId: gateId, note: _note.text.trim()));
    if (!mounted) return;
    setState(() => _busy = false);
    if (entry != null) {
      context.showSnack('${entry.number} logged ${entry.direction}${entry.unitLabel != null ? ' · ${entry.unitLabel}' : ''}');
      _plate.clear();
      _note.clear();
      setState(() => _lookup = null);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vehicle entry')),
      body: RefreshIndicator(
        onRefresh: () => ref.refresh(guardVehiclesProvider.future),
        child: ListView(
          padding: AppSpacing.screenAll,
          children: [
            AppCard(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  SegmentedButton<String>(
                    segments: const [
                      ButtonSegment(value: 'in', label: Text('Entry'), icon: Icon(Icons.login_rounded)),
                      ButtonSegment(value: 'out', label: Text('Exit'), icon: Icon(Icons.logout_rounded)),
                    ],
                    selected: {_direction},
                    onSelectionChanged: (s) => setState(() => _direction = s.first),
                  ),
                  const SizedBox(height: AppSpacing.md),
                  TextField(
                    controller: _plate,
                    textCapitalization: TextCapitalization.characters,
                    onChanged: (_) => setState(() => _lookup = null),
                    onSubmitted: (_) => _check(),
                    decoration: InputDecoration(
                      labelText: 'Plate number',
                      prefixIcon: const Icon(Icons.directions_car_outlined),
                      suffixIcon: IconButton(onPressed: _check, icon: const Icon(Icons.search_rounded)),
                    ),
                  ),
                  if (_lookup != null) ...[
                    const SizedBox(height: AppSpacing.sm),
                    Row(
                      children: [
                        Flexible(
                          child: StatusChip(
                            label: _lookup!.registered ? 'Resident · ${_lookup!.unit}' : 'Not registered: visitor vehicle',
                            tone: _lookup!.registered ? Tone.success : Tone.warning,
                            icon: _lookup!.registered ? Icons.verified_rounded : Icons.help_outline_rounded,
                          ),
                        ),
                      ],
                    ),
                  ],
                  const SizedBox(height: AppSpacing.md),
                  TextField(controller: _note, decoration: const InputDecoration(labelText: 'Note (optional)')),
                  const SizedBox(height: AppSpacing.md),
                  FilledButton(onPressed: _busy ? null : _log, child: Text(_direction == 'in' ? 'Log entry' : 'Log exit')),
                ],
              ),
            ),
            const SectionHeader(title: 'Recent'),
            AsyncView<List<VehicleLogEntry>>(
              value: ref.watch(guardVehiclesProvider),
              compact: true,
              onRetry: () => ref.invalidate(guardVehiclesProvider),
              data: (logs) => logs.isEmpty
                  ? AppCard(child: Text('No vehicles logged yet.', style: context.text.bodySmall))
                  : Column(
                      children: [
                        for (final l in logs.take(50)) ...[
                          AppCard(
                            padding: const EdgeInsets.symmetric(horizontal: AppSpacing.md, vertical: AppSpacing.md),
                            child: Row(
                              children: [
                                IconBadge(
                                  icon: l.direction == 'in' ? Icons.login_rounded : Icons.logout_rounded,
                                  color: l.direction == 'in' ? context.palette.success : context.palette.textMuted,
                                  size: 40,
                                ),
                                const SizedBox(width: AppSpacing.md),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Text(l.number, style: context.text.titleSmall),
                                      Text([l.unitLabel ?? 'Visitor', if (l.gateName != null) l.gateName!, if (l.note.isNotEmpty) l.note].join(' · '),
                                          style: context.text.bodySmall),
                                    ],
                                  ),
                                ),
                                Text(Fmt.time(l.time), style: context.text.labelMedium),
                              ],
                            ),
                          ),
                          const SizedBox(height: AppSpacing.sm),
                        ],
                      ],
                    ),
            ),
          ],
        ),
      ),
    );
  }
}
