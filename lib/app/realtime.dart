import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:web_socket_channel/web_socket_channel.dart';

import '../core/config/env.dart';
import '../data/guard.dart';
import '../data/providers.dart';
import 'router.dart';

final scaffoldMessengerKey = GlobalKey<ScaffoldMessengerState>();

/// Live notifications over WebSocket: refreshes affected data and shows an in-app banner.
class Realtime {
  Realtime(this.ref);

  final Ref ref;
  WebSocketChannel? _channel;
  StreamSubscription<dynamic>? _sub;
  Timer? _retry;
  bool _active = false;

  void start() {
    if (_active) return;
    _active = true;
    _connect();
  }

  void stop() {
    _active = false;
    _retry?.cancel();
    _sub?.cancel();
    _channel?.sink.close();
    _channel = null;
  }

  void _connect() {
    final token = ref.read(tokenStoreProvider).access;
    if (!_active || token == null) return;
    try {
      final channel = WebSocketChannel.connect(Uri.parse('${Env.wsUrl}?token=$token'));
      _channel = channel;
      // A failed handshake (server restarting, offline) must not surface as an uncaught error: just retry.
      channel.ready.catchError((_) {});
      _sub = channel.stream.listen(_onMessage, onDone: _reconnectLater, onError: (_) => _reconnectLater(),
          cancelOnError: true);
    } catch (_) {
      _reconnectLater();
    }
  }

  void _reconnectLater() {
    _sub?.cancel();
    _channel = null;
    if (!_active) return;
    _retry?.cancel();
    _retry = Timer(const Duration(seconds: 5), _connect);
  }

  void _onMessage(dynamic raw) {
    final msg = jsonDecode(raw as String) as Map<String, dynamic>;
    final data = Map<String, dynamic>.from(msg['data'] as Map? ?? {});
    ref.invalidate(notificationsProvider);
    if (const {'gate', 'security', 'daily_help'}.contains(msg['category'])) invalidateGuardData(ref);
    switch (msg['category']) {
      case 'gate':
        ref.invalidate(visitorsProvider);
        ref.invalidate(contextProvider);
      case 'daily_help':
        ref.invalidate(dailyHelpProvider);
      case 'payment':
        ref.invalidate(duesProvider);
        ref.invalidate(duesSummaryProvider);
        ref.invalidate(paymentsProvider);
      case 'notice':
        ref.invalidate(noticesProvider);
      case 'helpdesk':
        ref.invalidate(ticketsProvider);
        ref.invalidate(ticketProvider);
      case 'message':
        ref.invalidate(chatMessagesProvider);
      case 'community':
        ref.invalidate(propertiesProvider);
    }

    final visitorId = data['visitor_id'] as String?;
    final respond = data['action'] == 'respond' && visitorId != null;
    scaffoldMessengerKey.currentState
      ?..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        duration: Duration(seconds: respond ? 10 : 4),
        content: Text([msg['title'], msg['body']].where((e) => e != null && e != '').join('\n')),
        action: respond
            ? SnackBarAction(label: 'Respond', onPressed: () => appRouter.push(Routes.approval(visitorId)))
            : null,
      ));
  }
}

final realtimeProvider = Provider<Realtime>((ref) {
  final r = Realtime(ref);
  ref.onDispose(r.stop);
  return r;
});
