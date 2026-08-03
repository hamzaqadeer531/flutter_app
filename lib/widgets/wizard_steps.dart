import 'package:flutter/material.dart';

import '../theme/app_colors.dart';

/// The full 6-step sequence, matching the HTML source's `.steps` bar
/// exactly (HTML feature-parity closure plan, Phase 3) -- every screen
/// that shows WizardSteps passes this same array, with its own index
/// into it and step-tap routing. Client Details (index 1) and Verify &
/// Check (index 3) are their own real screens/routes as of this phase,
/// not folded into Upload/Review the way an earlier pass of this
/// migration originally scoped them.
const wizardStepLabels = [
  'Upload Statement',
  'Client Details',
  'Review Transactions',
  'Verify & Check',
  'Analytics & Insights',
  'Export',
];

/// Matches the HTML source's `.steps`/`.step`/`.step-n` classes — the
/// horizontal step tab bar above the wizard content.
class WizardSteps extends StatelessWidget {
  const WizardSteps({super.key, required this.currentIndex, required this.labels, this.onStepTap});

  final int currentIndex;
  final List<String> labels;
  final ValueChanged<int>? onStepTap;

  @override
  Widget build(BuildContext context) {
    return Container(
      color: AppColors.panel,
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (var i = 0; i < labels.length; i++)
              _StepTab(
                index: i + 1,
                label: labels[i],
                active: i == currentIndex,
                done: i < currentIndex,
                onTap: onStepTap == null ? null : () => onStepTap!(i),
              ),
          ],
        ),
      ),
    );
  }
}

class _StepTab extends StatelessWidget {
  const _StepTab({required this.index, required this.label, required this.active, required this.done, this.onTap});

  final int index;
  final String label;
  final bool active;
  final bool done;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    final color = active ? AppColors.accent : (done ? AppColors.green : AppColors.muted);
    return InkWell(
      onTap: onTap,
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 18, vertical: 13),
        decoration: BoxDecoration(
          border: Border(bottom: BorderSide(color: active || done ? color : Colors.transparent, width: 3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 24,
              height: 24,
              alignment: Alignment.center,
              decoration: BoxDecoration(
                color: active || done ? color : AppColors.gray,
                shape: BoxShape.circle,
              ),
              child: Text(
                '$index',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: active || done ? AppColors.accentOn : AppColors.text,
                ),
              ),
            ),
            const SizedBox(width: 8),
            Text(
              label,
              style: TextStyle(fontSize: 13, color: color, fontWeight: active ? FontWeight.w600 : FontWeight.normal),
            ),
          ],
        ),
      ),
    );
  }
}
