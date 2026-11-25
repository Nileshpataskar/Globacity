import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../theme/app_colors.dart';
import '../theme/app_spacing.dart';
import '../utils/context_ext.dart';

/// GlobaCity brand assets, motion helpers and branded controls.

class BrandAssets {
  BrandAssets._();

  static const appIcon = 'assets/brand/app-icon.svg';
  static const lettermark = 'assets/brand/lettermark.svg';
}

/// The GlobaCity "G": the navy app-icon tile, or the bare lettermark.
class BrandMark extends StatelessWidget {
  const BrandMark({super.key, this.size = 56, this.tile = true, this.glow = false});

  final double size;

  /// True: navy rounded tile (app icon). False: bare lettermark.
  final bool tile;

  /// Soft blue glow behind the mark (for dark hero backgrounds).
  final bool glow;

  @override
  Widget build(BuildContext context) {
    final mark = SvgPicture.asset(tile ? BrandAssets.appIcon : BrandAssets.lettermark, width: size, height: size);
    if (!glow) return mark;
    return DecoratedBox(
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(size * 0.26),
        boxShadow: [
          BoxShadow(color: AppColors.primary.withValues(alpha: 0.45), blurRadius: size * 0.6, spreadRadius: -size * 0.08),
          BoxShadow(color: AppColors.cyan.withValues(alpha: 0.25), blurRadius: size * 0.9, offset: Offset(0, size * 0.12)),
        ],
      ),
      child: mark,
    );
  }
}

/// "GlobaCity" wordmark: "Globa" in navy (or white on dark) and "City" in the blue→cyan gradient.
class BrandWordmark extends StatelessWidget {
  const BrandWordmark({super.key, this.size = 28, this.onDark = false, this.showMark = true});

  final double size;
  final bool onDark;
  final bool showMark;

  @override
  Widget build(BuildContext context) {
    final style = context.text.headlineMedium?.copyWith(
      fontSize: size,
      fontWeight: FontWeight.w800,
      letterSpacing: -size * 0.04,
      height: 1,
      color: onDark ? Colors.white : (context.theme.brightness == Brightness.dark ? Colors.white : AppColors.navy),
    );
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        if (showMark) ...[
          BrandMark(size: size * 1.25, tile: onDark),
          SizedBox(width: size * 0.3),
        ],
        Text('Globa', style: style),
        GradientText('City', style: style),
      ],
    );
  }
}

/// Text painted with the brand gradient.
class GradientText extends StatelessWidget {
  const GradientText(this.text, {super.key, this.style, this.colors = AppColors.brandGradient});

  final String text;
  final TextStyle? style;
  final List<Color> colors;

  @override
  Widget build(BuildContext context) => ShaderMask(
        blendMode: BlendMode.srcIn,
        shaderCallback: (r) => LinearGradient(colors: colors).createShader(Rect.fromLTWH(0, 0, r.width, r.height)),
        child: Text(text, style: style),
      );
}

/// Full-width call-to-action with the blue→cyan gradient and a press animation.
class GradientButton extends StatefulWidget {
  const GradientButton({super.key, required this.label, this.onPressed, this.icon, this.busy = false});

  final String label;
  final VoidCallback? onPressed;
  final IconData? icon;
  final bool busy;

  @override
  State<GradientButton> createState() => _GradientButtonState();
}

