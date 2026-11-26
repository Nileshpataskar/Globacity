import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

import '../data/models.dart';
import '../features/auth/forgot_password_screen.dart';
import '../features/auth/join_community_screen.dart';
import '../features/auth/login_screen.dart';
import '../features/auth/onboarding_screen.dart';
import '../features/auth/otp_screen.dart';
import '../features/auth/signup_screen.dart';
import '../features/auth/splash_screen.dart';
import '../features/community/classifieds_screen.dart';
import '../features/community/community_screen.dart';
import '../features/community/directory_screen.dart';
import '../features/community/events_screen.dart';
import '../features/community/forum_screens.dart';
import '../features/community/homestore_screen.dart';
import '../features/community/move_request_screen.dart';
import '../features/community/notices_screens.dart';
import '../features/community/polls_screen.dart';
import '../features/helpdesk/helpdesk_screens.dart';
import '../features/home/home_screen.dart';
import '../features/household/helper_detail_screen.dart';
import '../features/household/household_screen.dart';
import '../features/misc/chat_screen.dart';
import '../features/misc/notifications_screen.dart';
import '../features/misc/search_screen.dart';
import '../features/payments/pay_screen.dart';
import '../features/payments/payments_screen.dart';
import '../features/profile/edit_profile_screen.dart';
import '../features/profile/profile_screen.dart';
import '../features/profile/settings_screens.dart';
import '../features/security/emergency_contacts_screen.dart';
import '../features/security/kid_exit_screen.dart';
import '../features/security/sos_screen.dart';
import '../features/shell/main_shell.dart';
import '../features/visitors/approval_screen.dart';
import '../features/visitors/invite_screen.dart';
import '../features/visitors/pass_screen.dart';
import '../features/visitors/visitors_screen.dart';
import '../features/guard/gate_screen.dart';
import '../features/guard/guard_home_screen.dart';
import '../features/guard/guard_lists_screens.dart';
import '../features/guard/guard_more_screen.dart';
import '../features/guard/guard_shell.dart';
import '../features/guard/guard_visitors_screen.dart';
import '../features/guard/incidents_screen.dart';
import '../features/guard/shift_screen.dart';
import '../features/guard/staff_attendance_screen.dart';
import '../features/guard/vehicles_screen.dart';
import '../features/guard/walk_in_screen.dart';
import '../features/manage/manage_kit.dart';
import '../features/manage/manage_screens.dart';
import '../features/manage/resources.dart';

/// All route paths in one place.
class Routes {
  Routes._();

  static const splash = '/';
  static const onboarding = '/onboarding';
  static const login = '/login';
  static const otp = '/otp';
  static const signup = '/signup';
  static const forgotPassword = '/forgot-password';
  static const joinCommunity = '/join-community';

  // Bottom-nav tabs
  static const home = '/home';
  static const visitors = '/visitors';
  static const community = '/community';
  static const payments = '/payments';
  static const profile = '/profile';

  // Full-screen pages
  static const invite = '/invite';
  static String pass(String id) => '/pass/$id';
  static String approval(String id) => '/approval/$id';
  static const household = '/household';
  static String helper(String id) => '/helper/$id';
  static String pay(List<String> dueIds) => '/pay?ids=${dueIds.join(',')}';
  static const notices = '/notices';
  static String notice(String id) => '/notices/$id';
  static const polls = '/polls';
  static const events = '/events';
  static const forum = '/forum';
  static String forumPost(String id) => '/forum/$id';
  static const directory = '/directory';
  static const classifieds = '/classifieds';
  static const homestore = '/homestore';
  static const moveRequest = '/move-request';
  static const helpdesk = '/helpdesk';
  static const newTicket = '/helpdesk/new';
  static String ticket(String id) => '/helpdesk/$id';
  static const sos = '/sos';
  static const emergencyContacts = '/emergency-contacts';
  static const kidExit = '/kid-exit';
  static const notifications = '/notifications';
  static const search = '/search';
  static const editProfile = '/edit-profile';
  static const notificationSettings = '/settings/notifications';
  static const privacySettings = '/settings/privacy';
  static const terms = '/legal/terms';
  static const privacyPolicy = '/legal/privacy';
  static String chat(String conversationId, String name) => '/chat/$conversationId?name=${Uri.encodeComponent(name)}';

