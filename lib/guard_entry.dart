import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';
import 'core/config/app_config.dart';

/// Starts the separate "GlobaCity Guard" app (see guard_app/). Same code, guard-only flow:
/// no onboarding or sign-up, and only guards / managers / admins can sign in.
void runGuardApp() {
  AppConfig.guardApp = true;
  AppConfig.assetPackage = 'globacity';
  runApp(ProviderScope(retry: (_, _) => null, child: const GlobacityApp()));
}
