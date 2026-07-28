import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../models/analytics_models.dart';
import '../../state/analytics_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_main.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/stat_card.dart';

/// Net-new screen — the HTML source has no org-wide/admin dashboard (it's
/// a single-user tool with no accounts). Built using the one real
/// analytics data source the backend has today
/// (GET /api/v1/analytics/learning — Phase 5 Part K), styled with the
/// same stat-card/card language as the rest of the app.
///
/// Several metrics from the original spec (documents processed, queue
/// status, active users, organization/license usage) have no backend
/// endpoint yet — rather than fabricate numbers for them, this screen
/// only shows what's real and says so for the rest.
class DashboardScreen extends ConsumerWidget {
  const DashboardScreen({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final analyticsAsync = ref.watch(learningAnalyticsProvider);

    return AppShell(
      body: AppMain(
        child: analyticsAsync.when(
          data: (analytics) => _DashboardContent(analytics: analytics),
          loading: () => const Padding(
            padding: EdgeInsets.only(top: 100),
            child: Center(child: CircularProgressIndicator(color: AppColors.accent)),
          ),
          error: (error, _) => AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text(
                  'Could not load dashboard data',
                  style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.heading),
                ),
                const SizedBox(height: 6),
                Text('$error', style: TextStyle(fontSize: 12.5, color: AppColors.muted)),
                const SizedBox(height: 14),
                OutlinedButton(
                  onPressed: () => ref.invalidate(learningAnalyticsProvider),
                  child: const Text('Retry'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _DashboardContent extends StatelessWidget {
  const _DashboardContent({required this.analytics});

  final LearningAnalytics analytics;

  @override
  Widget build(BuildContext context) {
    final pct = NumberFormat.percent();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppCardHeader(
                icon: '📊',
                title: 'Dashboard',
                subtitle: 'System-wide accuracy and learning trends, computed from real processing history',
              ),
              Wrap(
                spacing: 12,
                runSpacing: 12,
                children: [
                  _statTile('OCR Accuracy', pct.format(analytics.ocrAccuracyProxy), AppColors.accent),
                  _statTile('Parser Accuracy', pct.format(analytics.parserAccuracyProxy), AppColors.green),
                  _statTile('Manual Correction Rate', pct.format(analytics.manualCorrectionRate), AppColors.orange),
                  _statTile('Avg. Confidence', pct.format(analytics.averageConfidence), AppColors.info),
                  _statTile('Template Hit Rate', pct.format(analytics.templateHitRate), AppColors.accent),
                ],
              ),
            ],
          ),
        ),
        AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppCardHeader(
                icon: '📈',
                title: 'Corrections Over Time',
                subtitle: 'Daily manual-correction volume — the learning engine\'s raw feedback signal',
              ),
              SizedBox(
                height: 220,
                child: analytics.correctionsByDay.isEmpty
                    ? const _EmptyChartState()
                    : _CorrectionsBarChart(data: analytics.correctionsByDay),
              ),
            ],
          ),
        ),
        Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Expanded(
              child: AppCard(
                margin: const EdgeInsets.only(right: 9, bottom: 18),
                child: _RankedList(
                  icon: '🎯',
                  title: 'Most Corrected Fields',
                  subtitle: 'Where reviewers intervene most often',
                  entries: analytics.mostCorrectedFields,
                ),
              ),
            ),
            Expanded(
              child: AppCard(
                margin: const EdgeInsets.only(left: 9, bottom: 18),
                child: _RankedList(
                  icon: '🧩',
                  title: 'Most Problematic Templates',
                  subtitle: 'Templates generating the most corrections',
                  entries: analytics.mostProblematicTemplates,
                ),
              ),
            ),
          ],
        ),
        AppCard(
          margin: EdgeInsets.zero,
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text('ℹ️', style: TextStyle(fontSize: 16)),
              const SizedBox(width: 10),
              Expanded(
                child: Text(
                  'Documents-processed count, queue status, active users, and organization/license '
                  'usage aren\'t wired up yet — those need small new read-only backend endpoints. '
                  'This dashboard only shows metrics with a real data source today.',
                  style: TextStyle(fontSize: 12.5, color: AppColors.muted, height: 1.5),
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _statTile(String label, String value, Color color) {
    return SizedBox(
      width: 210,
      child: StatCard(label: label, value: value, valueColor: color),
    );
  }
}

class _EmptyChartState extends StatelessWidget {
  const _EmptyChartState();

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const Text('📂', style: TextStyle(fontSize: 32)),
          const SizedBox(height: 8),
          Text('No corrections recorded yet.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
        ],
      ),
    );
  }
}

class _CorrectionsBarChart extends StatelessWidget {
  const _CorrectionsBarChart({required this.data});

  final List<(String, int)> data;

  @override
  Widget build(BuildContext context) {
    final maxY = data.map((e) => e.$2).fold<int>(0, (a, b) => a > b ? a : b).toDouble();
    return BarChart(
      BarChartData(
        maxY: maxY <= 0 ? 1 : maxY * 1.2,
        barTouchData: BarTouchData(enabled: true),
        titlesData: FlTitlesData(
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 32, getTitlesWidget: (value, meta) {
              return Text(value.toInt().toString(), style: TextStyle(fontSize: 10, color: AppColors.muted));
            }),
          ),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 28,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= data.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 6),
                  child: Text(data[i].$1, style: TextStyle(fontSize: 9, color: AppColors.muted)),
                );
              },
            ),
          ),
        ),
        gridData: FlGridData(show: true, drawVerticalLine: false, getDrawingHorizontalLine: (_) {
          return const FlLine(color: AppColors.border, strokeWidth: 1);
        }),
        borderData: FlBorderData(show: false),
        barGroups: [
          for (var i = 0; i < data.length; i++)
            BarChartGroupData(
              x: i,
              barRods: [
                BarChartRodData(
                  toY: data[i].$2.toDouble(),
                  color: AppColors.accent,
                  width: 14,
                  borderRadius: BorderRadius.circular(3),
                ),
              ],
            ),
        ],
      ),
    );
  }
}

class _RankedList extends StatelessWidget {
  const _RankedList({required this.icon, required this.title, required this.subtitle, required this.entries});

  final String icon;
  final String title;
  final String subtitle;
  final List<(String, int)> entries;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        AppCardHeader(icon: icon, title: title, subtitle: subtitle),
        if (entries.isEmpty)
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 12),
            child: Text('Nothing recorded yet.', style: TextStyle(color: AppColors.muted, fontSize: 13)),
          )
        else
          for (final entry in entries.take(8))
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 6),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      entry.$1,
                      overflow: TextOverflow.ellipsis,
                      style: const TextStyle(fontSize: 13, color: AppColors.text),
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 2),
                    decoration: BoxDecoration(
                      color: AppColors.accentSubtle,
                      borderRadius: BorderRadius.circular(20),
                    ),
                    child: Text(
                      '${entry.$2}',
                      style: const TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.heading),
                    ),
                  ),
                ],
              ),
            ),
      ],
    );
  }
}

/// Minimal percent formatter — avoids pulling in intl just for this.
class NumberFormat {
  NumberFormat.percent();

  String format(double value) => '${(value * 100).toStringAsFixed(1)}%';
}