class _GradientButtonState extends State<GradientButton> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    final enabled = widget.onPressed != null && !widget.busy;
    return AnimatedScale(
      scale: _down ? 0.97 : 1,
      duration: const Duration(milliseconds: 120),
      child: AnimatedOpacity(
        opacity: enabled || widget.busy ? 1 : 0.5,
        duration: const Duration(milliseconds: 200),
        child: DecoratedBox(
          decoration: BoxDecoration(
            gradient: const LinearGradient(colors: [AppColors.primary, Color(0xFF1D9BF0)]),
            borderRadius: AppRadius.fieldRadius,
            boxShadow: enabled
                ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 18, offset: const Offset(0, 8))]
                : null,
          ),
          child: Material(
            color: Colors.transparent,
            child: InkWell(
              borderRadius: AppRadius.fieldRadius,
              onTap: enabled ? widget.onPressed : null,
              onHighlightChanged: (v) => setState(() => _down = v),
              child: SizedBox(
                height: 54,
                child: Center(
                  child: widget.busy
                      ? const SizedBox(width: 22, height: 22, child: CircularProgressIndicator(strokeWidth: 2.4, color: Colors.white))
                      : Row(mainAxisSize: MainAxisSize.min, children: [
                          Text(widget.label, style: context.text.labelLarge?.copyWith(color: Colors.white, fontWeight: FontWeight.w700)),
                          if (widget.icon != null) ...[
                            const SizedBox(width: AppSpacing.sm),
                            Icon(widget.icon, color: Colors.white, size: 20),
                          ],
                        ]),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Navy hero background with soft blue/cyan light blobs, used behind splash and headers.
class BrandBackdrop extends StatelessWidget {
  const BrandBackdrop({super.key, required this.child, this.borderRadius, this.animate = true});

  final Widget child;
  final BorderRadius? borderRadius;
  final bool animate;

  @override
  Widget build(BuildContext context) {
    Widget blob(Color c, double size) {
      final w = Container(
        width: size,
        height: size,
        decoration: BoxDecoration(shape: BoxShape.circle, gradient: RadialGradient(colors: [c, c.withValues(alpha: 0)])),
      );
      return animate
          ? w.animate(onPlay: (ctl) => ctl.repeat(reverse: true)).scaleXY(begin: 0.9, end: 1.12, duration: 5.seconds,
              curve: Curves.easeInOut)
          : w;
    }

    return AnnotatedRegion<SystemUiOverlayStyle>(
      value: SystemUiOverlayStyle.light.copyWith(statusBarColor: Colors.transparent),
      child: ClipRRect(
      borderRadius: borderRadius ?? BorderRadius.zero,
      child: DecoratedBox(
        decoration: BoxDecoration(
          gradient: LinearGradient(colors: context.palette.heroGradient, begin: Alignment.topLeft, end: Alignment.bottomRight),
        ),
        child: Stack(
          children: [
            Positioned(top: -120, right: -90, child: blob(AppColors.primary.withValues(alpha: 0.55), 300)),
            Positioned(bottom: -140, left: -110, child: blob(AppColors.cyan.withValues(alpha: 0.28), 320)),
            child,
          ],
        ),
      ),
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Motion
// ---------------------------------------------------------------------------

/// Standard entrance animations so every screen moves the same way.
extension Entrance on Widget {
  /// Fade + slide up, staggered by [index] (for lists and stacked sections).
  Widget enter([int index = 0, double offset = 0.12]) => animate(delay: (40 * index.clamp(0, 12)).ms)
      .fadeIn(duration: 380.ms, curve: Curves.easeOutCubic)
      .slideY(begin: offset, end: 0, duration: 420.ms, curve: Curves.easeOutCubic);

  /// Gentle scale-in (for icons, badges and hero marks).
  Widget pop([int delayMs = 0]) => animate(delay: delayMs.ms)
      .fadeIn(duration: 300.ms)
      .scaleXY(begin: 0.85, end: 1, duration: 500.ms, curve: Curves.easeOutBack);
}

/// Shrinks slightly while pressed, for a tactile feel on tappable surfaces.
class Pressable extends StatefulWidget {
  const Pressable({super.key, required this.child, this.enabled = true});

  final Widget child;
  final bool enabled;

  @override
  State<Pressable> createState() => _PressableState();
}

class _PressableState extends State<Pressable> {
  bool _down = false;

  @override
  Widget build(BuildContext context) {
    if (!widget.enabled) return widget.child;
    return Listener(
      onPointerDown: (_) => setState(() => _down = true),
      onPointerUp: (_) => setState(() => _down = false),
      onPointerCancel: (_) => setState(() => _down = false),
      child: AnimatedScale(
        scale: _down ? 0.975 : 1,
        duration: const Duration(milliseconds: 140),
        curve: Curves.easeOut,
        child: widget.child,
      ),
    );
  }
}

// ---------------------------------------------------------------------------
// Navigation
// ---------------------------------------------------------------------------

/// One tab of [BrandNavBar]: (outlined icon, filled icon, label).
typedef BrandNavItem = (IconData icon, IconData selectedIcon, String label);

/// Floating bottom bar: the selected tab grows into a gradient pill with its label.
class BrandNavBar extends StatelessWidget {
  const BrandNavBar({super.key, required this.items, required this.index, required this.onSelect});

  final List<BrandNavItem> items;
  final int index;
  final ValueChanged<int> onSelect;

  @override
  Widget build(BuildContext context) {
    final dark = context.theme.brightness == Brightness.dark;
    return SafeArea(
      top: false,
      minimum: const EdgeInsets.only(bottom: AppSpacing.sm),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(AppSpacing.md, AppSpacing.xs, AppSpacing.md, 0),
        child: Container(
          height: 66,
          padding: const EdgeInsets.symmetric(horizontal: 6),
          decoration: BoxDecoration(
            color: dark ? const Color(0xFF16213A) : Colors.white,
            borderRadius: BorderRadius.circular(24),
            border: Border.all(color: context.palette.border.withValues(alpha: dark ? 1 : 0.6)),
            boxShadow: [
              BoxShadow(color: const Color(0xFF101828).withValues(alpha: dark ? 0.4 : 0.1), blurRadius: 28, offset: const Offset(0, 10)),
            ],
          ),
          child: Row(
            children: [
              for (final (i, item) in items.indexed)
                Expanded(
                  flex: i == index ? 2 : 1,
                  child: _NavTab(item: item, selected: i == index, onTap: () => onSelect(i)),
                ),
            ],
          ),
        ),
      ),
    );
  }
}

class _NavTab extends StatelessWidget {
  const _NavTab({required this.item, required this.selected, required this.onTap});

  final BrandNavItem item;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final (icon, selectedIcon, label) = item;
    return Semantics(
      selected: selected,
      button: true,
      label: label,
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: onTap,
        child: Center(
          child: AnimatedContainer(
            duration: const Duration(milliseconds: 320),
            curve: Curves.easeOutCubic,
            height: 46,
            padding: EdgeInsets.symmetric(horizontal: selected ? 14 : 0),
            decoration: BoxDecoration(
              gradient: selected ? const LinearGradient(colors: [AppColors.primary, Color(0xFF1D9BF0)]) : null,
              borderRadius: BorderRadius.circular(16),
              boxShadow: selected
                  ? [BoxShadow(color: AppColors.primary.withValues(alpha: 0.35), blurRadius: 14, offset: const Offset(0, 6))]
                  : null,
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                AnimatedSwitcher(
                  duration: const Duration(milliseconds: 250),
                  transitionBuilder: (c, a) => ScaleTransition(scale: a, child: c),
                  child: Icon(selected ? selectedIcon : icon, key: ValueKey(selected),
                      color: selected ? Colors.white : context.palette.textMuted, size: 24),
                ),
                if (selected)
                  Flexible(
                    child: Padding(
                      padding: const EdgeInsets.only(left: 6),
                      child: Text(label, maxLines: 1, overflow: TextOverflow.fade, softWrap: false,
                          style: context.text.labelMedium?.copyWith(color: Colors.white, fontWeight: FontWeight.w700))
                          .animate()
                          .fadeIn(duration: 250.ms)
                          .slideX(begin: -0.2, end: 0, duration: 250.ms),
                    ),
                  ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Full-screen loading state: the GlobaCity mark breathing gently.
class BrandLoader extends StatelessWidget {
  const BrandLoader({super.key, this.size = 52});

  final double size;

  @override
  Widget build(BuildContext context) => BrandMark(size: size, tile: false)
      .animate(onPlay: (c) => c.repeat(reverse: true))
      .scaleXY(begin: 0.88, end: 1.06, duration: 750.ms, curve: Curves.easeInOut)
      .fade(begin: 0.55, end: 1, duration: 750.ms);
}
