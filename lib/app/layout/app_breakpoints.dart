/// Width-based layout classes. Platform checks are deliberately not used.
enum AppLayout { compact, medium, expanded }

abstract final class AppBreakpoints {
  static const double medium = 600;
  static const double expanded = 840;
  static const double extendedRail = 1200;

  static const double contentMaxWidth = 760;
  static const double settingsMaxWidth = 1000;
  static const double settingsTwoColumnMinWidth = 900;

  static AppLayout layoutFor(double width) {
    if (width >= expanded) return AppLayout.expanded;
    if (width >= medium) return AppLayout.medium;
    return AppLayout.compact;
  }
}
