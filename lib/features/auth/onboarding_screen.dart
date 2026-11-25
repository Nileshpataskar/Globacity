import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/theme/app_colors.dart';
import '../../core/theme/app_spacing.dart';
import '../../core/utils/context_ext.dart';
import '../../core/widgets/widgets.dart';

/// Three intro slides shown once per device, on the navy brand backdrop.
class OnboardingScreen extends StatefulWidget {
  const OnboardingScreen({super.key});

  @override
  State<OnboardingScreen> createState() => _OnboardingScreenState();
}

class _OnboardingScreenState extends State<OnboardingScreen> {
  final _controller = PageController();
  int _page = 0;

  static const _pages = [
    _Slide(Icons.verified_user_rounded, [Icons.qr_code_2_rounded, Icons.local_shipping_rounded, Icons.local_taxi_rounded],
        'Secure gate access', 'Pre-approve guests, deliveries and cabs. Approve or deny visitors at the gate with one tap.'),
    _Slide(Icons.account_balance_wallet_rounded, [Icons.receipt_long_rounded, Icons.credit_card_rounded, Icons.trending_up_rounded],
        'Pay dues in seconds', 'See your bills and pay maintenance securely from anywhere, any time.'),
    _Slide(Icons.diversity_3_rounded, [Icons.campaign_rounded, Icons.how_to_vote_rounded, Icons.celebration_rounded],
        'Stay connected', 'Notices, polls, events and a friendly neighbourhood forum, all in one place.'),
  ];

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _next() {
    if (_page == _pages.length - 1) {
      context.go(Routes.login);
    } else {
      _controller.nextPage(duration: const Duration(milliseconds: 450), curve: Curves.easeOutCubic);
    }
  }

