import 'package:flutter/widgets.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../app/router.dart';
import '../../core/config/app_config.dart';
import '../../core/utils/context_ext.dart';
import '../../data/guard.dart';
import '../../data/providers.dart';

/// After sign-in: admins/managers go to the management dashboard, guards to the guard dashboard; residents go home if they have any unit
/// (approved or pending), else to "join community".
Future<void> goAfterSignIn(BuildContext context, WidgetRef ref) async {
  ref.invalidate(propertiesProvider);
  ref.invalidate(myRolesDetailProvider);
  final results = await Future.wait([ref.read(propertiesProvider.future), ref.read(myRolesProvider.future)]);
  final properties = results[0] as List;
  final roles = results[1] as Set<String>;
  if (!context.mounted) return;
  if (AppConfig.guardApp) {
    // Guard app: security staff only (admins / managers can also run the gate).
    if (roles.contains('guard') || roles.contains('admin') || roles.contains('manager') || roles.contains('platform_admin')) {
      context.go(Routes.guardHome);
    } else {
      await ref.read(sessionProvider.notifier).logout();
      if (!context.mounted) return;
      context.go(Routes.login);
      context.showSnack('This app is for security staff. Residents, please use the GlobaCity app.');
    }
    return;
  }
  if (roles.contains('admin') || roles.contains('manager') || roles.contains('platform_admin')) {
    context.go(Routes.manageHome);
  } else if (roles.contains('guard')) {
    context.go(Routes.guardHome);
  } else {
    context.go(properties.isEmpty ? '${Routes.joinCommunity}?first=1' : Routes.home);
  }
}
