import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../../core/errors/app_failure.dart';
import '../../../core/network/dio_provider.dart';
import '../../../core/platform/android_nudge_platform.dart';
import '../../../core/platform/platform_providers.dart';
import '../../settings/application/settings_providers.dart';
import '../../settings/domain/api_settings.dart';
import '../application/nudge_providers.dart';
import '../domain/nudge_config.dart';

class SettingsScreen extends ConsumerWidget {
  const SettingsScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final configAsync = ref.watch(nudgeConfigProvider);

    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 720),
          child: configAsync.when(
            data: (config) => _SettingsBody(config: config),
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(child: Text('Could not load settings: $e')),
          ),
        ),
      ),
    );
  }
}

class _SettingsBody extends ConsumerWidget {
  const _SettingsBody({required this.config});

  final NudgeConfig config;

  void _update(WidgetRef ref, NudgeConfig next) {
    ref.read(nudgeConfigProvider.notifier).save(next);
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
    _update(
      ref,
      isStart
          ? config.copyWith(quietHoursStartMinutes: minutes)
          : config.copyWith(quietHoursEndMinutes: minutes),
    );
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

    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        _Section(
          title: 'Nudge',
          children: [
            SwitchListTile(
              title: const Text('Show me my todos'),
              subtitle: const Text('On boot, login and unlock'),
              value: config.enabled,
              onChanged: (v) => _update(ref, config.copyWith(enabled: v)),
            ),
            SwitchListTile(
              title: const Text('Start at login / boot'),
              value: config.startAtLogin,
              onChanged: (v) => _update(ref, config.copyWith(startAtLogin: v)),
            ),
            ListTile(
              title: const Text('Cooldown'),
              subtitle: Slider(
                value: config.cooldownMinutes.toDouble(),
                min: NudgeConfig.minCooldownMinutes.toDouble(),
                max: NudgeConfig.maxCooldownMinutes.toDouble(),
                divisions:
                    NudgeConfig.maxCooldownMinutes -
                    NudgeConfig.minCooldownMinutes,
                label: '${config.cooldownMinutes} min',
                onChanged: (v) =>
                    _update(ref, config.copyWith(cooldownMinutes: v.round())),
              ),
              trailing: Text('${config.cooldownMinutes} min'),
            ),
            SwitchListTile(
              title: const Text('Quiet hours'),
              subtitle: const Text('No nudges during this window'),
              value: config.quietHoursEnabled,
              onChanged: (v) =>
                  _update(ref, config.copyWith(quietHoursEnabled: v)),
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
        ),
        _Section(
          title: 'Privacy',
          children: [
            SwitchListTile(
              title: const Text('Show todo text in notifications'),
              subtitle: const Text('Off shows only the count'),
              value: config.showTextInNotifications,
              onChanged: (v) =>
                  _update(ref, config.copyWith(showTextInNotifications: v)),
            ),
          ],
        ),
        const _ServerSection(),
        if (isAndroid) const _AndroidOnboardingSection(),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});

  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
            child: Text(title, style: Theme.of(context).textTheme.titleMedium),
          ),
          ...children,
          const SizedBox(height: 8),
        ],
      ),
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

    return _Section(
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
    await ref
        .read(apiSettingsProvider.notifier)
        .save(
          ApiSettings(
            baseUrl: _urlController.text.trim(),
            token: _tokenController.text.trim(),
          ),
        );
    if (!mounted) return;
    setState(() {
      _status = 'Saved.';
      _statusIsError = false;
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

    return _Section(
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
            decoration: const InputDecoration(
              labelText: 'Server URL',
              hintText: 'https://nudge.example.com',
              border: OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ),
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
          child: TextField(
            controller: _tokenController,
            obscureText: !_revealToken,
            autocorrect: false,
            enableSuggestions: false,
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
                onPressed: _testing ? null : _test,
                child: Text(_testing ? 'Testing...' : 'Test connection'),
              ),
              const SizedBox(width: 12),
              OutlinedButton(onPressed: _save, child: const Text('Save')),
            ],
          ),
        ),
      ],
    );
  }
}
