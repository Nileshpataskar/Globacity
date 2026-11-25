import 'package:flutter/material.dart';

import 'brand.dart';

import '../config/app_config.dart';
import '../theme/app_spacing.dart';
import '../utils/context_ext.dart';
import 'app_card.dart';

/// Title row above a content section, with an optional "See all" action.
class SectionHeader extends StatelessWidget {
  const SectionHeader({super.key, required this.title, this.action, this.onAction});

  final String title;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: AppSpacing.xl, bottom: AppSpacing.md),
      child: Row(
        children: [
          Expanded(child: Text(title, style: context.text.titleMedium)),
          if (action != null)
            GestureDetector(
              onTap: onAction,
              child: Text(action!, style: context.text.labelLarge?.copyWith(color: context.scheme.primary, fontSize: 13.5)),
            ),
        ],
      ),
    );
  }
}

/// Placeholder shown when a list has no items.
class EmptyState extends StatelessWidget {
  const EmptyState({super.key, required this.icon, required this.title, this.message, this.action, this.onAction});

  final IconData icon;
  final String title;
  final String? message;
  final String? action;
  final VoidCallback? onAction;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(AppSpacing.xxl),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(icon: icon, size: 72).pop(),
            const SizedBox(height: AppSpacing.lg),
            Text(title, style: context.text.titleMedium, textAlign: TextAlign.center).enter(1, 0.3),
            if (message != null) ...[
              const SizedBox(height: AppSpacing.xs),
              Text(message!, style: context.text.bodySmall, textAlign: TextAlign.center),
            ],
            if (action != null) ...[
              const SizedBox(height: AppSpacing.lg),
              FilledButton.tonal(onPressed: onAction, child: Text(action!)),
            ],
          ],
        ),
      ),
    );
  }
}

/// Square shortcut used in quick-action grids.
class ActionTile extends StatelessWidget {
  const ActionTile({super.key, required this.icon, required this.label, required this.onTap, this.color});

  final IconData icon;
  final String label;
  final VoidCallback onTap;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return Pressable(
      child: InkWell(
      onTap: onTap,
      borderRadius: AppRadius.fieldRadius,
      child: Padding(
        padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            IconBadge(icon: icon, color: color, size: 52),
            const SizedBox(height: AppSpacing.sm),
            Text(
              label,
              maxLines: 2,
              textAlign: TextAlign.center,
              overflow: TextOverflow.ellipsis,
              style: context.text.labelMedium?.copyWith(color: context.scheme.onSurface, height: 1.2),
            ),
          ],
        ),
      ),
      ),
    );
  }
}

/// Label above a form input.
class LabeledField extends StatelessWidget {
  const LabeledField({super.key, required this.label, required this.child});

  final String label;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: AppSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(label, style: context.text.labelMedium?.copyWith(color: context.scheme.onSurface)),
          const SizedBox(height: AppSpacing.sm),
          child,
        ],
      ),
    );
  }
}

/// Brand mark built from [AppConfig].
class AppLogo extends StatelessWidget {
  const AppLogo({super.key, this.size = 72, this.inverted = false});

  final double size;
  final bool inverted;

  /// [inverted] = shown on a dark background (adds a soft glow).
  @override
  Widget build(BuildContext context) => BrandMark(size: size, glow: inverted);
}

/// Five-star display/input.
class RatingStars extends StatelessWidget {
  const RatingStars({super.key, required this.rating, this.size = 16, this.onChanged});

  final double rating;
  final double size;
  final ValueChanged<int>? onChanged;

  @override
  Widget build(BuildContext context) {
    const amber = Color(0xFFF59E0B);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: List.generate(5, (i) {
        final icon = rating >= i + 1
            ? Icons.star_rounded
            : rating > i
                ? Icons.star_half_rounded
                : Icons.star_outline_rounded;
        final star = Icon(icon, size: size, color: amber);
        if (onChanged == null) return star;
        return GestureDetector(
          onTap: () => onChanged!(i + 1),
          child: Padding(padding: const EdgeInsets.all(AppSpacing.xs), child: star),
        );
      }),
    );
  }
}

/// Shows a themed modal bottom sheet with a title and scrollable body.
Future<T?> showAppSheet<T>(BuildContext context, {required String title, required Widget child}) {
  return showModalBottomSheet<T>(
    context: context,
    isScrollControlled: true,
    useSafeArea: true,
    builder: (ctx) => Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(ctx).bottom),
      child: SingleChildScrollView(
        padding: const EdgeInsets.fromLTRB(AppSpacing.lg, 0, AppSpacing.lg, AppSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(title, style: ctx.text.titleLarge),
            const SizedBox(height: AppSpacing.lg),
            child,
          ],
        ),
      ),
    ),
  );
}

/// Group of list tiles inside a card, separated by dividers.
class TileGroup extends StatelessWidget {
  const TileGroup({super.key, required this.children, this.title});

  final List<Widget> children;
  final String? title;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (title != null)
          Padding(
            padding: const EdgeInsets.fromLTRB(AppSpacing.xs, AppSpacing.xl, 0, AppSpacing.sm),
            child: Text(title!.toUpperCase(), style: context.text.labelSmall),
          ),
        AppCard(
          padding: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < children.length; i++) ...[
                if (i > 0) const Divider(indent: AppSpacing.lg, endIndent: AppSpacing.lg),
                children[i],
              ],
            ],
          ),
        ),
      ],
    );
  }
}

/// Settings / menu row with a tinted leading icon.
class MenuTile extends StatelessWidget {
  const MenuTile({super.key, required this.icon, required this.title, this.subtitle, this.onTap, this.trailing, this.color});

  final IconData icon;
  final String title;
  final String? subtitle;
  final VoidCallback? onTap;
  final Widget? trailing;
  final Color? color;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.xxs),
      leading: IconBadge(icon: icon, color: color, size: 38),
      title: Text(title),
      subtitle: subtitle != null ? Text(subtitle!) : null,
      trailing: trailing ?? Icon(Icons.chevron_right_rounded, color: context.palette.textMuted),
    );
  }
}

/// Text input bar pinned to the bottom of chat-like screens.
class MessageComposer extends StatelessWidget {
  const MessageComposer({super.key, required this.controller, required this.hint, required this.onSend});

  final TextEditingController controller;
  final String hint;
  final VoidCallback onSend;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(color: context.scheme.surface, border: Border(top: BorderSide(color: context.palette.border))),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.all(AppSpacing.sm),
          child: Row(
            children: [
              Expanded(
                child: TextField(
                  controller: controller,
                  onSubmitted: (_) => onSend(),
                  decoration: InputDecoration(hintText: hint, isDense: true),
                ),
              ),
              const SizedBox(width: AppSpacing.sm),
              IconButton.filled(onPressed: onSend, icon: const Icon(Icons.send_rounded)),
            ],
          ),
        ),
      ),
    );
  }
}
