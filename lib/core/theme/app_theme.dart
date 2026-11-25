import 'package:flutter/cupertino.dart' show CupertinoPageTransitionsBuilder;
import 'package:flutter/material.dart';

import 'app_colors.dart';
import 'app_spacing.dart';
import 'app_typography.dart';

/// Semantic colors that Material's [ColorScheme] does not cover.
@immutable
class AppPalette extends ThemeExtension<AppPalette> {
  const AppPalette({
    required this.success,
    required this.warning,
    required this.danger,
    required this.info,
    required this.surfaceAlt,
    required this.border,
    required this.textMuted,
    required this.heroGradient,
  });

  final Color success;
  final Color warning;
  final Color danger;
  final Color info;
  final Color surfaceAlt;
  final Color border;
  final Color textMuted;
  final List<Color> heroGradient;

  static const light = AppPalette(
    success: AppColors.success,
    warning: AppColors.warning,
    danger: AppColors.danger,
    info: AppColors.info,
    surfaceAlt: AppColors.lightSurfaceAlt,
    border: AppColors.lightBorder,
    textMuted: AppColors.lightTextMuted,
    heroGradient: [AppColors.navy, AppColors.navyLight],
  );

  static const dark = AppPalette(
    success: Color(0xFF22C55E),
    warning: Color(0xFFFBBF24),
    danger: Color(0xFFF87171),
    info: Color(0xFF38BDF8),
    surfaceAlt: AppColors.darkSurfaceAlt,
    border: AppColors.darkBorder,
    textMuted: AppColors.darkTextMuted,
    heroGradient: [Color(0xFF0B1324), AppColors.navyLight],
  );

  @override
  AppPalette copyWith({
    Color? success,
    Color? warning,
    Color? danger,
    Color? info,
    Color? surfaceAlt,
    Color? border,
    Color? textMuted,
    List<Color>? heroGradient,
  }) {
    return AppPalette(
      success: success ?? this.success,
      warning: warning ?? this.warning,
      danger: danger ?? this.danger,
      info: info ?? this.info,
      surfaceAlt: surfaceAlt ?? this.surfaceAlt,
      border: border ?? this.border,
      textMuted: textMuted ?? this.textMuted,
      heroGradient: heroGradient ?? this.heroGradient,
    );
  }

  @override
  AppPalette lerp(ThemeExtension<AppPalette>? other, double t) {
    if (other is! AppPalette) return this;
    return AppPalette(
      success: Color.lerp(success, other.success, t)!,
      warning: Color.lerp(warning, other.warning, t)!,
      danger: Color.lerp(danger, other.danger, t)!,
      info: Color.lerp(info, other.info, t)!,
      surfaceAlt: Color.lerp(surfaceAlt, other.surfaceAlt, t)!,
      border: Color.lerp(border, other.border, t)!,
      textMuted: Color.lerp(textMuted, other.textMuted, t)!,
      heroGradient: t < 0.5 ? heroGradient : other.heroGradient,
    );
  }
}

class AppTheme {
  AppTheme._();

  /// The default community colour means "use GlobaCity branding" (navy hero), not a custom brand.
  static Color? _custom(Color? brand) =>
      brand == null || brand.toARGB32() == AppColors.primary.toARGB32() ? null : brand;

  /// [brand] is the white-label color of the selected community (null = default brand).
  static ThemeData light({bool arabic = false, Color? brand}) => _lightFor(arabic, _custom(brand));

  static ThemeData dark({bool arabic = false, Color? brand}) => _darkFor(arabic, _custom(brand));

  static ThemeData _lightFor(bool arabic, Color? brand) => _build(
        brightness: Brightness.light,
        palette: brand == null
            ? AppPalette.light
            : AppPalette.light.copyWith(heroGradient: [brand, Color.lerp(brand, Colors.black, 0.32)!]),
        primary: brand ?? AppColors.primary,
        background: AppColors.lightBackground,
        surface: AppColors.lightSurface,
        text: AppColors.lightText,
        arabic: arabic,
      );

