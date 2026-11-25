import 'package:flutter/material.dart';

import 'brand.dart';

import '../theme/app_spacing.dart';
import '../utils/context_ext.dart';

/// Bordered surface used for nearly every grouped block in the app.
class AppCard extends StatelessWidget {
  const AppCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(AppSpacing.lg),
    this.onTap,
    this.color,
    this.borderColor,
  });

  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  final Color? borderColor;

  @override
  Widget build(BuildContext context) {
    final dark = context.theme.brightness == Brightness.dark;
    return Pressable(
      enabled: onTap != null,
      child: DecoratedBox(
        decoration: BoxDecoration(
          borderRadius: AppRadius.cardRadius,
          boxShadow: dark || color != null
              ? null
              : [BoxShadow(color: const Color(0xFF101828).withValues(alpha: 0.05), blurRadius: 18, offset: const Offset(0, 6))],
        ),
        child: Material(
          color: color ?? context.scheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: AppRadius.cardRadius,
            side: BorderSide(color: borderColor ?? context.palette.border.withValues(alpha: dark ? 1 : 0.7)),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: onTap,
            child: Padding(padding: padding, child: child),
          ),
        ),
      ),
    );
  }
}

/// Rounded square with a tinted background holding an icon.
class IconBadge extends StatelessWidget {
  const IconBadge({super.key, required this.icon, this.color, this.size = 44});

  final IconData icon;
  final Color? color;
  final double size;

  @override
  Widget build(BuildContext context) {
    final c = color ?? context.scheme.primary;
    return Container(
      width: size,
      height: size,
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(size * 0.3),
      ),
      child: Icon(icon, color: c, size: size * 0.5),
    );
  }
}

/// Icon + label + value row used in detail screens.
class InfoRow extends StatelessWidget {
  const InfoRow({super.key, required this.icon, required this.label, required this.value});

  final IconData icon;
  final String label;
  final String value;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
      child: Row(
        children: [
          Icon(icon, size: 20, color: context.palette.textMuted),
          const SizedBox(width: AppSpacing.md),
          Text(label, style: context.text.bodyMedium?.copyWith(color: context.palette.textMuted)),
          const SizedBox(width: AppSpacing.md),
          Expanded(
            child: Text(value, textAlign: TextAlign.end, style: context.text.titleSmall),
          ),
        ],
      ),
    );
  }
}
