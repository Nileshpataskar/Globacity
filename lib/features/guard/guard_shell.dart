import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/widgets.dart';

/// Bottom navigation for the guard app.
class GuardShell extends StatelessWidget {
  const GuardShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _items = [
    (Icons.space_dashboard_outlined, Icons.space_dashboard_rounded, 'Dashboard'),
    (Icons.qr_code_scanner_outlined, Icons.qr_code_scanner_rounded, 'Gate'),
    (Icons.groups_outlined, Icons.groups_rounded, 'Visitors'),
    (Icons.badge_outlined, Icons.badge_rounded, 'Staff'),
    (Icons.menu_rounded, Icons.menu_open_rounded, 'More'),
  ];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: shell,
      bottomNavigationBar: BrandNavBar(
        items: _items,
        index: shell.currentIndex,
        onSelect: (i) => shell.goBranch(i, initialLocation: i == shell.currentIndex),
      ),
    );
  }
}
