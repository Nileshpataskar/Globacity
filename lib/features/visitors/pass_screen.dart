import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:qr_flutter/qr_flutter.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/utils/device.dart';
import '../../core/utils/formatters.dart';
import '../../core/widgets/widgets.dart';
import '../../data/models.dart';
import '../../data/providers.dart';

/// Gate pass: QR code + numeric code the guard verifies at the gate.
class PassScreen extends ConsumerWidget {
  const PassScreen({super.key, required this.visitorId});

  final String visitorId;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final property = ref.watch(currentPropertyProvider).value;
    return Scaffold(
      appBar: AppBar(title: const Text('Gate pass')),
      body: AsyncView<Visitor>(
        value: ref.watch(visitorProvider(visitorId)),
        onRetry: () => ref.invalidate(visitorProvider(visitorId)),
        data: (v) => ListView(
          padding: AppSpacing.screenAll,
          children: [
            AppCard(
              padding: EdgeInsets.zero,
              child: Column(
                children: [
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(AppSpacing.lg),
                    decoration: BoxDecoration(gradient: LinearGradient(colors: context.palette.heroGradient)),
                    child: Column(
                      children: [
                        Text(property?.community ?? '', style: context.text.titleMedium?.copyWith(color: Colors.white)),
                        const SizedBox(height: 2),
                        Text('Invited by ${v.unitLabel}', style: context.text.bodySmall?.copyWith(color: Colors.white70)),
                      ],
                    ),
                  ),
                  Padding(
                    padding: const EdgeInsets.all(AppSpacing.xl),
                    child: Column(
                      children: [
                        Text(v.name, style: context.text.titleLarge, textAlign: TextAlign.center),
                        const SizedBox(height: AppSpacing.xs),
                        StatusChip(label: v.status == VisitorStatus.expected ? v.type.label : v.status.label,
                            icon: v.type.icon, tone: v.status == VisitorStatus.expected ? Tone.primary : v.status.tone),
                        if (v.passCode.isNotEmpty) ...[
                          const SizedBox(height: AppSpacing.xl),
                          Container(
                            padding: const EdgeInsets.all(AppSpacing.md),
                            decoration: BoxDecoration(color: Colors.white, borderRadius: AppRadius.fieldRadius,
                                border: Border.all(color: context.palette.border)),
                            child: QrImageView(data: v.passCode, size: 200, backgroundColor: Colors.white),
                          ),
                          const SizedBox(height: AppSpacing.lg),
                          Text('Entry code', style: context.text.bodySmall),
                          const SizedBox(height: AppSpacing.xs),
                          GestureDetector(
                            onTap: () {
                              Clipboard.setData(ClipboardData(text: v.passCode));
                              context.showSnack('Code copied');
                            },
                            child: Text('${v.passCode.substring(0, 3)} ${v.passCode.substring(3)}',
                                style: context.text.headlineMedium?.copyWith(letterSpacing: 4, color: context.scheme.primary)),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const Divider(),
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.sm),
                    child: Column(
                      children: [
                        InfoRow(icon: Icons.calendar_today_rounded, label: 'Expected', value: Fmt.dateTime(v.time)),
                        if (v.validUntil != null)
                          InfoRow(icon: Icons.timer_outlined, label: 'Valid until', value: Fmt.dateTime(v.validUntil!)),
                        if (v.guests > 1) InfoRow(icon: Icons.groups_outlined, label: 'Guests', value: '${v.guests}'),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: AppSpacing.lg),
            Text('Share this QR code or entry code with your visitor. The guard scans or types it at the gate.',
                textAlign: TextAlign.center, style: context.text.bodySmall),
            const SizedBox(height: AppSpacing.xl),
            FilledButton.icon(
              onPressed: () => Device.share(
                context,
                'Hi ${v.name}, your entry code for ${property?.community ?? 'our community'} '
                '(${v.unitLabel}) is ${v.passCode}. Show it at the gate. '
                'Valid until ${v.validUntil == null ? '-' : Fmt.dateTime(v.validUntil!)}.',
                subject: 'Gate pass',
              ),
              icon: const Icon(Icons.share_rounded),
              label: const Text('Share pass'),
            ),
          ],
        ),
      ),
    );
  }
}