  @override
  Widget build(BuildContext context) {
    final last = _page == _pages.length - 1;
    return Scaffold(
      body: BrandBackdrop(
        child: SafeArea(
          bottom: false,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.md, AppSpacing.md, 0),
                child: Row(children: [
                  const BrandWordmark(size: 20, onDark: true).animate().fadeIn(duration: 500.ms),
                  const Spacer(),
                  AnimatedOpacity(
                    opacity: last ? 0 : 1,
                    duration: 250.ms,
                    child: TextButton(
                      onPressed: last ? null : () => context.go(Routes.login),
                      style: TextButton.styleFrom(foregroundColor: Colors.white70),
                      child: const Text('Skip'),
                    ),
                  ),
                ]),
              ),
              Expanded(
                child: PageView.builder(
                  controller: _controller,
                  itemCount: _pages.length,
                  onPageChanged: (i) => setState(() => _page = i),
                  itemBuilder: (context, i) => Center(child: _Illustration(slide: _pages[i], key: ValueKey(i))),
                ),
              ),
              _InfoPanel(
                slide: _pages[_page],
                page: _page,
                count: _pages.length,
                onNext: _next,
                last: last,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _Slide {
  const _Slide(this.icon, this.orbit, this.title, this.body);

  final IconData icon;
  final List<IconData> orbit;
  final String title;
  final String body;
}

/// Big glowing icon tile with three small chips floating around it.
class _Illustration extends StatelessWidget {
  const _Illustration({super.key, required this.slide});

  final _Slide slide;

  @override
  Widget build(BuildContext context) {
    Widget chip(IconData icon, Alignment at, int i) => Align(
          alignment: at,
          child: Container(
            width: 58,
            height: 58,
            decoration: BoxDecoration(
              color: Colors.white.withValues(alpha: 0.1),
              borderRadius: BorderRadius.circular(18),
              border: Border.all(color: Colors.white.withValues(alpha: 0.18)),
            ),
            child: Icon(icon, color: Colors.white, size: 26),
          )
              .animate(onPlay: (c) => c.repeat(reverse: true))
              .moveY(begin: 0, end: i.isEven ? -8 : 8, duration: (1800 + 300 * i).ms, curve: Curves.easeInOut)
              .animate(delay: (250 + 120 * i).ms)
              .fadeIn(duration: 400.ms)
              .scaleXY(begin: 0.6, end: 1, curve: Curves.easeOutBack, duration: 500.ms),
        );

    return SizedBox(
      width: 300,
      height: 300,
      child: Stack(children: [
        // Rings
        for (final (size, alpha) in [(300.0, 0.06), (220.0, 0.09)])
          Center(
            child: Container(
              width: size,
              height: size,
              decoration: BoxDecoration(shape: BoxShape.circle, border: Border.all(color: Colors.white.withValues(alpha: alpha * 2)),
                  color: Colors.white.withValues(alpha: alpha * 0.4)),
            ).animate().fadeIn(duration: 600.ms).scaleXY(begin: 0.85, end: 1, duration: 700.ms, curve: Curves.easeOutCubic),
          ),
        Center(
          child: Container(
            width: 128,
            height: 128,
            decoration: BoxDecoration(
              gradient: const LinearGradient(colors: AppColors.brandGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
              borderRadius: BorderRadius.circular(38),
              boxShadow: [BoxShadow(color: AppColors.primary.withValues(alpha: 0.55), blurRadius: 40, offset: const Offset(0, 14))],
            ),
            child: Icon(slide.icon, size: 60, color: Colors.white),
          ).animate().fadeIn(duration: 350.ms).scaleXY(begin: 0.5, end: 1, duration: 650.ms, curve: Curves.easeOutBack),
        ),
        chip(slide.orbit[0], const Alignment(-0.95, -0.55), 0),
        chip(slide.orbit[1], const Alignment(0.95, -0.2), 1),
        chip(slide.orbit[2], const Alignment(-0.45, 0.95), 2),
      ]),
    );
  }
}

class _InfoPanel extends StatelessWidget {
  const _InfoPanel({required this.slide, required this.page, required this.count, required this.onNext, required this.last});

  final _Slide slide;
  final int page;
  final int count;
  final VoidCallback onNext;
  final bool last;

  @override
  Widget build(BuildContext context) {
    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        color: context.scheme.surface,
        borderRadius: const BorderRadius.vertical(top: Radius.circular(32)),
      ),
      padding: EdgeInsets.fromLTRB(AppSpacing.xl, AppSpacing.xl, AppSpacing.xl, AppSpacing.xl + MediaQuery.paddingOf(context).bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: List.generate(count, (i) {
              final active = i == page;
              return AnimatedContainer(
                duration: 300.ms,
                curve: Curves.easeOutCubic,
                margin: const EdgeInsets.only(right: 6),
                width: active ? 28 : 8,
                height: 8,
                decoration: BoxDecoration(
                  gradient: active ? const LinearGradient(colors: AppColors.brandGradient) : null,
                  color: active ? null : context.palette.border,
                  borderRadius: BorderRadius.circular(AppRadius.pill),
                ),
              );
            }),
          ),
          const SizedBox(height: AppSpacing.lg),
          AnimatedSwitcher(
            duration: 350.ms,
            switchOutCurve: const Threshold(0),
            layoutBuilder: (current, previous) => current ?? const SizedBox.shrink(),
            transitionBuilder: (child, a) => FadeTransition(
              opacity: a,
              child: SlideTransition(position: Tween(begin: const Offset(0, 0.15), end: Offset.zero).animate(a), child: child),
            ),
            child: Column(
              key: ValueKey(page),
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(slide.title, style: context.text.headlineMedium),
                const SizedBox(height: AppSpacing.sm),
                Text(slide.body, style: context.text.bodyLarge?.copyWith(color: context.palette.textMuted)),
              ],
            ),
          ),
          const SizedBox(height: AppSpacing.xl),
          GradientButton(
            label: last ? 'Get started' : 'Next',
            icon: last ? Icons.arrow_forward_rounded : null,
            onPressed: onNext,
          ),
        ],
      ),
    );
  }
}
