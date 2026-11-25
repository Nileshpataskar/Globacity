import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../../core/widgets/widgets.dart';

/// Bottom navigation scaffold hosting the five main tabs.
class MainShell extends StatelessWidget {
  const MainShell({super.key, required this.shell});

  final StatefulNavigationShell shell;

  static const _items = [
    (Icons.home_outlined, Icons.home_rounded, 'Home'),
    (Icons.badge_outlined, Icons.badge_rounded, 'Visitors'),
    (Icons.groups_outlined, Icons.groups_rounded, 'Community'),
    (Icons.account_balance_wallet_outlined, Icons.account_balance_wallet_rounded, 'Payments'),
    (Icons.person_outline_rounded, Icons.person_rounded, 'Profile'),
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
