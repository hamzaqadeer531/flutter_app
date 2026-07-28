import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Matches the HTML source's `.card` class: panel background, 1px
/// border, 8px radius, drop shadow, 22px padding, 18px bottom margin.
class AppCard extends StatelessWidget {
  const AppCard({super.key, required this.child, this.margin});

  final Widget child;
  final EdgeInsetsGeometry? margin;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: margin ?? const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.all(22),
      decoration: BoxDecoration(
        color: AppColors.panel,
        borderRadius: BorderRadius.circular(AppColors.radius),
        border: Border.all(color: AppColors.border, width: 1),
        boxShadow: AppColors.shadow,
      ),
      child: child,
    );
  }
}

/// Matches `.card-hdr` + `.card-ico` + `.card-title` + `.card-sub`: an
/// icon chip, a bold title, and a muted subtitle, with a bottom divider.
class AppCardHeader extends StatelessWidget {
  const AppCardHeader({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.iconBackground,
  });

  final String icon;
  final String title;
  final String? subtitle;
  final Color? iconBackground;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(bottom: 18),
      padding: const EdgeInsets.only(bottom: 14),
      decoration: const BoxDecoration(
        border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.center,
        children: [
          Container(
            width: 34,
            height: 34,
            alignment: Alignment.center,
            decoration: BoxDecoration(
              color: iconBackground ?? AppColors.accentSubtle,
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(icon, style: const TextStyle(fontSize: 18)),
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.heading),
                ),
                if (subtitle != null) ...[
                  const SizedBox(height: 1),
                  Text(subtitle!, style: TextStyle(fontSize: 12, color: AppColors.muted)),
                ],
              ],
            ),
          ),
        ],
      ),
    );
  }
}
