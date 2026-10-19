import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../app/layout/app_breakpoints.dart';
import '../../../app/layout/pane_header.dart';
import '../../../core/errors/app_failure.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/platform/android_nudge_platform.dart';
import '../../../core/platform/platform_providers.dart';
import '../../appearance/presentation/theme_picker.dart';
import '../../settings/application/settings_providers.dart';
import '../../settings/domain/api_settings.dart';
import '../../settings/presentation/settings_section.dart';
import '../application/nudge_providers.dart';
import '../domain/nudge_config.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({this.embedded = false, super.key});

  /// True when the expanded shell owns navigation and no AppBar is needed.
  final bool embedded;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(nudgeConfigProvider);
    final body = configAsync.when(
      data: (config) => _SettingsBody(config: config),
      loading: () => const Center(child: CircularProgressIndicator()),
      error: (error, _) => Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              error is AppFailure ? error.message : 'Could not load settings.',
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: () => ref.invalidate(nudgeConfigProvider),
              child: const Text('Retry'),
            ),
          ],
        ),
      ),
    );

    if (embedded) {
      return Center(
        child: ConstrainedBox(
          key: const ValueKey('settings-content'),
          constraints: const BoxConstraints(
            maxWidth: AppBreakpoints.settingsMaxWidth,
          ),
          child: Column(
            children: [
              const PaneHeader(
                key: ValueKey('settings-pane-header'),
                title: 'Settings',
                subtitle: 'Nudge behavior, appearance and server',
              ),
              Expanded(child: body),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: body,
        ),
      ),
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  const _SettingsBody({required this.config});

  final NudgeConfig config;

  /// Persists [next] and surfaces a storage failure, so a toggle that cannot be
  /// saved does not silently look saved.
  Future<void> _update(
    BuildContext context,
    WidgetRef ref,
    NudgeConfig next,
  ) async {
    final failure = await ref.read(nudgeConfigProvider.notifier).save(next);
    if (failure == null || !context.mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(failure.message)));
  }

  Future<void> _pickTime(
    BuildContext context,
    WidgetRef ref, {
    required bool isStart,
  }) async {
    final current = isStart
        ? config.quietHoursStartMinutes
        : config.quietHoursEndMinutes;
    final picked = await showTimePicker(
      context: context,
      initialTime: TimeOfDay(hour: current ~/ 60, minute: current % 60),
    );
    if (picked == null) return;
    final minutes = picked.hour * 60 + picked.minute;
    final next = isStart
        ? config.copyWith(quietHoursStartMinutes: minutes)
        : config.copyWith(quietHoursEndMinutes: minutes);

    // An empty window (start == end) would make isWithinQuietHours ambiguous,
    // so refuse it rather than saving something that does nothing.
    if (next.quietHoursStartMinutes == next.quietHoursEndMinutes) {
      if (!context.mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Start and end cannot be the same time.')),
      );
      return;
    }
    if (!context.mounted) return;
    await _update(context, ref, next);
  }

  String _format(int minutes) {
    final h = (minutes ~/ 60).toString().padLeft(2, '0');
    final m = (minutes % 60).toString().padLeft(2, '0');
    return '$h:$m';
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final isAndroid =
        ref.watch(targetPlatformProvider) == TargetPlatform.android;
    const appearance = ThemePickerSection();
    final nudge = _nudgeSection(context, ref);
    final privacy = _privacySection(context, ref);
    const server = _ServerSection();
    final android = isAndroid ? const _AndroidOnboardingSection() : null;

    return LayoutBuilder(
      builder: (context, constraints) {
        final twoColumn =
            constraints.maxWidth >= AppBreakpoints.settingsTwoColumnMinWidth;

        if (!twoColumn) {
          return ListView(
            padding: const EdgeInsets.all(16),
            children: [appearance, nudge, privacy, server, ?android],
          );
        }

        return ListView(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 24),
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Expanded(
                  child: Column(
                    key: const ValueKey('settings-left-column'),
                    children: [appearance, nudge],
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    key: const ValueKey('settings-right-column'),
                    children: [privacy, server, ?android],
                  ),
                ),
              ],
            ),
          ],
        );
      },
    );
  }

  Widget _nudgeSection(BuildContext context, WidgetRef ref) {
    return SettingsSection(
      title: 'Nudge',
      children: [
        SwitchListTile(
          title: const Text('Show me my todos'),
          subtitle: const Text('On boot, login and unlock'),
          value: config.enabled,
          onChanged: (v) => _update(context, ref, config.copyWith(enabled: v)),
        ),
        SwitchListTile(
          title: const Text('Start at login / boot'),
          value: config.startAtLogin,
          onChanged: (v) =>
              _update(context, ref, config.copyWith(startAtLogin: v)),
        ),
        _CooldownSlider(config: config),
        SwitchListTile(
          title: const Text('Quiet hours'),
          subtitle: const Text('No nudges during this window'),
          value: config.quietHoursEnabled,
          onChanged: (v) =>
              _update(context, ref, config.copyWith(quietHoursEnabled: v)),
        ),
        if (config.quietHoursEnabled)
          ListTile(
            title: const Text('Quiet hours window'),
            subtitle: Text(
              '${_format(config.quietHoursStartMinutes)} – '
              '${_format(config.quietHoursEndMinutes)}',
            ),
            trailing: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextButton(
                  onPressed: () => _pickTime(context, ref, isStart: true),
                  child: const Text('Start'),
                ),
                TextButton(
                  onPressed: () => _pickTime(context, ref, isStart: false),
                  child: const Text('End'),
                ),
              ],
            ),
          ),
      ],
    );
  }

  Widget _privacySection(BuildContext context, WidgetRef ref) {
    return SettingsSection(
      title: 'Privacy',
      children: [
        SwitchListTile(
          title: const Text('Show todo text in notifications'),
          subtitle: const Text('Off shows only the count'),
          value: config.showTextInNotifications,
          onChanged: (v) => _update(
            context,
            ref,
            config.copyWith(showTextInNotifications: v),
          ),
        ),
      ],
    );
  }
}

