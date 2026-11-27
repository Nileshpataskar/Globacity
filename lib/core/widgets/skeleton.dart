import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';

import '../theme/app_spacing.dart';
import '../utils/context_ext.dart';

/// Skeleton loading: grey placeholders shaped like the content, with a soft shimmer.

/// One placeholder block.
class SkeletonBox extends StatelessWidget {
  const SkeletonBox({super.key, this.width, this.height = 14, this.radius = 8, this.circle = false});

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  Widget build(BuildContext context) => Container(
        width: circle ? height : width,
        height: height,
        decoration: BoxDecoration(
          color: context.palette.border.withValues(alpha: context.theme.brightness == Brightness.dark ? 0.9 : 0.75),
          borderRadius: circle ? null : BorderRadius.circular(radius),
          shape: circle ? BoxShape.circle : BoxShape.rectangle,
        ),
      );
}

/// Wraps placeholders with the shared shimmer sweep.
class Shimmer extends StatelessWidget {
  const Shimmer({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) => child
      .animate(onPlay: (c) => c.repeat())
      .shimmer(duration: 1300.ms, color: context.scheme.surface.withValues(alpha: 0.7), angle: 0.3);
}

/// A card-shaped placeholder: avatar, two lines and an optional trailing chip.
class SkeletonCard extends StatelessWidget {
  const SkeletonCard({super.key, this.avatar = true, this.lines = 2, this.tall = false});

  final bool avatar;
  final int lines;

  /// Taller card with a banner (events, notices).
  final bool tall;

  @override
  Widget build(BuildContext context) {
    return Container(
      decoration: BoxDecoration(
        color: context.scheme.surface,
        borderRadius: AppRadius.cardRadius,
        border: Border.all(color: context.palette.border.withValues(alpha: 0.7)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (tall) const SkeletonBox(height: 96, radius: 0),
          Padding(
            padding: const EdgeInsets.all(AppSpacing.lg),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (avatar) ...[const SkeletonBox(height: 44, circle: true), const SizedBox(width: AppSpacing.md)],
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const FractionallySizedBox(widthFactor: 0.6, child: SkeletonBox(height: 15)),
                      for (var i = 1; i < lines + 1; i++) ...[
                        const SizedBox(height: 9),
                        FractionallySizedBox(widthFactor: i == lines ? 0.45 : 0.9, child: const SkeletonBox(height: 11)),
                      ],
                    ],
                  ),
                ),
                if (!tall) ...[const SizedBox(width: AppSpacing.md), const SkeletonBox(width: 56, height: 22, radius: 99)],
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// A list of placeholder cards, used while a screen's list loads.
class SkeletonList extends StatelessWidget {
  const SkeletonList({super.key, this.count = 6, this.tall = false, this.padding = AppSpacing.screenAll});

  final int count;
  final bool tall;
  final EdgeInsetsGeometry padding;

  @override
  Widget build(BuildContext context) => Shimmer(
        child: ListView.separated(
          padding: padding,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: count,
          separatorBuilder: (_, _) => const SizedBox(height: AppSpacing.md),
          itemBuilder: (_, i) => SkeletonCard(tall: tall, lines: i.isEven ? 2 : 1),
        ),
      );
}

/// Small inline placeholder (inside cards and sections).
class SkeletonLines extends StatelessWidget {
  const SkeletonLines({super.key, this.lines = 2});

  final int lines;

  @override
  Widget build(BuildContext context) => Shimmer(
        child: Padding(
          padding: const EdgeInsets.symmetric(vertical: AppSpacing.sm),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var i = 0; i < lines; i++) ...[
                if (i > 0) const SizedBox(height: 10),
                FractionallySizedBox(widthFactor: i == lines - 1 ? 0.55 : 1, child: const SkeletonBox(height: 13)),
              ],
            ],
          ),
        ),
      );
}

/// Placeholder for the resident home screen: hero, quick-action grid and two cards.
class HomeSkeleton extends StatelessWidget {
  const HomeSkeleton({super.key});

  @override
  Widget build(BuildContext context) {
    return Shimmer(
      child: ListView(
        physics: const NeverScrollableScrollPhysics(),
        padding: EdgeInsets.zero,
        children: [
          Container(
            height: 210,
            decoration: BoxDecoration(
              gradient: LinearGradient(colors: context.palette.heroGradient),
              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(32)),
            ),
          ),
          Padding(
            padding: AppSpacing.screenAll,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const SizedBox(height: AppSpacing.md),
                const SkeletonBox(width: 130, height: 16),
                const SizedBox(height: AppSpacing.md),
                GridView.count(
                  crossAxisCount: 4,
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  mainAxisSpacing: AppSpacing.lg,
                  children: [
                    for (var i = 0; i < 8; i++)
                      const Column(children: [
                        SkeletonBox(width: 52, height: 52, radius: 16),
                        SizedBox(height: 8),
                        SkeletonBox(width: 48, height: 10),
                      ]),
                  ],
                ),
                const SizedBox(height: AppSpacing.xl),
                const SkeletonCard(),
                const SizedBox(height: AppSpacing.md),
                const SkeletonCard(lines: 1),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
