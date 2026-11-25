import 'package:flutter/material.dart';

import '../theme/app_colors.dart';
import '../utils/formatters.dart';

/// Initials avatar with a stable color derived from the name.
class AppAvatar extends StatelessWidget {
  const AppAvatar({super.key, required this.name, this.size = 44, this.icon, this.color, this.imageUrl});

  final String name;
  final String? imageUrl;
  final double size;
  final IconData? icon;
  final Color? color;

  static Color colorFor(String name) =>
      AppColors.accents[name.codeUnits.fold<int>(0, (a, b) => a + b) % AppColors.accents.length];

  @override
  Widget build(BuildContext context) {
    final c = color ?? colorFor(name);
    if (imageUrl != null) {
      return ClipOval(
        child: Image.network(
          imageUrl!,
          width: size,
          height: size,
          fit: BoxFit.cover,
          errorBuilder: (_, _, _) => AppAvatar(name: name, size: size, icon: icon, color: color),
        ),
      );
    }
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: c.withValues(alpha: 0.14), shape: BoxShape.circle),
      child: icon != null
          ? Icon(icon, color: c, size: size * 0.5)
          : Text(
              Fmt.initials(name),
              style: TextStyle(color: c, fontWeight: FontWeight.w700, fontSize: size * 0.36),
            ),
    );
  }
}