/// The cooldown slider holds the value under the finger locally and only
/// persists on release, so a drag from 1 to 240 does not write to preferences
/// (and the autostart entry) dozens of times.
class _CooldownSlider extends ConsumerStatefulWidget {
  const _CooldownSlider({required this.config});

  final NudgeConfig config;

  @override
  ConsumerState<_CooldownSlider> createState() => _CooldownSliderState();
}

class _CooldownSliderState extends ConsumerState<_CooldownSlider> {
  double? _dragValue;

  Future<void> _commit(double value) async {
    setState(() => _dragValue = null);
    final failure = await ref
        .read(nudgeConfigProvider.notifier)
        .save(widget.config.copyWith(cooldownMinutes: value.round()));
    if (failure == null || !mounted) return;
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(failure.message)));
  }

  @override
  Widget build(BuildContext context) {
    final value = _dragValue ?? widget.config.cooldownMinutes.toDouble();
    return ListTile(
      title: const Text('Cooldown'),
      subtitle: Slider(
        value: value,
        min: NudgeConfig.minCooldownMinutes.toDouble(),
        max: NudgeConfig.maxCooldownMinutes.toDouble(),
        divisions:
            NudgeConfig.maxCooldownMinutes - NudgeConfig.minCooldownMinutes,
        onChanged: (v) => setState(() => _dragValue = v),
        onChangeEnd: _commit,
      ),
      trailing: Text('${value.round()} min'),
    );
  }
}

class _AndroidOnboardingSection extends ConsumerStatefulWidget {
  const _AndroidOnboardingSection();

  @override
  ConsumerState<_AndroidOnboardingSection> createState() =>
      _AndroidOnboardingSectionState();
}

