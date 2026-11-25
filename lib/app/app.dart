import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../core/config/app_config.dart';
import '../core/theme/app_theme.dart';
import '../data/models.dart';
import '../data/providers.dart';
import 'realtime.dart';
import 'router.dart';

class GlobacityApp extends ConsumerStatefulWidget {
  const GlobacityApp({super.key});

  @override
  ConsumerState<GlobacityApp> createState() => _GlobacityAppState();
}

class _GlobacityAppState extends ConsumerState<GlobacityApp> {
  @override
  void initState() {
    super.initState();
    ref.read(apiProvider).onSessionExpired = () {
      ref.read(sessionProvider.notifier).expired();
      appRouter.go(Routes.login);
    };
  }

  @override
  Widget build(BuildContext context) {
    // Live updates while signed in.
    ref.listen<UserProfile?>(sessionProvider, (_, user) {
      final realtime = ref.read(realtimeProvider);
      user != null ? realtime.start() : realtime.stop();
    });

    final locale = ref.watch(localeProvider);
    final arabic = locale.languageCode == 'ar';
    // White-label: the selected community's brand color themes the whole app.
    final brand = ref.watch(sessionProvider) == null ? null : ref.watch(contextProvider).value?.primaryColor;
    return MaterialApp.router(
      title: AppConfig.appName,
      debugShowCheckedModeBanner: false,
      scaffoldMessengerKey: scaffoldMessengerKey,
      theme: AppTheme.light(arabic: arabic, brand: brand),
      darkTheme: AppTheme.dark(arabic: arabic, brand: brand),
      themeMode: ref.watch(themeModeProvider),
      locale: locale,
      supportedLocales: const [Locale('en'), Locale('ar')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      routerConfig: appRouter,
    );
  }
}
