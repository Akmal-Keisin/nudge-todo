import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:nudge/app/nudge_app.dart';
import 'package:nudge/app/theme/theme_catalog.dart';
import 'package:nudge/core/platform/noop_nudge_platform.dart';
import 'package:nudge/core/platform/platform_providers.dart';
import 'package:nudge/features/appearance/application/appearance_providers.dart';
import 'package:nudge/features/appearance/domain/app_theme_id.dart';
import 'package:nudge/features/appearance/domain/appearance_settings.dart';
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

  Future<void> pumpNudge(
    WidgetTester tester,
    Widget app, {
    Size size = const Size(390, 844),
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    await tester.pumpWidget(app);
    await tester.pumpAndSettle();
  }

  testWidgets('renders both tabs and the composer', (tester) async {
    await pumpNudge(tester, buildApp());

    expect(find.text('Active'), findsOneWidget);
    expect(find.text('Archive'), findsOneWidget);
    expect(find.text('Add a todo...'), findsOneWidget);
  });

  testWidgets('adding a todo shows it in the list', (tester) async {
    await pumpNudge(tester, buildApp());

    await tester.enterText(find.byType(TextField).first, 'Buy milk');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    expect(find.text('Buy milk'), findsOneWidget);
  });

  testWidgets('switching tabs shows only that tab\'s todos', (tester) async {
    await pumpNudge(tester, buildApp());

    await tester.enterText(find.byType(TextField).first, 'Keep me');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextField).first, 'File me away');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await tester.pumpAndSettle();

    // Newest first, so the first checkbox belongs to "File me away".
    await tester.tap(find.byType(Checkbox).first);
    await tester.pumpAndSettle();

    expect(find.text('Keep me'), findsOneWidget);
    expect(find.text('File me away'), findsNothing);

    await tester.tap(find.text('Archive'));
    await tester.pumpAndSettle();
    expect(find.text('File me away'), findsOneWidget);
    expect(find.text('Keep me'), findsNothing);

    await tester.tap(find.text('Active'));
    await tester.pumpAndSettle();
    expect(find.text('Keep me'), findsOneWidget);
    expect(find.text('File me away'), findsNothing);
  });

  testWidgets('the selected theme and mode drive MaterialApp', (tester) async {
    final container = ProviderContainer(
      overrides: [
        nudgePlatformProvider.overrideWithValue(NoopNudgePlatform()),
        initialAppearanceProvider.overrideWithValue(
          const AppearanceSettings(
            theme: AppThemeId.grape,
            mode: AppThemeMode.dark,
          ),
        ),
      ],
    );
    addTearDown(container.dispose);

    await pumpNudge(
      tester,
      UncontrolledProviderScope(container: container, child: const NudgeApp()),
    );

    final app = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(app.themeMode, ThemeMode.dark);
    expect(
      app.theme?.colorScheme.primary,
      colorSchemeFor(AppThemeId.grape, Brightness.light).primary,
    );
    expect(
      app.darkTheme?.colorScheme.primary,
      colorSchemeFor(AppThemeId.grape, Brightness.dark).primary,
    );

    await container
        .read(appearanceProvider.notifier)
        .setMode(AppThemeMode.light);
    await tester.pumpAndSettle();

    final updated = tester.widget<MaterialApp>(find.byType(MaterialApp));
    expect(updated.themeMode, ThemeMode.light);
  });

  testWidgets('picking a theme in Settings updates the appearance', (
    tester,
  ) async {
    final container = ProviderContainer(
      overrides: [nudgePlatformProvider.overrideWithValue(NoopNudgePlatform())],
    );
    addTearDown(container.dispose);

    await pumpNudge(
      tester,
      UncontrolledProviderScope(container: container, child: const NudgeApp()),
    );

    await tester.tap(find.byIcon(Icons.settings));
    await tester.pumpAndSettle();

    expect(find.text('Appearance'), findsOneWidget);
    expect(container.read(appearanceProvider).theme, AppThemeId.ocean);

    await tester.tap(find.text('Grape'));
    await tester.pumpAndSettle();

    expect(container.read(appearanceProvider).theme, AppThemeId.grape);
  });
}