  static ThemeData _darkFor(bool arabic, Color? brand) => _build(
        brightness: Brightness.dark,
        palette: brand == null
            ? AppPalette.dark
            : AppPalette.dark.copyWith(
                heroGradient: [Color.lerp(brand, Colors.black, 0.15)!, Color.lerp(brand, Colors.black, 0.6)!]),
        primary: brand == null ? const Color(0xFF60A5FA) : Color.lerp(brand, Colors.white, 0.35)!,
        background: AppColors.darkBackground,
        surface: AppColors.darkSurface,
        text: AppColors.darkText,
        arabic: arabic,
      );

  static ThemeData _build({
    required Brightness brightness,
    required AppPalette palette,
    required Color primary,
    required Color background,
    required Color surface,
    required Color text,
    required bool arabic,
  }) {
    final isDark = brightness == Brightness.dark;
    final scheme = ColorScheme.fromSeed(
      seedColor: primary,
      brightness: brightness,
      primary: primary,
      onPrimary: isDark ? const Color(0xFF0B1220) : Colors.white,
      secondary: AppColors.secondary,
      error: palette.danger,
      surface: surface,
      onSurface: text,
      outline: palette.border,
      outlineVariant: palette.border,
      surfaceContainerHighest: palette.surfaceAlt,
    );
    final textTheme = AppTypography.textTheme(text, palette.textMuted, arabic: arabic);

    OutlineInputBorder fieldBorder(Color color, [double width = 1]) => OutlineInputBorder(
          borderRadius: AppRadius.fieldRadius,
          borderSide: BorderSide(color: color, width: width),
        );

    const buttonShape = RoundedRectangleBorder(borderRadius: AppRadius.fieldRadius);
    const buttonSize = Size(64, 52);

    return ThemeData(
      useMaterial3: true,
      brightness: brightness,
      colorScheme: scheme,
      scaffoldBackgroundColor: background,
      textTheme: textTheme,
      extensions: [palette],
      splashFactory: InkSparkle.splashFactory,
      // Smooth, modern page transitions on every platform.
      pageTransitionsTheme: const PageTransitionsTheme(builders: {
        TargetPlatform.android: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.iOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.macOS: CupertinoPageTransitionsBuilder(),
        TargetPlatform.windows: FadeForwardsPageTransitionsBuilder(),
        TargetPlatform.linux: FadeForwardsPageTransitionsBuilder(),
      }),
      appBarTheme: AppBarTheme(
        backgroundColor: background,
        foregroundColor: text,
        elevation: 0,
        scrolledUnderElevation: 0,
        centerTitle: false,
        titleTextStyle: textTheme.titleLarge,
      ),
      cardTheme: CardThemeData(
        color: surface,
        elevation: 0,
        margin: EdgeInsets.zero,
        shape: RoundedRectangleBorder(
          borderRadius: AppRadius.cardRadius,
          side: BorderSide(color: palette.border),
        ),
      ),
      dividerTheme: DividerThemeData(color: palette.border, thickness: 1, space: 1),
      filledButtonTheme: FilledButtonThemeData(
        style: FilledButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          textStyle: textTheme.labelLarge,
        ),
      ),
      elevatedButtonTheme: ElevatedButtonThemeData(
        style: ElevatedButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          elevation: 0,
          textStyle: textTheme.labelLarge,
        ),
      ),
      outlinedButtonTheme: OutlinedButtonThemeData(
        style: OutlinedButton.styleFrom(
          minimumSize: buttonSize,
          shape: buttonShape,
          side: BorderSide(color: palette.border),
          foregroundColor: text,
          textStyle: textTheme.labelLarge,
        ),
      ),
      textButtonTheme: TextButtonThemeData(
        style: TextButton.styleFrom(textStyle: textTheme.labelLarge),
      ),
      inputDecorationTheme: InputDecorationTheme(
        filled: true,
        fillColor: surface,
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg, vertical: AppSpacing.lg),
        hintStyle: textTheme.bodyMedium?.copyWith(color: palette.textMuted),
        labelStyle: textTheme.bodyMedium?.copyWith(color: palette.textMuted),
        prefixIconColor: palette.textMuted,
        suffixIconColor: palette.textMuted,
        border: fieldBorder(palette.border),
        enabledBorder: fieldBorder(palette.border),
        focusedBorder: fieldBorder(scheme.primary, 1.6),
        errorBorder: fieldBorder(palette.danger),
        focusedErrorBorder: fieldBorder(palette.danger, 1.6),
      ),
      chipTheme: ChipThemeData(
        backgroundColor: surface,
        selectedColor: scheme.primary.withValues(alpha: 0.12),
        side: BorderSide(color: palette.border),
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.pill))),
        labelStyle: textTheme.labelMedium?.copyWith(color: text),
        padding: const EdgeInsets.symmetric(horizontal: AppSpacing.sm, vertical: AppSpacing.xs),
        showCheckmark: false,
      ),
      navigationBarTheme: NavigationBarThemeData(
        height: 66,
        elevation: 0,
        backgroundColor: Colors.transparent,
        labelBehavior: NavigationDestinationLabelBehavior.alwaysShow,
        indicatorColor: scheme.primary.withValues(alpha: 0.14),
        indicatorShape: const StadiumBorder(),
        labelTextStyle: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return textTheme.labelSmall?.copyWith(
            color: selected ? scheme.primary : palette.textMuted,
            fontWeight: selected ? FontWeight.w700 : FontWeight.w600,
          );
        }),
        iconTheme: WidgetStateProperty.resolveWith((states) {
          final selected = states.contains(WidgetState.selected);
          return IconThemeData(color: selected ? scheme.primary : palette.textMuted, size: 24);
        }),
      ),
      tabBarTheme: TabBarThemeData(
        labelColor: scheme.primary,
        unselectedLabelColor: palette.textMuted,
        labelStyle: textTheme.titleSmall,
        unselectedLabelStyle: textTheme.titleSmall,
        indicatorColor: scheme.primary,
        indicatorSize: TabBarIndicatorSize.label,
        dividerColor: palette.border,
      ),
      bottomSheetTheme: BottomSheetThemeData(
        backgroundColor: surface,
        showDragHandle: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(AppRadius.xl)),
        ),
      ),
      dialogTheme: DialogThemeData(
        backgroundColor: surface,
        shape: const RoundedRectangleBorder(borderRadius: BorderRadius.all(Radius.circular(AppRadius.xl))),
      ),
      listTileTheme: ListTileThemeData(
        contentPadding: const EdgeInsets.symmetric(horizontal: AppSpacing.lg),
        iconColor: palette.textMuted,
        titleTextStyle: textTheme.titleSmall,
        subtitleTextStyle: textTheme.bodySmall,
      ),
      floatingActionButtonTheme: FloatingActionButtonThemeData(
        backgroundColor: scheme.primary,
        foregroundColor: scheme.onPrimary,
        elevation: 0,
        highlightElevation: 0,
        shape: const StadiumBorder(),
      ),
      snackBarTheme: SnackBarThemeData(
        behavior: SnackBarBehavior.floating,
        shape: const RoundedRectangleBorder(borderRadius: AppRadius.fieldRadius),
        contentTextStyle: textTheme.bodyMedium?.copyWith(color: isDark ? AppColors.lightText : Colors.white),
      ),
      switchTheme: SwitchThemeData(
        trackOutlineColor: WidgetStateProperty.all(Colors.transparent),
      ),
      segmentedButtonTheme: SegmentedButtonThemeData(
        style: SegmentedButton.styleFrom(
          side: BorderSide(color: palette.border),
          selectedBackgroundColor: scheme.primary.withValues(alpha: 0.12),
          selectedForegroundColor: scheme.primary,
          textStyle: textTheme.labelMedium,
        ),
      ),
    );
  }
}
