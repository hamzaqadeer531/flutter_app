import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// Matches the HTML source's `.stat`/`.stat-label`/`.stat-val` classes.
class StatCard extends StatelessWidget {
  const StatCard({super.key, required this.label, required this.value, this.valueColor});

  final String label;
  final String value;
  final Color? valueColor;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 15),
      decoration: BoxDecoration(
        color: AppColors.panel,
        border: Border.all(color: AppColors.border),
        borderRadius: BorderRadius.circular(AppColors.radius),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Text(
            label.toUpperCase(),
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.muted, letterSpacing: 0.5),
          ),
          const SizedBox(height: 5),
          Text(
            value,
            style: TextStyle(fontSize: 19, fontWeight: FontWeight.bold, color: valueColor ?? AppColors.heading),
          ),
        ],
      ),
    );
  }
}
