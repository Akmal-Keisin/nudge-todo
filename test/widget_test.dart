import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/app/nudge_app.dart';
import 'package:nudge/core/platform/noop_nudge_platform.dart';
import 'package:nudge/core/platform/platform_providers.dart';
import 'package:shared_preferences_platform_interface/in_memory_shared_preferences_async.dart';
import 'package:shared_preferences_platform_interface/shared_preferences_async_platform_interface.dart';

void main() {
  setUp(() {
    SharedPreferencesAsyncPlatform.instance =
        InMemorySharedPreferencesAsync.empty();
  });

  ProviderScope buildApp() {
    return ProviderScope(
      overrides: [nudgePlatformProvider.overrideWithValue(NoopNudgePlatform())],
      child: const NudgeApp(),
    );
  }

  testWidgets('renders both tabs and the composer', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Add a todo...'), findsOneWidget);
  });

  testWidgets('adding a todo shows it in the list', (tester) async {
    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'Buy milk');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Buy milk'), findsOneWidget);
  });
}
