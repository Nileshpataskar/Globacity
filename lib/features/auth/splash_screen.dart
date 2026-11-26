import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/config/app_config.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/widgets/widgets.dart';
import '../../data/providers.dart';
import 'auth_flow.dart';

/// Restores a saved session, then routes to home / join community / onboarding.
class SplashScreen extends ConsumerStatefulWidget {
  const SplashScreen({super.key});

  @override
  ConsumerState<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends ConsumerState<SplashScreen> {
  String? _error;

  @override
  void initState() {
    super.initState();
    _start();
  }

  Future<void> _start() async {
    setState(() => _error = null);
    // Long enough for the logo animation, short enough not to feel like a wait.
    final brandMoment = Future<void>.delayed(const Duration(milliseconds: 800));
    try {
      final signedIn = await ref.read(sessionProvider.notifier).restore();
      await brandMoment;
      if (!mounted) return;
      if (signedIn) {
        // Already logged in: straight to the app, no intro or login screens.
        await goAfterSignIn(context, ref);
        return;
      }
      final tokens = ref.read(tokenStoreProvider);
      if (tokens.onboardingSeen || AppConfig.guardApp) {
        context.go(Routes.login);
      } else {
        await tokens.markOnboardingSeen();
        if (mounted) context.go(Routes.onboarding);
      }
    } catch (e) {
      if (mounted) setState(() => _error = e.toString());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BrandBackdrop(
        child: SizedBox.expand(
          child: SafeArea(
            child: Padding(
              padding: const EdgeInsets.all(AppSpacing.xl),
              child: Column(
                children: [
                  const Spacer(flex: 3),
                  const BrandMark(size: 112, glow: true)
                      .animate()
                      .fadeIn(duration: 400.ms)
                      .scaleXY(begin: 0.6, end: 1, duration: 700.ms, curve: Curves.easeOutBack)
                      .then(delay: 200.ms)
                      .shimmer(duration: 1200.ms, color: Colors.white24),
                  const SizedBox(height: AppSpacing.xl),
                  const BrandWordmark(size: 34, onDark: true, showMark: false).enter(4, 0.4),
                  const SizedBox(height: AppSpacing.sm),
                  Text(AppConfig.tagline, textAlign: TextAlign.center,
                          style: context.text.bodyMedium?.copyWith(color: Colors.white70))
                      .enter(6, 0.4),
                  const Spacer(flex: 2),
                  if (_error == null)
                    const SizedBox(width: 26, height: 26, child: CircularProgressIndicator(strokeWidth: 2.4, color: AppColors.cyan))
                        .animate()
                        .fadeIn(delay: 700.ms)
                  else ...[
                    Text(_error!, textAlign: TextAlign.center, style: context.text.bodySmall?.copyWith(color: Colors.white)),
                    const SizedBox(height: AppSpacing.lg),
                    FilledButton.tonal(onPressed: _start, child: const Text('Retry')),
                  ],
                  const SizedBox(height: AppSpacing.xxl),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}