  // Guard app (tabs)
  static const guardHome = '/guard/home';
  static const guardGate = '/guard/gate';
  static const guardVisitors = '/guard/visitors';
  static const guardStaff = '/guard/staff';
  static const guardMore = '/guard/more';
  static const guardTabs = {guardHome, guardGate, guardVisitors, guardStaff, guardMore};

  // Guard app (pages)
  static const guardShift = '/guard/shift';
  static const guardScan = '/guard/scan';
  static const guardWalkIn = '/guard/walk-in';
  static const guardVehicles = '/guard/vehicles';
  static const guardIncidents = '/guard/incidents';
  static const guardDirectory = '/guard/directory';
  static const guardKidExits = '/guard/kid-exits';
  static const guardHelpers = '/guard/helpers';

  // Management app (tabs)
  static const manageHome = '/manage/home';
  static const manageResidents = '/manage/residents';
  static const manageFinance = '/manage/finance';
  static const manageHelpdesk = '/manage/helpdesk';
  static const manageMore = '/manage/more';

  // Management app (pages)
  static String manageResource(String key, [int filter = 0, String? tower]) =>
      '/manage/r/$key?f=$filter${tower == null ? '' : '&t=$tower'}';
  static const manageBulkBill = '/manage/bulk-bill';
  static const manageSettings = '/manage/settings';
}

final _rootKey = GlobalKey<NavigatorState>();

GoRoute _page(String path, Widget Function(GoRouterState s) builder, {List<RouteBase> routes = const []}) =>
    GoRoute(path: path, parentNavigatorKey: _rootKey, builder: (_, s) => builder(s), routes: routes);

