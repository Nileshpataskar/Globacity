import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/widgets/widgets.dart';

/// Branded frame for sign-in screens: navy header with the logo and a title,
/// and the form on a rounded panel that slides up.
class AuthScaffold extends StatelessWidget {
  const AuthScaffold({super.key, required this.title, this.subtitle, required this.body, this.icon});

  final String title;
  final String? subtitle;
  final Widget body;

  /// Optional icon shown instead of the logo (e.g. a message icon on the code screen).
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final canPop = context.canPop();
    return Scaffold(
      backgroundColor: context.palette.heroGradient.first,
      body: BrandBackdrop(
        child: Column(
          children: [
            SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.sm, AppSpacing.xl, AppSpacing.xl),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    SizedBox(
                      height: 48,
                      child: Row(children: [
                        if (canPop)
                          IconButton(
                            onPressed: () => context.pop(),
                            icon: const Icon(Icons.arrow_back_rounded, color: Colors.white),
                          )
                        else
                          const SizedBox(width: AppSpacing.sm),
                        const Spacer(),
                      ]),
                    ),
                    Padding(
                      padding: const EdgeInsets.only(left: AppSpacing.sm),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          if (icon == null)
                            const BrandMark(size: 60, glow: true).pop()
                          else
                            Container(
                              width: 60,
                              height: 60,
                              decoration: BoxDecoration(
                                color: Colors.white.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(18),
                                border: Border.all(color: Colors.white.withValues(alpha: 0.2)),
                              ),
                              child: Icon(icon, color: Colors.white, size: 28),
                            ).pop(),
                          const SizedBox(height: AppSpacing.lg),
                          Text(title, style: context.text.headlineMedium?.copyWith(color: Colors.white)).enter(1, 0.3),
                          if (subtitle != null) ...[
                            const SizedBox(height: AppSpacing.xs),
                            Text(subtitle!, style: context.text.bodyMedium?.copyWith(color: Colors.white70)).enter(2, 0.3),
                          ],
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
            Expanded(
              child: Container(
                width: double.infinity,
                decoration: BoxDecoration(
                  color: context.theme.scaffoldBackgroundColor,
                  borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
                ),
                clipBehavior: Clip.antiAlias,
                child: MediaQuery.removePadding(
                  context: context,
                  removeTop: true,
                  child: Padding(padding: const EdgeInsets.only(top: AppSpacing.lg), child: body),
                ),
              )
                  .animate()
                  .fadeIn(duration: 350.ms)
                  .slideY(begin: 0.08, end: 0, duration: 500.ms, curve: Curves.easeOutCubic),
            ),
          ],
        ),
      ),
    );
  }
}
