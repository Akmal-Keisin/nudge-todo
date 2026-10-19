import 'package:flutter/material.dart';

/// A page header used by the medium and expanded layouts. It replaces the
/// AppBar so the title, actions and optional filters stay inside the content
/// column instead of spanning the whole window.
class PaneHeader extends StatelessWidget {
  const PaneHeader({
    required this.title,
    this.subtitle,
    this.actions = const [],
    this.tabs,
    super.key,
  });

  final String title;
  final String? subtitle;
  final List<Widget> actions;
  final Widget? tabs;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final subtitle = this.subtitle;
    final tabs = this.tabs;

    return Padding(
      padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: theme.textTheme.headlineSmall?.copyWith(
                        fontWeight: FontWeight.w700,
                        letterSpacing: -0.2,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              ...actions,
            ],
          ),
          if (tabs != null) ...[const SizedBox(height: 14), tabs],
        ],
      ),
    );
  }
}