final appRouter = GoRouter(
  navigatorKey: _rootKey,
  initialLocation: Routes.splash,
  routes: [
    _page(Routes.splash, (_) => const SplashScreen()),
    _page(Routes.onboarding, (_) => const OnboardingScreen()),
    _page(Routes.login, (_) => const LoginScreen()),
    _page(Routes.otp, (s) => OtpScreen(phone: s.uri.queryParameters['to'] ?? '', devCode: s.uri.queryParameters['dev'])),
    _page(Routes.forgotPassword, (_) => const ForgotPasswordScreen()),
    _page(Routes.signup, (_) => const SignupScreen()),
    _page(Routes.joinCommunity, (s) => JoinCommunityScreen(isOnboarding: s.uri.queryParameters['first'] == '1')),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => MainShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: Routes.home, builder: (_, _) => const HomeScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.visitors, builder: (_, _) => const VisitorsScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.community, builder: (_, _) => const CommunityScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.payments, builder: (_, _) => const PaymentsScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.profile, builder: (_, _) => const ProfileScreen())]),
      ],
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => GuardShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: Routes.guardHome, builder: (_, _) => const GuardHomeScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.guardGate, builder: (_, s) => GateScreen(initialCode: s.uri.queryParameters['code']))]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.guardVisitors, builder: (_, _) => const GuardVisitorsScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.guardStaff, builder: (_, _) => const StaffAttendanceScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.guardMore, builder: (_, _) => const GuardMoreScreen())]),
      ],
    ),
    StatefulShellRoute.indexedStack(
      builder: (context, state, shell) => ManageShell(shell: shell),
      branches: [
        StatefulShellBranch(routes: [GoRoute(path: Routes.manageHome, builder: (_, _) => const ManageDashboardScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.manageResidents, builder: (_, _) => const ManageResidentsTab())]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.manageFinance, builder: (_, _) => const ManageFinanceScreen())]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.manageHelpdesk, builder: (_, _) => const ManageHelpdeskTab())]),
        StatefulShellBranch(routes: [GoRoute(path: Routes.manageMore, builder: (_, _) => const ManageMoreScreen())]),
      ],
    ),
    _page('/manage/r/:key', (s) => ResourceListScreen(
          key: ValueKey(s.uri.toString()),
          spec: allResources[s.pathParameters['key']]!,
          initialFilter: int.tryParse(s.uri.queryParameters['f'] ?? '') ?? 0,
          initialTower: s.uri.queryParameters['t'],
        )),
    _page(Routes.manageBulkBill, (_) => const BulkBillScreen()),
    _page(Routes.manageSettings, (_) => const CommunitySettingsScreen()),
    _page(Routes.guardShift, (_) => const ShiftScreen()),
    _page(Routes.guardScan, (_) => const ScanScreen()),
    _page(Routes.guardWalkIn, (s) => WalkInScreen(
          initialType: VisitorType.values.where((t) => t.name == s.uri.queryParameters['type']).firstOrNull,
        )),
    _page(Routes.guardVehicles, (_) => const VehiclesScreen()),
    _page(Routes.guardIncidents, (_) => const IncidentsScreen()),
    _page(Routes.guardDirectory, (_) => const GuardDirectoryScreen()),
    _page(Routes.guardKidExits, (_) => const GuardKidExitsScreen()),
    _page(Routes.guardHelpers, (_) => const GuardHelpersScreen()),
    _page(Routes.invite, (_) => const InviteScreen()),
    _page('/pass/:id', (s) => PassScreen(visitorId: s.pathParameters['id']!)),
    _page('/approval/:id', (s) => ApprovalScreen(visitorId: s.pathParameters['id']!)),
    _page(Routes.household, (s) => HouseholdScreen(initialTab: int.tryParse(s.uri.queryParameters['tab'] ?? '') ?? 0)),
    _page('/helper/:id', (s) => HelperDetailScreen(helperId: s.pathParameters['id']!)),
    _page('/pay', (s) => PayScreen(dueIds: (s.uri.queryParameters['ids'] ?? '').split(',').where((e) => e.isNotEmpty).toList())),
    _page(Routes.notices, (_) => const NoticesScreen(), routes: [
      GoRoute(path: ':id', parentNavigatorKey: _rootKey, builder: (_, s) => NoticeDetailScreen(noticeId: s.pathParameters['id']!)),
    ]),
    _page(Routes.polls, (_) => const PollsScreen()),
    _page(Routes.events, (_) => const EventsScreen()),
    _page(Routes.forum, (_) => const ForumScreen(), routes: [
      GoRoute(path: ':id', parentNavigatorKey: _rootKey, builder: (_, s) => ForumPostScreen(postId: s.pathParameters['id']!)),
    ]),
    _page(Routes.directory, (s) => DirectoryScreen(initialTab: s.uri.queryParameters['tab'] == 'staff' ? 1 : 0)),
    _page(Routes.classifieds, (_) => const ClassifiedsScreen()),
    _page(Routes.homestore, (_) => const HomestoreScreen()),
    _page(Routes.moveRequest, (_) => const MoveRequestScreen()),
    _page(Routes.helpdesk, (_) => const HelpdeskScreen(), routes: [
      GoRoute(path: 'new', parentNavigatorKey: _rootKey, builder: (_, _) => const NewTicketScreen()),
      GoRoute(path: ':id', parentNavigatorKey: _rootKey, builder: (_, s) => TicketDetailScreen(ticketId: s.pathParameters['id']!)),
    ]),
    _page(Routes.sos, (_) => const SosScreen()),
    _page(Routes.emergencyContacts, (_) => const EmergencyContactsScreen()),
    _page(Routes.kidExit, (_) => const KidExitScreen()),
    _page(Routes.notifications, (_) => const NotificationsScreen()),
    _page(Routes.search, (_) => const SearchScreen()),
    _page(Routes.editProfile, (_) => const EditProfileScreen()),
    _page(Routes.notificationSettings, (_) => const NotificationSettingsScreen()),
    _page(Routes.privacySettings, (_) => const PrivacySettingsScreen()),
    _page('/legal/:type', (s) => LegalScreen(isTerms: s.pathParameters['type'] == 'terms')),
    _page('/chat/:id', (s) => ChatScreen(conversationId: s.pathParameters['id']!, name: s.uri.queryParameters['name'] ?? 'Chat')),
  ],
);
