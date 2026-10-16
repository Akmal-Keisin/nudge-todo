import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'app/nudge_app.dart';
import 'core/platform/window_setup.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await setUpDesktopWindow();
  runApp(const ProviderScope(child: NudgeApp()));
}
