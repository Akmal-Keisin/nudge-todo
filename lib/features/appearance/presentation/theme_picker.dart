import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/theme/theme_catalog.dart';
import '../../settings/presentation/settings_section.dart';
import '../application/appearance_providers.dart';
import '../domain/app_theme_id.dart';
import 'theme_mode_mapping.dart';

/// Appearance settings: light/dark/system plus a grid of curated palettes.
/// Changes apply immediately, so the whole screen is the preview.
class ThemePickerSection extends ConsumerWidget {
  const ThemePickerSection({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final appearance = ref.watch(appearanceProvider);

    return SettingsSection(
      title: 'Appearance',
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: SegmentedButton<AppThemeMode>(
            segments: [
              for (final mode in AppThemeMode.values)
                ButtonSegment<AppThemeMode>(
                  value: mode,
                  label: Text(mode.label),
                ),
            ],
            selected: {appearance.mode},
            showSelectedIcon: false,
            onSelectionChanged: (selection) =>
                _setMode(context, ref, selection.first),
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: LayoutBuilder(
            builder: (context, constraints) {
              final columns = constraints.maxWidth >= 520 ? 3 : 2;
              const spacing = 12.0;
              final width =
                  (constraints.maxWidth - spacing * (columns - 1)) / columns;
              return Wrap(
                spacing: spacing,
                runSpacing: spacing,
                children: [
                  for (final preset in themePresets)
                    SizedBox(
                      width: width,
                      child: _ThemeCard(
                        preset: preset,
                        selected: appearance.theme == preset.id,
                        onTap: () => _setTheme(context, ref, preset.id),
                      ),
                    ),
                ],
              );
            },
          ),
        ),
      ],
    );
  }

  Future<void> _setMode(
    BuildContext context,
    WidgetRef ref,
    AppThemeMode mode,
  ) async {
    // Captured before the await so the callback never touches a stale context.
    final messenger = ScaffoldMessenger.of(context);
    final failure = await ref.read(appearanceProvider.notifier).setMode(mode);
    if (failure != null) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }

  Future<void> _setTheme(
    BuildContext context,
    WidgetRef ref,
    AppThemeId id,
  ) async {
    final messenger = ScaffoldMessenger.of(context);
    final failure = await ref.read(appearanceProvider.notifier).setTheme(id);
    if (failure != null) {
      messenger.showSnackBar(SnackBar(content: Text(failure.message)));
    }
  }
}

class _ThemeCard extends StatelessWidget {
  const _ThemeCard({
    required this.preset,
    required this.selected,
    required this.onTap,
  });

  final ThemePreset preset;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final swatches = previewSwatches(preset.id);

    return Semantics(
      selected: selected,
      button: true,
      label: '${preset.label} theme',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          padding: const EdgeInsets.all(10),
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: selected ? scheme.primary : scheme.outlineVariant,
              width: selected ? 2 : 1,
            ),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              ClipRRect(
                borderRadius: BorderRadius.circular(10),
                child: SizedBox(
                  height: 44,
                  child: Row(
                    children: [
                      for (final color in swatches)
                        Expanded(child: ColoredBox(color: color)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: Text(
                      preset.label,
                      style: theme.textTheme.labelLarge,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selected)
                    Icon(Icons.check_circle, size: 18, color: scheme.primary),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
