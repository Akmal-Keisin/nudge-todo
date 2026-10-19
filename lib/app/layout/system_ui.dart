import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Keeps status-bar icons legible on screens that do not use an AppBar.
SystemUiOverlayStyle nudgeOverlayStyle(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  return (dark ? SystemUiOverlayStyle.light : SystemUiOverlayStyle.dark)
      .copyWith(statusBarColor: Colors.transparent);
}
