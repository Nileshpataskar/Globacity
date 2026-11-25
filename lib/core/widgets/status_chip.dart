import 'package:flutter/material.dart';

import '../theme/app_spacing.dart';
import '../utils/context_ext.dart';

enum Tone { primary, success, warning, danger, info, neutral }

extension ToneColor on Tone {
  Color resolve(BuildContext context) => switch (this) {
        Tone.primary => context.scheme.primary,
        Tone.success => context.palette.success,
        Tone.warning => context.palette.warning,
        Tone.danger => context.palette.danger,
        Tone.info => context.palette.info,
        Tone.neutral => context.palette.textMuted,
      };
}

/// Small pill showing a status such as "Approved" or "Overdue".
class StatusChip extends StatelessWidget {
  const StatusChip({super.key, required this.label, this.tone = Tone.neutral, this.icon});

  final String label;
  final Tone tone;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final c = tone.resolve(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm + 2, vertical: AppSpacing.xs),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(AppRadius.pill),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 13, color: c),
            const SizedBox(width: AppSpacing.xs),
          ],
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelSmall?.copyWith(color: c, letterSpacing: 0.2),
            ),
          ),
        ],
      ),
    );
  }
}
