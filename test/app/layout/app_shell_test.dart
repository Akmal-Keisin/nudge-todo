import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
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

  Future<void> pumpAtSize(
    WidgetTester tester,
    Size size, {
    double textScale = 1.0,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    if (textScale != 1.0) {
      tester.platformDispatcher.textScaleFactorTestValue = textScale;
      addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    }

    await tester.pumpWidget(buildApp());
    await tester.pumpAndSettle();
  }

  Future<void> pressControl(WidgetTester tester, LogicalKeyboardKey key) async {
    await tester.sendKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await tester.sendKeyEvent(key);
    await tester.sendKeyUpEvent(LogicalKeyboardKey.controlLeft);
    await tester.pumpAndSettle();
  }

  testWidgets('compact layout keeps the app-bar tabs', (tester) async {
    await pumpAtSize(tester, const Size(390, 844));

    expect(find.byType(TabBar), findsOneWidget);
    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byKey(const ValueKey('todo-filter-tabs')), findsNothing);
  });

  testWidgets('medium layout uses an in-content filter header', (tester) async {
    await pumpAtSize(tester, const Size(700, 900));

    expect(find.byType(NavigationRail), findsNothing);
    expect(find.byType(TabBar), findsNothing);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const ValueKey('todo-pane-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo-filter-tabs')), findsOneWidget);
    expect(
      tester.getSize(find.byKey(const ValueKey('todo-content'))).width,
      lessThanOrEqualTo(760),
    );
  });

  testWidgets('expanded layout uses the rail and a pane header', (
    tester,
  ) async {
    await pumpAtSize(tester, const Size(1100, 900));

    expect(find.byType(NavigationRail), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    expect(find.byKey(const ValueKey('todo-pane-header')), findsOneWidget);
    expect(find.byKey(const ValueKey('todo-filter-tabs')), findsNothing);
    expect(
      tester.getSize(find.byKey(const ValueKey('todo-content'))).width,
      760,
    );
  });

  testWidgets('the rail switches between lists and settings', (tester) async {
    await pumpAtSize(tester, const Size(1100, 900));

    await tester.tap(find.byKey(const ValueKey('rail-archive')));
    await tester.pumpAndSettle();
    expect(find.text('Nothing archived yet'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('rail-settings')));
    await tester.pumpAndSettle();
    expect(find.text('Appearance'), findsOneWidget);

    await tester.tap(find.byKey(const ValueKey('rail-active')));
    await tester.pumpAndSettle();
    expect(find.text('Add a todo...'), findsOneWidget);
  });

  testWidgets('wide settings use two columns', (tester) async {
    await pumpAtSize(tester, const Size(1200, 900));

    await tester.tap(find.byKey(const ValueKey('rail-settings')));
    await tester.pumpAndSettle();

    final left = find.byKey(const ValueKey('settings-left-column'));
    final right = find.byKey(const ValueKey('settings-right-column'));
    expect(left, findsOneWidget);
    expect(right, findsOneWidget);
    expect(tester.getTopLeft(left).dx, lessThan(tester.getTopLeft(right).dx));
  });

  testWidgets('control shortcuts switch panes', (tester) async {
    await pumpAtSize(tester, const Size(1200, 900));

    await pressControl(tester, LogicalKeyboardKey.digit2);
    expect(find.text('Nothing archived yet'), findsOneWidget);

    await pressControl(tester, LogicalKeyboardKey.comma);
    expect(find.text('Appearance'), findsOneWidget);
  });

  testWidgets('medium layout survives large text', (tester) async {
    await pumpAtSize(tester, const Size(700, 900), textScale: 1.5);

    expect(tester.takeException(), isNull);
  });
}
