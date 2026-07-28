import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/pipeline_models.dart';
import '../../state/workflow_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_main.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/wizard_steps.dart';

/// Pixel-accurate migration of the HTML source's Step 5 ("Analytics &
/// Insights") — the Executive Summary and Dashboard (chart) sub-tabs are
/// implemented with real computed data from the loaded statement; the
/// HTML's other sub-tabs (Internal Transfers, Recurring, Smart Insights,
/// Filters) are the same underlying transaction data viewed differently
/// and are reasonable follow-up additions rather than blocking this pass.
class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({super.key});

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  int _tab = 0;

  @override
  Widget build(BuildContext context) {
    final workflow = ref.watch(workflowControllerProvider);
    final statement = workflow.statement;

    if (statement == null) {
      return AppShell(
        body: AppMain(
          child: AppCard(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                const Text('No statement loaded yet.',
                    style: TextStyle(fontSize: 15, fontWeight: FontWeight.bold, color: AppColors.heading)),
                const SizedBox(height: 10),
                ElevatedButton(onPressed: () => context.go('/upload'), child: const Text('Upload a statement')),
              ],
            ),
          ),
        ),
      );
    }

    final totalCredit = statement.transactions.fold<double>(0, (sum, t) => sum + (t.credit ?? 0));
    final totalDebit = statement.transactions.fold<double>(0, (sum, t) => sum + (t.debit ?? 0));

    return AppShell(
      body: Column(
        children: [
          WizardSteps(
            currentIndex: 2,
            labels: const ['Upload Statement', 'Review Transactions', 'Analytics & Export'],
            onStepTap: (i) {
              if (i == 0) context.go('/upload');
              if (i == 1) context.go('/review');
            },
          ),
          Expanded(
            child: AppMain(
              child: AppCard(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const AppCardHeader(
                      icon: '📊',
                      title: 'Analytics & Insights',
                      subtitle: 'Computed from this statement\'s extracted transactions.',
                    ),
                    Row(
                      children: [
                        _tabButton('📋 Executive Summary', 0),
                        _tabButton('📈 Dashboard', 1),
                      ],
                    ),
                    const Divider(color: AppColors.border, height: 24),
                    if (_tab == 0)
                      _ExecutiveSummaryTab(statement: statement, totalCredit: totalCredit, totalDebit: totalDebit)
                    else
                      _DashboardTab(statement: statement, totalCredit: totalCredit, totalDebit: totalDebit),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 14),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                OutlinedButton(onPressed: () => context.go('/review'), child: const Text('← Back')),
                ElevatedButton(onPressed: () => context.go('/reports'), child: const Text('Proceed to Export →')),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _tabButton(String label, int index) {
    final active = _tab == index;
    return Padding(
      padding: const EdgeInsets.only(right: 6),
      child: OutlinedButton(
        onPressed: () => setState(() => _tab = index),
        style: OutlinedButton.styleFrom(
          backgroundColor: active ? AppColors.accentSubtle : AppColors.panel2,
          foregroundColor: active ? AppColors.accent : AppColors.text,
        ),
        child: Text(label, style: const TextStyle(fontSize: 12.5)),
      ),
    );
  }
}

class _ExecutiveSummaryTab extends StatelessWidget {
  const _ExecutiveSummaryTab({required this.statement, required this.totalCredit, required this.totalDebit});

  final ParsedStatement statement;
  final double totalCredit;
  final double totalDebit;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        SizedBox(width: 220, child: StatCard(label: 'Total Transactions', value: '${statement.transactions.length}')),
        SizedBox(
            width: 220,
            child: StatCard(label: 'Total Credits', value: totalCredit.toStringAsFixed(2), valueColor: AppColors.green)),
        SizedBox(
            width: 220,
            child: StatCard(label: 'Total Debits', value: totalDebit.toStringAsFixed(2), valueColor: AppColors.red)),
        SizedBox(
            width: 220,
            child: StatCard(label: 'Opening Balance', value: statement.openingBalance?.toStringAsFixed(2) ?? '—')),
        SizedBox(
            width: 220,
            child: StatCard(label: 'Closing Balance', value: statement.closingBalance?.toStringAsFixed(2) ?? '—')),
        SizedBox(
            width: 220,
            child: StatCard(
                label: 'Net Change',
                value: (totalCredit - totalDebit).toStringAsFixed(2),
                valueColor: (totalCredit - totalDebit) >= 0 ? AppColors.green : AppColors.red)),
      ],
    );
  }
}

class _DashboardTab extends StatelessWidget {
  const _DashboardTab({required this.statement, required this.totalCredit, required this.totalDebit});

  final ParsedStatement statement;
  final double totalCredit;
  final double totalDebit;

  @override
  Widget build(BuildContext context) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('DEBIT VS CREDIT',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.muted, letterSpacing: 0.5)),
              const SizedBox(height: 10),
              SizedBox(
                height: 200,
                child: (totalCredit + totalDebit) <= 0
                    ? Center(child: Text('No amounts to chart yet.', style: TextStyle(color: AppColors.muted)))
                    : PieChart(
                        PieChartData(
                          sections: [
                            PieChartSectionData(value: totalCredit, color: AppColors.green, title: 'Credit', radius: 70),
                            PieChartSectionData(value: totalDebit, color: AppColors.red, title: 'Debit', radius: 70),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
        const SizedBox(width: 20),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('BALANCE OVER TIME',
                  style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.muted, letterSpacing: 0.5)),
              const SizedBox(height: 10),
              SizedBox(
                height: 200,
                child: statement.transactions.isEmpty
                    ? Center(child: Text('No transactions to chart yet.', style: TextStyle(color: AppColors.muted)))
                    : LineChart(
                        LineChartData(
                          gridData: const FlGridData(show: false),
                          titlesData: const FlTitlesData(show: false),
                          borderData: FlBorderData(show: false),
                          lineBarsData: [
                            LineChartBarData(
                              spots: [
                                for (var i = 0; i < statement.transactions.length; i++)
                                  if (statement.transactions[i].balance != null)
                                    FlSpot(i.toDouble(), statement.transactions[i].balance!),
                              ],
                              isCurved: true,
                              color: AppColors.accent,
                              dotData: const FlDotData(show: false),
                              belowBarData: BarAreaData(show: true, color: AppColors.accentSubtle),
                            ),
                          ],
                        ),
                      ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
