import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/insight_model.dart';
import '../../models/internal_transfer_model.dart';
import '../../models/pipeline_models.dart';
import '../../models/recurring_transaction_model.dart';
import '../../state/auth_state.dart';
import '../../state/session_state.dart';
import '../../state/workflow_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_alert.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_main.dart';
import '../../widgets/app_shell.dart';
import '../../widgets/stat_card.dart';
import '../../widgets/wizard_steps.dart';

/// Pixel-accurate migration of the HTML source's Step 5 ("Analytics &
/// Insights") — the Executive Summary, Dashboard (chart), Internal
/// Transfers, and Recurring Transactions sub-tabs are implemented with
/// real data; the HTML's remaining sub-tabs (Smart Insights, Filters)
/// are the same underlying transaction data viewed differently and are
/// reasonable follow-up additions rather than blocking this pass.
class SummaryScreen extends ConsumerStatefulWidget {
  const SummaryScreen({super.key});

  @override
  ConsumerState<SummaryScreen> createState() => _SummaryScreenState();
}

class _SummaryScreenState extends ConsumerState<SummaryScreen> {
  int _tab = 0;

  List<InternalTransfer>? _transfers;
  bool _loadingTransfers = false;
  String? _transfersError;

  List<RecurringTransaction>? _recurring;
  bool _loadingRecurring = false;
  String? _recurringError;

  List<Insight>? _insights;
  bool _loadingInsights = false;
  String? _insightsError;

  Future<void> _loadTransfers() async {
    final sessionId = ref.read(sessionControllerProvider).sessionId;
    if (sessionId == null) {
      setState(() => _transfersError = 'No working session yet -- upload a statement first.');
      return;
    }
    setState(() {
      _loadingTransfers = true;
      _transfersError = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get('/sessions/$sessionId/internal-transfers');
      final data = response.data as List<dynamic>;
      setState(() {
        _transfers = data.map((e) => InternalTransfer.fromJson(e as Map<String, dynamic>)).toList();
        _loadingTransfers = false;
      });
    } catch (error) {
      setState(() {
        _loadingTransfers = false;
        _transfersError = 'Could not load internal transfers: $error';
      });
    }
  }

  Future<void> _loadRecurring() async {
    final sessionId = ref.read(sessionControllerProvider).sessionId;
    if (sessionId == null) {
      setState(() => _recurringError = 'No working session yet -- upload a statement first.');
      return;
    }
    setState(() {
      _loadingRecurring = true;
      _recurringError = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get('/sessions/$sessionId/recurring-transactions');
      final data = response.data as List<dynamic>;
      setState(() {
        _recurring = data.map((e) => RecurringTransaction.fromJson(e as Map<String, dynamic>)).toList();
        _loadingRecurring = false;
      });
    } catch (error) {
      setState(() {
        _loadingRecurring = false;
        _recurringError = 'Could not load recurring transactions: $error';
      });
    }
  }

  Future<void> _loadInsights() async {
    final sessionId = ref.read(sessionControllerProvider).sessionId;
    if (sessionId == null) {
      setState(() => _insightsError = 'No working session yet -- upload a statement first.');
      return;
    }
    setState(() {
      _loadingInsights = true;
      _insightsError = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final response = await dio.get('/sessions/$sessionId/insights');
      final data = response.data as List<dynamic>;
      setState(() {
        _insights = data.map((e) => Insight.fromJson(e as Map<String, dynamic>)).toList();
        _loadingInsights = false;
      });
    } catch (error) {
      setState(() {
        _loadingInsights = false;
        _insightsError = 'Could not load insights: $error';
      });
    }
  }

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
            currentIndex: 4,
            labels: wizardStepLabels,
            onStepTap: (i) {
              if (i == 0) context.go('/upload');
              if (i == 1) context.go('/client-details');
              if (i == 2) context.go('/review');
              if (i == 3) context.go('/verify');
              if (i == 5) context.go('/reports');
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
                        _tabButton('🔁 Internal Transfers', 2),
                        _tabButton('🔂 Recurring Transactions', 3),
                        _tabButton('💡 Smart Insights', 4),
                      ],
                    ),
                    const Divider(color: AppColors.border, height: 24),
                    if (_tab == 0)
                      _ExecutiveSummaryTab(statement: statement, totalCredit: totalCredit, totalDebit: totalDebit)
                    else if (_tab == 1)
                      _DashboardTab(statement: statement, totalCredit: totalCredit, totalDebit: totalDebit)
                    else if (_tab == 2)
                      _loadingTransfers
                          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppColors.accent)))
                          : _transfersError != null
                              ? AppAlert(kind: AppAlertKind.error, message: _transfersError!)
                              : _InternalTransfersTab(transfers: _transfers ?? const [])
                    else if (_tab == 3)
                      _loadingRecurring
                          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppColors.accent)))
                          : _recurringError != null
                              ? AppAlert(kind: AppAlertKind.error, message: _recurringError!)
                              : _RecurringTransactionsTab(recurring: _recurring ?? const [])
                    else
                      _loadingInsights
                          ? const Center(child: Padding(padding: EdgeInsets.all(24), child: CircularProgressIndicator(color: AppColors.accent)))
                          : _insightsError != null
                              ? AppAlert(kind: AppAlertKind.error, message: _insightsError!)
                              : _SmartInsightsTab(insights: _insights ?? const []),
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
        onPressed: () {
          setState(() => _tab = index);
          if (index == 2 && _transfers == null && !_loadingTransfers) {
            _loadTransfers();
          }
          if (index == 3 && _recurring == null && !_loadingRecurring) {
            _loadRecurring();
          }
          if (index == 4 && _insights == null && !_loadingInsights) {
            _loadInsights();
          }
        },
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

