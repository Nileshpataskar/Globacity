import 'package:intl/intl.dart';

import '../config/app_config.dart';

class Fmt {
  Fmt._();

  static String _currency = AppConfig.currency;
  static int _decimals = 2;

  /// Called when the selected unit's country context loads (e.g. AED/2, INR/2, KWD/3).
  static void setCurrency(String code, int decimals) {
    _currency = code;
    _decimals = decimals;
  }

  static String get currency => _currency;

  /// Formats [amount] in [currency] (defaults to the selected unit's currency).
  static String money(num amount, [String? currency]) {
    final code = currency == null || currency.isEmpty ? _currency : currency;
    final decimals = code == _currency ? _decimals : 2;
    final pattern = decimals > 0 ? '#,##0.${'0' * decimals}' : '#,##0';
    return '$code ${NumberFormat(pattern).format(amount)}';
  }
  static String date(DateTime d) => DateFormat('d MMM yyyy').format(d);
  static String shortDate(DateTime d) => DateFormat('d MMM').format(d);
  static String time(DateTime d) => DateFormat('h:mm a').format(d);
  static String dateTime(DateTime d) => DateFormat('d MMM, h:mm a').format(d);
  static String weekday(DateTime d) => DateFormat('EEE').format(d);
  static String month(DateTime d) => DateFormat('MMMM yyyy').format(d);

  static String relative(DateTime d) {
    final diff = DateTime.now().difference(d);
    if (diff.isNegative) {
      final ahead = -diff.inMinutes;
      if (ahead < 60) return 'in ${ahead}m';
      if (ahead < 60 * 24) return 'in ${(ahead / 60).round()}h';
      return date(d);
    }
    if (diff.inMinutes < 1) return 'just now';
    if (diff.inMinutes < 60) return '${diff.inMinutes}m ago';
    if (diff.inHours < 24) return '${diff.inHours}h ago';
    if (diff.inDays < 7) return '${diff.inDays}d ago';
    return date(d);
  }

  static String initials(String name) {
    final parts = name.trim().split(RegExp(r'\s+')).where((p) => p.isNotEmpty).toList();
    if (parts.isEmpty) return '?';
    if (parts.length == 1) return parts.first.substring(0, 1).toUpperCase();
    return (parts.first[0] + parts.last[0]).toUpperCase();
  }
}
