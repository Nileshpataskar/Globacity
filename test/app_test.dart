import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';

import 'package:globacity/app/app.dart';
import 'package:globacity/app/router.dart';
import 'package:globacity/data/api/token_store.dart';
import 'package:globacity/data/providers.dart';

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  testWidgets('splash with no saved session leads to onboarding', (tester) async {
    await tester.pumpWidget(ProviderScope(
      overrides: [tokenStoreProvider.overrideWithValue(TokenStore(persistent: false))],
      child: const GlobacityApp(),
    ));
    expect(find.text('Globacity'), findsOneWidget);
    await tester.pump(const Duration(seconds: 2));
    await tester.pump(const Duration(milliseconds: 500));
    expect(find.text('Secure gate access'), findsOneWidget);
  });

  // Renders every screen on a phone-sized viewport and fails on overflow or
  // runtime errors.
  const routes = [
    Routes.login,
    '${Routes.otp}?to=x',
    Routes.forgotPassword,
    '${Routes.joinCommunity}?first=1',
    Routes.home,
    Routes.visitors,
    Routes.community,
    Routes.payments,
    Routes.profile,
    Routes.invite,
    '/pass/v2',
    '/approval/v1',
    Routes.household,
    '${Routes.household}?tab=2',
    '/helper/h1',
    '/pay?ids=d1,d2',
    Routes.notices,
    '/notices/n1',
    Routes.polls,
    Routes.events,
    Routes.forum,
    '/forum/fp1',
    Routes.directory,
    Routes.classifieds,
    Routes.homestore,
    Routes.moveRequest,
    Routes.helpdesk,
    Routes.newTicket,
    '/helpdesk/T-1042',
    Routes.sos,
    Routes.emergencyContacts,
    Routes.kidExit,
    Routes.notifications,
    Routes.search,
    Routes.editProfile,
    Routes.notificationSettings,
    Routes.privacySettings,
    Routes.terms,
    '/chat?name=Meera%20Shah',
  ];

  for (final rtlDark in [false, true]) {
    for (final route in routes) {
      testWidgets('renders $route${rtlDark ? ' (Arabic, dark)' : ''}', (tester) async {
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);

        appRouter.go(route);
        await tester.pumpWidget(
          ProviderScope(
            overrides: [
              if (rtlDark) localeProvider.overrideWith(_ArabicLocale.new),
              if (rtlDark) themeModeProvider.overrideWith(_DarkMode.new),
            ],
            child: const GlobacityApp(),
          ),
        );
        await tester.pump();
        await tester.pump(const Duration(seconds: 1));
        expect(tester.takeException(), isNull);
      });
    }
  }
}

class _ArabicLocale extends LocaleNotifier {
  @override
  Locale build() => const Locale('ar');
}

class _DarkMode extends ThemeModeNotifier {
  @override
  ThemeMode build() => ThemeMode.dark;
}
