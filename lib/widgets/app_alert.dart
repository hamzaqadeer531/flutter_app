import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

enum AppAlertKind { info, success, warn, error }

/// Matches the HTML source's `.alert` + `.al-info/.al-success/.al-warn/.al-err`:
/// a left-accent-bordered banner with an icon and message.
class AppAlert extends StatelessWidget {
  const AppAlert({super.key, required this.kind, required this.message, this.icon});

  final AppAlertKind kind;
  final String message;
  final String? icon;

  @override
  Widget build(BuildContext context) {
    final (Color bg, Color accent, Color fg, String defaultIcon) = switch (kind) {
      AppAlertKind.info => (const Color(0x1A6FB7FF), AppColors.info, const Color(0xFFBFE0FF), 'ℹ️'),
      AppAlertKind.success => (AppColors.greenSubtle, AppColors.green, AppColors.green, '✅'),
      AppAlertKind.warn => (AppColors.orangeSubtle, AppColors.orange, AppColors.orange, '⚠️'),
      AppAlertKind.error => (AppColors.redSubtle, AppColors.red, AppColors.red, '❌'),
    };

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 11),
      margin: const EdgeInsets.only(bottom: 14),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border(left: BorderSide(color: accent, width: 4)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(icon ?? defaultIcon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(child: Text(message, style: TextStyle(fontSize: 13, color: fg))),
        ],
      ),
    );
  }
}
