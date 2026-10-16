class NudgeConfig {
  const NudgeConfig({
    this.enabled = true,
    this.cooldownMinutes = 15,
    this.quietHoursEnabled = false,
    this.quietHoursStartMinutes = 22 * 60,
    this.quietHoursEndMinutes = 7 * 60,
    this.startAtLogin = true,
    this.showTextInNotifications = true,
  });

  final bool enabled;
  final int cooldownMinutes;
  final bool quietHoursEnabled;
  final int quietHoursStartMinutes;
  final int quietHoursEndMinutes;
  final bool startAtLogin;
  final bool showTextInNotifications;

  bool get quietHoursCrossesMidnight =>
      quietHoursStartMinutes > quietHoursEndMinutes;

  bool isWithinQuietHours(DateTime now) {
    if (!quietHoursEnabled) return false;
    final minutes = now.hour * 60 + now.minute;
    if (quietHoursCrossesMidnight) {
      return minutes >= quietHoursStartMinutes ||
          minutes < quietHoursEndMinutes;
    }
    return minutes >= quietHoursStartMinutes && minutes < quietHoursEndMinutes;
  }

  NudgeConfig copyWith({
    bool? enabled,
    int? cooldownMinutes,
    bool? quietHoursEnabled,
    int? quietHoursStartMinutes,
    int? quietHoursEndMinutes,
    bool? startAtLogin,
    bool? showTextInNotifications,
  }) {
    return NudgeConfig(
      enabled: enabled ?? this.enabled,
      cooldownMinutes: cooldownMinutes ?? this.cooldownMinutes,
      quietHoursEnabled: quietHoursEnabled ?? this.quietHoursEnabled,
      quietHoursStartMinutes:
          quietHoursStartMinutes ?? this.quietHoursStartMinutes,
      quietHoursEndMinutes: quietHoursEndMinutes ?? this.quietHoursEndMinutes,
      startAtLogin: startAtLogin ?? this.startAtLogin,
      showTextInNotifications:
          showTextInNotifications ?? this.showTextInNotifications,
    );
  }

  Map<String, dynamic> toJson() => {
    'enabled': enabled,
    'cooldownMinutes': cooldownMinutes,
    'quietHoursEnabled': quietHoursEnabled,
    'quietHoursStartMinutes': quietHoursStartMinutes,
    'quietHoursEndMinutes': quietHoursEndMinutes,
    'startAtLogin': startAtLogin,
    'showTextInNotifications': showTextInNotifications,
  };

  factory NudgeConfig.fromJson(Map<String, dynamic> json) => NudgeConfig(
    enabled: json['enabled'] as bool? ?? true,
    cooldownMinutes: json['cooldownMinutes'] as int? ?? 15,
    quietHoursEnabled: json['quietHoursEnabled'] as bool? ?? false,
    quietHoursStartMinutes: json['quietHoursStartMinutes'] as int? ?? 22 * 60,
    quietHoursEndMinutes: json['quietHoursEndMinutes'] as int? ?? 7 * 60,
    startAtLogin: json['startAtLogin'] as bool? ?? true,
    showTextInNotifications: json['showTextInNotifications'] as bool? ?? true,
  );

  static const minCooldownMinutes = 1;
  static const maxCooldownMinutes = 240;
}