class _AndroidOnboardingSectionState
    extends ConsumerState<_AndroidOnboardingSection> {
  bool? _isHyperOs;

  @override
  void initState() {
    super.initState();
    _detect();
  }

  Future<void> _detect() async {
    final platform = ref.read(nudgePlatformProvider);
    if (platform is AndroidNudgePlatform) {
      final value = await platform.isHyperOs();
      if (mounted) setState(() => _isHyperOs = value);
    }
  }

  AndroidNudgePlatform get _platform =>
      ref.read(nudgePlatformProvider) as AndroidNudgePlatform;

  @override
  Widget build(BuildContext context) {
    final showHyperOsSteps = _isHyperOs ?? false;

    return SettingsSection(
      title: 'Android permissions',
      children: [
        ListTile(
          title: const Text('Notifications'),
          subtitle: const Text('Required for the nudge notification'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _platform.requestNotificationPermission(),
        ),
        ListTile(
          title: const Text('Full-screen intent'),
          subtitle: const Text('Shows Nudge over the lock screen'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => _platform.requestFullScreenIntentPermission(),
        ),
        if (showHyperOsSteps) ...[
          const Divider(),
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
            child: Text(
              'HyperOS needs extra steps, or it will kill Nudge in the '
              'background:',
            ),
          ),
          ListTile(
            title: const Text('1. Enable Autostart'),
            subtitle: const Text('Without this, boot does nothing'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _platform.openAutostartSettings(),
          ),
          ListTile(
            title: const Text('2. Battery: no restrictions'),
            trailing: const Icon(Icons.chevron_right),
            onTap: () => _platform.openBatterySettings(),
          ),
          const ListTile(
            title: Text('3. Battery usage limits: unrestricted'),
            subtitle: Text('Settings › Battery › Battery usage limits'),
          ),
        ],
      ],
    );
  }
}

/// Server connection. Empty URL means the app stays local-only.
class _ServerSection extends ConsumerStatefulWidget {
  const _ServerSection();

  @override
  ConsumerState<_ServerSection> createState() => _ServerSectionState();
}

class _ServerSectionState extends ConsumerState<_ServerSection> {
  final _urlController = TextEditingController();
  final _tokenController = TextEditingController();
  bool _revealToken = false;
  bool _loaded = false;
  bool _testing = false;
  bool _saving = false;
  String? _status;
  bool _statusIsError = false;

  @override
  void initState() {
    super.initState();
    ref.listenManual(apiSettingsProvider, (previous, next) {
      final settings = next.value;
      if (settings != null && !_loaded) _applyToFields(settings);
    });
    final settings = ref.read(apiSettingsProvider).value;
    if (settings != null) _applyToFields(settings);
  }

  void _applyToFields(ApiSettings settings) {
    _urlController.text = settings.baseUrl;
    _tokenController.text = settings.token;
    _loaded = true;
  }

  @override
  void dispose() {
    _urlController.dispose();
    _tokenController.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final settings = ApiSettings(
      baseUrl: _urlController.text.trim(),
      token: _tokenController.text.trim(),
    );

    final validationError = settings.validationError;
    if (validationError != null) {
      setState(() {
        _status = validationError;
        _statusIsError = true;
      });
      return;
    }

    setState(() {
      _saving = true;
      _status = null;
    });

    final failure = await ref.read(apiSettingsProvider.notifier).save(settings);

    if (!mounted) return;
    setState(() {
      _saving = false;
      _status = failure == null ? 'Saved.' : failure.message;
      _statusIsError = failure != null;
    });
  }

  /// Pings the authenticated endpoint, so a success proves both that the
  /// server is reachable and that the token is accepted.
  Future<void> _test() async {
    setState(() {
      _testing = true;
      _status = null;
    });

    final settings = ApiSettings(
      baseUrl: _urlController.text.trim(),
      token: _tokenController.text.trim(),
    );

    String status;
    var isError = true;
    if (!settings.configured) {
      status = 'Enter a server URL first.';
    } else {
      try {
        await ref
            .read(dioProvider)
            .get<void>(
              '${settings.apiBase}/todos',
              options: Options(
                headers: {'Authorization': 'Bearer ${settings.token}'},
              ),
            );
        status = 'Connected.';
        isError = false;
      } on DioException catch (e) {
        status = _describeDioFailure(e);
      } catch (_) {
        status = 'Could not reach the server.';
      }
    }

    if (!mounted) return;
    setState(() {
      _testing = false;
      _status = status;
      _statusIsError = isError;
    });
  }

  String _describeDioFailure(DioException e) {
    final code = e.response?.statusCode;
    return switch (code) {
      401 => const UnauthorizedFailure().message,
      404 => 'Reached the server, but no Nudge API at that path.',
      429 => const RateLimitedFailure().message,
      _ when code != null => 'The server returned $code.',
      _ => const NetworkFailure().message,
    };
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final busy = _testing || _saving;

    return SettingsSection(
      title: 'Server',
      children: [
        const Padding(
          padding: EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Text('Leave the URL empty to keep todos on this device only.'),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _urlController,
            keyboardType: TextInputType.url,
            autocorrect: false,
            textInputAction: TextInputAction.next,
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'https://nudge.example.com',
              border: OutlineInputBorder(),
              isDense: true,
            ),
            onSubmitted: (_) => _save(),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _tokenController,
            obscureText: !_revealToken,
            autocorrect: false,
            enableSuggestions: false,
            textInputAction: TextInputAction.done,
            decoration: InputDecoration(
              labelText: 'API token',
              border: const OutlineInputBorder(),
              isDense: true,
              suffixIcon: IconButton(
                icon: Icon(
                  _revealToken ? Icons.visibility_off : Icons.visibility,
                ),
                tooltip: _revealToken ? 'Hide token' : 'Show token',
                onPressed: () => setState(() => _revealToken = !_revealToken),
              ),
            ),
            onSubmitted: (_) => _save(),
          ),
        ),
        if (_status != null)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
            child: Text(
              _status!,
              style: theme.textTheme.bodyMedium?.copyWith(
                color: _statusIsError
                    ? theme.colorScheme.error
                    : theme.colorScheme.primary,
              ),
            ),
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 12),
          child: Row(
            children: [
              FilledButton(
                onPressed: busy ? null : _test,
                child: Text(_testing ? 'Testing...' : 'Test connection'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(
                onPressed: busy ? null : _save,
                child: Text(_saving ? 'Saving...' : 'Save'),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