class _InternalTransfersTab extends StatelessWidget {
  const _InternalTransfersTab({required this.transfers});

  final List<InternalTransfer> transfers;

  @override
  Widget build(BuildContext context) {
    if (transfers.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'No likely internal transfers detected. This needs at least two statements in the same working session.',
          style: TextStyle(fontSize: 13, color: AppColors.muted),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(AppColors.panel2),
        columns: const [
          DataColumn(label: Text('Date')),
          DataColumn(label: Text('Source Account')),
          DataColumn(label: Text('Destination Account')),
          DataColumn(label: Text('Amount')),
          DataColumn(label: Text('Reference')),
          DataColumn(label: Text('Confidence')),
        ],
        rows: [
          for (final t in transfers)
            DataRow(cells: [
              DataCell(Text(t.dateIso ?? '—', style: TextStyle(fontSize: 12.5, color: AppColors.text))),
              DataCell(Text(t.sourceAccount, style: TextStyle(fontSize: 12.5, color: AppColors.text))),
              DataCell(Text(t.destinationAccount, style: TextStyle(fontSize: 12.5, color: AppColors.text))),
              DataCell(Text(t.amount.toStringAsFixed(2), style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.heading))),
              DataCell(Text(t.referenceNumber ?? '—', style: TextStyle(fontSize: 12.5, color: AppColors.muted))),
              DataCell(_confidenceBadge(t.confidence)),
            ]),
        ],
      ),
    );
  }

  Widget _confidenceBadge(String confidence) {
    final color = switch (confidence) {
      'high' => AppColors.green,
      'medium' => AppColors.orange,
      _ => AppColors.muted,
    };
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: color.withValues(alpha: 0.15), borderRadius: BorderRadius.circular(10)),
      child: Text(confidence.toUpperCase(), style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: color)),
    );
  }
}

class _RecurringTransactionsTab extends StatelessWidget {
  const _RecurringTransactionsTab({required this.recurring});

  final List<RecurringTransaction> recurring;

  @override
  Widget build(BuildContext context) {
    if (recurring.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text(
          'No recurring or repetitive transactions detected yet.',
          style: TextStyle(fontSize: 13, color: AppColors.muted),
        ),
      );
    }
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      child: DataTable(
        headingRowColor: WidgetStateProperty.all(AppColors.panel2),
        columns: const [
          DataColumn(label: Text('Description')),
          DataColumn(label: Text('Type')),
          DataColumn(label: Text('Occurrences')),
          DataColumn(label: Text('Frequency')),
          DataColumn(label: Text('First')),
          DataColumn(label: Text('Last')),
          DataColumn(label: Text('Total')),
        ],
        rows: [
          for (final r in recurring)
            DataRow(cells: [
              DataCell(Text(r.description, style: TextStyle(fontSize: 12.5, color: AppColors.text))),
              DataCell(Text(r.type == 'credit' ? 'Credit' : 'Debit',
                  style: TextStyle(fontSize: 12.5, color: r.type == 'credit' ? AppColors.green : AppColors.red))),
              DataCell(Text('${r.count}×', style: TextStyle(fontSize: 12.5, color: AppColors.text))),
              DataCell(_frequencyBadge(r.frequency)),
              DataCell(Text(r.firstDateIso ?? '—', style: TextStyle(fontSize: 12.5, color: AppColors.muted))),
              DataCell(Text(r.lastDateIso ?? '—', style: TextStyle(fontSize: 12.5, color: AppColors.muted))),
              DataCell(Text(r.total.toStringAsFixed(2),
                  style: const TextStyle(fontSize: 12.5, fontWeight: FontWeight.w600, color: AppColors.heading))),
            ]),
        ],
      ),
    );
  }

  Widget _frequencyBadge(String frequency) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(color: AppColors.accentSubtle, borderRadius: BorderRadius.circular(10)),
      child: Text(frequency, style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: AppColors.accent)),
    );
  }
}

class _SmartInsightsTab extends StatelessWidget {
  const _SmartInsightsTab({required this.insights});

  final List<Insight> insights;

  @override
  Widget build(BuildContext context) {
    if (insights.isEmpty) {
      return Padding(
        padding: const EdgeInsets.symmetric(vertical: 24),
        child: Text('No notable patterns detected yet.', style: TextStyle(fontSize: 13, color: AppColors.muted)),
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [for (final insight in insights) _InsightRow(insight: insight)],
    );
  }
}

class _InsightRow extends StatelessWidget {
  const _InsightRow({required this.insight});

  final Insight insight;

  @override
  Widget build(BuildContext context) {
    final (background, border) = switch (insight.type) {
      'alert' => (AppColors.redSubtle, AppColors.red),
      'warn' => (AppColors.orangeSubtle, AppColors.orange),
      _ => (AppColors.panel2, AppColors.border),
    };
    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: background,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: border, width: 1),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(insight.icon, style: const TextStyle(fontSize: 16)),
          const SizedBox(width: 10),
          Expanded(child: Text(insight.text, style: TextStyle(fontSize: 13, color: AppColors.text, height: 1.4))),
        ],
      ),
    );
  }
}
