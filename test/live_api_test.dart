// End-to-end check of the app against a running backend.
//
//   cd backend && docker compose up -d
//   flutter test test/live_api_test.dart --dart-define=LIVE=true --dart-define=API_URL=http://localhost:8000
//
// Skipped by default so `flutter test` works without the backend.

import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:google_fonts/google_fonts.dart';
import 'package:globacity/app/app.dart';
import 'package:globacity/app/router.dart';
import 'package:globacity/core/config/env.dart';
import 'package:globacity/data/actions.dart';
import 'package:globacity/data/api/token_store.dart';
import 'package:globacity/data/models.dart';
import 'package:globacity/data/providers.dart';

const live = bool.fromEnvironment('LIVE');
const resident = '+971501234567';

Future<Json> _post(String path, Json body) async {
  final client = HttpClient();
  final req = await client.postUrl(Uri.parse('${Env.apiUrl}$path'));
  final bytes = utf8.encode(jsonEncode(body));
  req.headers.contentType = ContentType.json;
  req.contentLength = bytes.length; // Django needs Content-Length (no chunked bodies)
  req.add(bytes);
  final res = await req.close();
  final data = jsonDecode(await res.transform(utf8.decoder).join()) as Json;
  client.close();
  if (res.statusCode >= 300) throw Exception('$path -> ${res.statusCode} $data');
  return data;
}

Json? _auth;

/// Signs in once with OTP (DEBUG backend returns the code); each test gets a fresh container.
Future<ProviderContainer> _signedInContainer() async {
  if (_auth == null) {
    final otp = await _post('/auth/otp/request/', {'phone': resident});
    _auth = await _post('/auth/otp/verify/', {'phone': resident, 'code': otp['debug_code']});
  }
  final store = TokenStore(persistent: false)
    ..access = _auth!['access'] as String
    ..refresh = _auth!['refresh'] as String;
  final container = ProviderContainer(
    overrides: [tokenStoreProvider.overrideWithValue(store)],
    retry: (_, _) => null,
  );
  expect(await container.read(sessionProvider.notifier).restore(), isTrue);
  return container;
}

