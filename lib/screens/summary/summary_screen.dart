import 'package:fl_chart/fl_chart.dart';
import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../../models/insight_model.dart';
import '../../models/internal_transfer_model.dart';
import '../../models/monthly_summary_model.dart';
import '../../models/pipeline_models.dart';
import '../../models/recurring_transaction_model.dart';
import '../../models/verification_models.dart';
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

  // Dashboard follow-up charts (session-scoped) -- reuses whatever of
  // _transfers/_recurring above is already loaded rather than
  // re-fetching, and adds two more session-wide sources: per-account
  // verification (bank-wise volume + credit/debit category summaries)
  // and the monthly credit/debit aggregation.
  SessionVerification? _dashboardVerification;
  List<MonthlySummary>? _monthlySummary;
  bool _loadingDashboardExtras = false;
  String? _dashboardExtrasError;

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

  Future<void> _loadDashboardExtras() async {
    final sessionId = ref.read(sessionControllerProvider).sessionId;
    if (sessionId == null) {
      setState(() => _dashboardExtrasError = 'No working session yet -- upload a statement first.');
      return;
    }
    setState(() {
      _loadingDashboardExtras = true;
      _dashboardExtrasError = null;
    });
    try {
      final dio = ref.read(apiClientProvider).dio;
      final results = await Future.wait([
        dio.get('/sessions/$sessionId/verification'),
        dio.get('/sessions/$sessionId/monthly-summary'),
      ]);
      final verification = SessionVerification.fromJson(results[0].data as Map<String, dynamic>);
      final monthly = (results[1].data as List<dynamic>)
          .map((e) => MonthlySummary.fromJson(e as Map<String, dynamic>))
          .toList();
      setState(() {
        _dashboardVerification = verification;
        _monthlySummary = monthly;
        _loadingDashboardExtras = false;
      });
      // Recurring/Internal Transfer Trend reuse the same lists the
      // Recurring Transactions / Internal Transfers tabs use -- load
      // them too if this is the first tab the reviewer has opened.
      if (_recurring == null && !_loadingRecurring) _loadRecurring();
      if (_transfers == null && !_loadingTransfers) _loadTransfers();
    } catch (error) {
      setState(() {
        _loadingDashboardExtras = false;
        _dashboardExtrasError = 'Could not load dashboard data: $error';
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
                      _DashboardTab(
                        statement: statement,
                        totalCredit: totalCredit,
                        totalDebit: totalDebit,
                        verification: _dashboardVerification,
                        monthlySummary: _monthlySummary,
                        recurring: _recurring,
                        transfers: _transfers,
                        loadingExtras: _loadingDashboardExtras,
                        extrasError: _dashboardExtrasError,
                      )
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
          if (index == 1 && _dashboardVerification == null && !_loadingDashboardExtras) {
            _loadDashboardExtras();
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
  const _DashboardTab({
    required this.statement,
    required this.totalCredit,
    required this.totalDebit,
    required this.verification,
    required this.monthlySummary,
    required this.recurring,
    required this.transfers,
    required this.loadingExtras,
    required this.extrasError,
  });

  final ParsedStatement statement;
  final double totalCredit;
  final double totalDebit;

  // Session-scoped follow-up charts -- null while not yet loaded.
  final SessionVerification? verification;
  final List<MonthlySummary>? monthlySummary;
  final List<RecurringTransaction>? recurring;
  final List<InternalTransfer>? transfers;
  final bool loadingExtras;
  final String? extrasError;

  @override
  Widget build(BuildContext context) {
    return Wrap(
      spacing: 20,
      runSpacing: 20,
      children: [
        _chartBox('DEBIT VS CREDIT', (totalCredit + totalDebit) <= 0
            ? _emptyChart('No amounts to chart yet.')
            : PieChart(
                PieChartData(
                  sections: [
                    PieChartSectionData(value: totalCredit, color: AppColors.green, title: 'Credit', radius: 70),
                    PieChartSectionData(value: totalDebit, color: AppColors.red, title: 'Debit', radius: 70),
                  ],
                ),
              )),
        _chartBox('BALANCE OVER TIME', statement.transactions.isEmpty
            ? _emptyChart('No transactions to chart yet.')
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
              )),
        _chartBox('MONTHLY CASH FLOW', _sessionChartBody(child: _monthlyCashFlowChart())),
        _chartBox('BANK-WISE TRANSACTION DISTRIBUTION', _sessionChartBody(child: _bankDistributionChart())),
        _chartBox('CATEGORY-WISE SPENDING', _sessionChartBody(child: _categorySpendingChart())),
        _chartBox('RECURRING TRANSACTION TREND', _recurringTrendChart()),
        _chartBox('INTERNAL TRANSFER TREND', _internalTransferTrendChart()),
      ],
    );
  }

  Widget _chartBox(String title, Widget child) {
    return SizedBox(
      width: 340,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.muted, letterSpacing: 0.5)),
          const SizedBox(height: 10),
          SizedBox(height: 200, child: child),
        ],
      ),
    );
  }

  Widget _emptyChart(String message) => Center(child: Text(message, style: TextStyle(color: AppColors.muted)));

  /// Wraps a chart that depends on session-scoped data (verification/
  /// monthly-summary) with the shared loading/error/not-yet-loaded
  /// states, so each of the 3 session-scoped charts doesn't repeat
  /// this branching.
  Widget _sessionChartBody({required Widget child}) {
    if (loadingExtras) {
      return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    }
    if (extrasError != null) {
      return Center(child: Text(extrasError!, style: TextStyle(fontSize: 11.5, color: AppColors.red)));
    }
    if (verification == null) {
      return _emptyChart('No data yet.');
    }
    return child;
  }

  Widget _monthlyCashFlowChart() {
    final months = monthlySummary ?? const [];
    if (months.isEmpty) return _emptyChart('No dated transactions to chart yet.');
    final maxValue = months.fold<double>(
      0, (m, r) => [m, r.totalCredits, r.totalDebits].reduce((a, b) => a > b ? a : b));
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        maxY: maxValue <= 0 ? 1 : maxValue * 1.15,
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= months.length) return const SizedBox.shrink();
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(months[i].month.substring(5), style: TextStyle(fontSize: 9, color: AppColors.muted)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < months.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(toY: months[i].totalCredits, color: AppColors.green, width: 7),
              BarChartRodData(toY: months[i].totalDebits, color: AppColors.red, width: 7),
            ]),
        ],
      ),
    );
  }

  Widget _bankDistributionChart() {
    final accounts = verification?.accounts ?? const [];
    if (accounts.isEmpty) return _emptyChart('Needs at least one processed account.');
    final palette = [AppColors.accent, AppColors.green, AppColors.orange, AppColors.red, AppColors.muted];
    return PieChart(
      PieChartData(
        sections: [
          for (var i = 0; i < accounts.length; i++)
            PieChartSectionData(
              value: (accounts[i].bankSummary.creditCount + accounts[i].bankSummary.debitCount).toDouble(),
              color: palette[i % palette.length],
              title: accounts[i].bankSummary.bankName ?? accounts[i].filename,
              radius: 70,
              titleStyle: const TextStyle(fontSize: 9, fontWeight: FontWeight.bold, color: Colors.white),
            ),
        ],
      ),
    );
  }

  Widget _categorySpendingChart() {
    final accounts = verification?.accounts ?? const [];
    if (accounts.isEmpty) return _emptyChart('Needs at least one processed account.');
    final byCategory = <String, double>{};
    for (final account in accounts) {
      for (final group in account.debitSummary) {
        final key = group.category ?? 'Uncategorized';
        byCategory[key] = (byCategory[key] ?? 0) + group.total;
      }
    }
    if (byCategory.isEmpty) return _emptyChart('No debit categories to chart yet.');
    final top = byCategory.entries.toList()..sort((a, b) => b.value.compareTo(a.value));
    final shown = top.take(6).toList();
    final maxValue = shown.first.value;
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        maxY: maxValue <= 0 ? 1 : maxValue * 1.15,
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 40,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= shown.length) return const SizedBox.shrink();
                final label = shown[i].key.length > 8 ? '${shown[i].key.substring(0, 8)}…' : shown[i].key;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Transform.rotate(
                    angle: -0.5,
                    child: Text(label, style: TextStyle(fontSize: 9, color: AppColors.muted)),
                  ),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < shown.length; i++)
            BarChartGroupData(x: i, barRods: [BarChartRodData(toY: shown[i].value, color: AppColors.orange, width: 14)]),
        ],
      ),
    );
  }

  Widget _recurringTrendChart() {
    if (loadingRecurring) return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    final items = recurring ?? const [];
    if (items.isEmpty) return _emptyChart('No recurring transactions detected yet.');
    final top = (List<RecurringTransaction>.from(items)..sort((a, b) => b.total.compareTo(a.total))).take(6).toList();
    final maxValue = top.first.total;
    return BarChart(
      BarChartData(
        gridData: const FlGridData(show: false),
        borderData: FlBorderData(show: false),
        maxY: maxValue <= 0 ? 1 : maxValue * 1.15,
        titlesData: FlTitlesData(
          leftTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              reservedSize: 26,
              getTitlesWidget: (value, meta) {
                final i = value.toInt();
                if (i < 0 || i >= top.length) return const SizedBox.shrink();
                final label = top[i].description.length > 6 ? '${top[i].description.substring(0, 6)}…' : top[i].description;
                return Padding(
                  padding: const EdgeInsets.only(top: 4),
                  child: Text(label, style: TextStyle(fontSize: 9, color: AppColors.muted)),
                );
              },
            ),
          ),
        ),
        barGroups: [
          for (var i = 0; i < top.length; i++)
            BarChartGroupData(x: i, barRods: [
              BarChartRodData(toY: top[i].total, color: AppColors.accent, width: 14),
            ]),
        ],
      ),
    );
  }

  Widget _internalTransferTrendChart() {
    if (loadingTransfers) return const Center(child: CircularProgressIndicator(color: AppColors.accent));
    final items = transfers ?? const [];
    if (items.isEmpty) return _emptyChart('No internal transfers detected yet.');
    final sorted = List<InternalTransfer>.from(items)
      ..sort((a, b) => (a.dateIso ?? '').compareTo(b.dateIso ?? ''));
    return LineChart(
      LineChartData(
        gridData: const FlGridData(show: false),
        titlesData: const FlTitlesData(show: false),
        borderData: FlBorderData(show: false),
        lineBarsData: [
          LineChartBarData(
            spots: [for (var i = 0; i < sorted.length; i++) FlSpot(i.toDouble(), sorted[i].amount)],
            isCurved: false,
            color: AppColors.orange,
            barWidth: 2,
            dotData: const FlDotData(show: true),
            belowBarData: BarAreaData(show: true, color: AppColors.orangeSubtle),
          ),
        ],
      ),
    );
  }

  // These two mirror the loading state of the sibling tabs' own
  // fetches (Recurring Transactions / Internal Transfers) -- the
  // Dashboard tab triggers those loads too (see _loadDashboardExtras),
  // so its own trend charts show a spinner instead of a premature
  // "none detected" while that fetch is still in flight.
  bool get loadingRecurring => recurring == null && loadingExtras;
  bool get loadingTransfers => transfers == null && loadingExtras;
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
