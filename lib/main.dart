import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/app.dart';

void main() {
  // Failed requests show an error with a Retry button instead of retrying silently.
  runApp(ProviderScope(retry: (_, _) => null, child: const GlobacityApp()));
}