void main() {
  setUpAll(() => GoogleFonts.config.allowRuntimeFetching = false);

  group('live backend', skip: live ? false : 'Run with --dart-define=LIVE=true and the backend up', () {
    late ProviderContainer c;

    setUp(() async {
      HttpOverrides.global = null; // allow real network in tests
      c = await _signedInContainer();
    });
    tearDown(() => c.dispose());

    test('properties, country context and currency switch per unit', () async {
      final props = await c.read(propertiesProvider.future);
      final dubai = props.firstWhere((p) => p.currency == 'AED');
      final mumbai = props.firstWhere((p) => p.currency == 'INR');

      c.read(actionsProvider).selectUnit(dubai.id);
      var ctx = await c.read(contextProvider.future);
      expect((ctx.currencyCode, ctx.taxName), ('AED', 'VAT'));
      final aedDues = await c.read(duesProvider.future);
      expect(aedDues.every((d) => d.currency == 'AED'), isTrue);

      c.read(actionsProvider).selectUnit(mumbai.id);
      ctx = await c.read(contextProvider.future);
      expect((ctx.currencyCode, ctx.taxName), ('INR', 'GST'));
      expect((await c.read(duesProvider.future)).every((d) => d.currency == 'INR'), isTrue);
    });

    test('every read endpoint parses into app models', () async {
      final dubai = (await c.read(propertiesProvider.future)).firstWhere((p) => p.currency == 'AED');
      c.read(actionsProvider).selectUnit(dubai.id);
      for (final bucket in ['upcoming', 'inside', 'history']) {
        await c.read(visitorsProvider(bucket).future);
      }
      final helpers = await c.read(dailyHelpProvider.future);
      expect(helpers, isNotEmpty);
      await c.read(helperProvider(helpers.first.id).future);
      await c.read(helperAttendanceProvider(helpers.first.id).future);
      await c.read(helperReviewsProvider(helpers.first.id).future);
      for (final p in <FutureProvider<List<Object>>>[
        familyProvider, vehiclesProvider, petsProvider, frequentEntriesProvider, emergencyContactsProvider,
        duesProvider, paymentsProvider, noticesProvider, pollsProvider, eventsProvider, forumProvider,
        classifiedsProvider, vendorsProvider, residentsProvider, staffProvider, ticketCategoriesProvider, ticketsProvider,
        notificationsProvider,
      ]) {
        await c.read(p.future);
      }
      await c.read(duesSummaryProvider.future);
      await c.read(statementProvider.future);
      final posts = await c.read(forumProvider.future);
      await c.read(forumRepliesProvider(posts.first.id).future);
      expect(await c.read(searchProvider('Fatima').future), isNotEmpty);
      expect((await c.read(userSettingsProvider.future)).keys, containsAll(['notification_prefs', 'privacy_prefs']));
    });

    test('write actions: invite, pay, ticket, vote, chat', () async {
      final dubai = (await c.read(propertiesProvider.future)).firstWhere((p) => p.currency == 'AED');
      final a = c.read(actionsProvider)..selectUnit(dubai.id);

      final v = await a.preApprove({'name': 'Live Test Guest', 'visitor_type': 'guest', 'guests': 1});
      expect(v.passCode.length, 6);
      await a.visitorAction(v.id, 'cancel');

      final dues = await c.read(duesProvider.future);
      if (dues.isNotEmpty) {
        final checkout = await a.checkout([dues.first.id], 'card');
        final paid = await a.confirmMockPayment(checkout.paymentId);
        expect(paid.status, 'success');
        expect(paid.currency, 'AED');
      }

      final cat = (await c.read(ticketCategoriesProvider.future)).first;
      final ticket = await a.createTicket(cat.id, 'Live test ticket', 'from Flutter test', 'Low');
      expect(ticket.number, startsWith('T-'));

      final open = (await c.read(pollsProvider.future)).where((p) => !p.isClosed && p.myVote == null);
      if (open.isNotEmpty) {
        await a.vote(open.first.id, open.first.options.first.id);
        final updated = (await c.read(pollsProvider.future)).firstWhere((p) => p.id == open.first.id);
        expect(updated.myVote, open.first.options.first.id);
      }

      final meera = (await c.read(residentsProvider.future)).firstWhere((p) => p.name == 'Meera Shah');
      final conv = await a.startConversation(meera.userId!);
      await a.sendMessage(conv.id, 'Hello from the live test');
      expect((await c.read(chatMessagesProvider(conv.id).future)).last.text, 'Hello from the live test');
    });

    testWidgets('sign up from the login screen through OTP to join community', (tester) async {
      HttpOverrides.global = null;
      tester.view.physicalSize = const Size(390 * 3, 900 * 3);
      tester.view.devicePixelRatio = 3;
      addTearDown(tester.view.reset);
      final fresh = ProviderContainer(
        overrides: [tokenStoreProvider.overrideWithValue(TokenStore(persistent: false))],
        retry: (_, _) => null,
      );
      addTearDown(fresh.dispose);
      Future<void> settle() async {
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
          await tester.pump(const Duration(milliseconds: 100));
        }
      }

      appRouter.go(Routes.login);
      await tester.pumpWidget(UncontrolledProviderScope(container: fresh, child: const GlobacityApp()));
      await settle();
      await tester.ensureVisible(find.text('Sign up'));
      await tester.pump();
      await tester.tap(find.text('Sign up'));
      await settle();
      expect(find.text('Create your account'), findsOneWidget);

      final digits = (DateTime.now().millisecondsSinceEpoch % 10000000).toString().padLeft(7, '0');
      final fields = find.byType(TextFormField);
      await tester.enterText(fields.at(0), 'Widget Signup');
      await tester.enterText(fields.at(1), '50$digits');
      await tester.enterText(fields.at(2), 'widget$digits@example.com');
      await tester.enterText(fields.at(3), 'Signup@12345');
      await tester.enterText(fields.at(4), 'Signup@12345');
      await tester.tap(find.byType(Checkbox));
      await tester.pump();
      await tester.ensureVisible(find.text('Continue'));
      await tester.tap(find.text('Continue'));
      await settle();
      expect(find.text("Verify it's you"), findsOneWidget, reason: 'OTP screen should open');

      await tester.tap(find.textContaining('Development code'));
      await tester.pump();
      await tester.tap(find.text('Verify & continue'));
      await settle();
      await settle();
      expect(find.text('Find your community'), findsOneWidget, reason: 'new user should be asked to join a community');
      expect(fresh.read(userProvider).name, 'Widget Signup');
      expect(fresh.read(userProvider).email, 'widget$digits@example.com');

      await tester.pumpWidget(const SizedBox());
      await tester.pump(const Duration(seconds: 4));
    });

    // Opens every screen with live data on a phone-sized viewport.
    const routes = [
      Routes.home, Routes.visitors, Routes.community, Routes.payments, Routes.profile, Routes.invite,
      Routes.household, '${Routes.household}?tab=2', Routes.notices, Routes.polls, Routes.events, Routes.forum,
      Routes.directory, Routes.classifieds, Routes.homestore, Routes.moveRequest, Routes.helpdesk, Routes.newTicket,
      Routes.sos, Routes.emergencyContacts, Routes.kidExit, Routes.notifications, Routes.search, Routes.editProfile,
      Routes.notificationSettings, Routes.privacySettings, '${Routes.joinCommunity}?first=0',
    ];
    for (final route in routes) {
      testWidgets('screen $route renders live data', (tester) async {
        HttpOverrides.global = null;
        tester.view.physicalSize = const Size(390 * 3, 844 * 3);
        tester.view.devicePixelRatio = 3;
        addTearDown(tester.view.reset);
        final dubai = (await tester.runAsync(() => c.read(propertiesProvider.future)))!
            .firstWhere((p) => p.currency == 'AED');
        c.read(actionsProvider).selectUnit(dubai.id);

        final errors = <String>[];
        final previous = FlutterError.onError;
        FlutterError.onError = (d) {
          final where = d.toString().split('\n').where((l) => l.contains('/lib/')).take(2).join(' | ');
          errors.add('${d.exceptionAsString().split('\n').first} @ $where');
        };
        appRouter.go(route);
        await tester.pumpWidget(UncontrolledProviderScope(container: c, child: const GlobacityApp()));
        for (var i = 0; i < 6; i++) {
          await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 250)));
          await tester.pump(const Duration(milliseconds: 100));
        }
        FlutterError.onError = previous;
        expect(errors, isEmpty);
        expect(find.text("Couldn't load"), findsNothing, reason: 'a request failed on $route');
        if (route == Routes.payments) expect(find.textContaining('AED'), findsWidgets);
        await tester.pumpWidget(const SizedBox());
        await tester.pump(const Duration(seconds: 4)); // let idle HTTP keep-alive timers expire
      });
    }
  });
}
