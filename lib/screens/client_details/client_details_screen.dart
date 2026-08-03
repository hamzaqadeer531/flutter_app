import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../state/session_state.dart';
import '../../theme/app_colors.dart';
import '../../widgets/app_alert.dart';
import '../../widgets/app_card.dart';
import '../../widgets/app_main.dart';
import '../../widgets/app_shell.dart';

/// Client Details (HTML feature-parity closure plan, Phase 2) — matches
/// the HTML source's Step 2 fields exactly: Client Name, NTN, Tax Year,
/// Branch, Prepared Date, Large Transaction Threshold. The 7 Tax Year
/// options are copied verbatim from the HTML's <select id="taxYear">.
///
/// Not yet wired into navigation/the wizard -- Phase 3 adds the
/// /client-details route and the 6-step WizardSteps array this screen
/// will sit behind. Building it now (compiled, testable) rather than
/// only once Phase 3 lands keeps each phase independently verifiable,
/// same discipline the backend phases already follow.
const List<String> taxYearOptions = [
  'TY 2026 (Jul 2025 – Jun 2026)',
  'TY 2025 (Jul 2024 – Jun 2025)',
  'TY 2024 (Jul 2023 – Jun 2024)',
  'TY 2023 (Jul 2022 – Jun 2023)',
  'TY 2022 (Jul 2021 – Jun 2022)',
  'TY 2021 (Jul 2020 – Jun 2021)',
  'TY 2020 (Jul 2019 – Jun 2020)',
];

class ClientDetailsScreen extends ConsumerStatefulWidget {
  const ClientDetailsScreen({super.key});

  @override
  ConsumerState<ClientDetailsScreen> createState() => _ClientDetailsScreenState();
}

class _ClientDetailsScreenState extends ConsumerState<ClientDetailsScreen> {
  final _clientNameController = TextEditingController();
  final _ntnController = TextEditingController();
  final _branchController = TextEditingController();
  final _thresholdController = TextEditingController();
  String? _taxYear;
  DateTime? _preparedDate;
  bool _saving = false;
  String? _saveMessage;
  bool _hydrated = false;

  @override
  void dispose() {
    _clientNameController.dispose();
    _ntnController.dispose();
    _branchController.dispose();
    _thresholdController.dispose();
    super.dispose();
  }

  void _hydrateFromState(SessionState session) {
    if (_hydrated) return;
    _hydrated = true;
    _clientNameController.text = session.clientName ?? '';
    _ntnController.text = session.ntn ?? '';
    _branchController.text = session.branch ?? '';
    _thresholdController.text = session.largeTransactionThreshold?.toStringAsFixed(0) ?? '';
    _taxYear = session.taxYear;
    _preparedDate = session.preparedDate != null ? DateTime.tryParse(session.preparedDate!) : null;
  }

  Future<void> _pickPreparedDate() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _preparedDate ?? DateTime.now(),
      firstDate: DateTime(2000),
      lastDate: DateTime(2100),
    );
    if (picked != null) setState(() => _preparedDate = picked);
  }

  Future<void> _save() async {
    setState(() {
      _saving = true;
      _saveMessage = null;
    });
    final threshold = double.tryParse(_thresholdController.text.trim());
    final ok = await ref.read(sessionControllerProvider.notifier).updateClientDetails(
          clientName: _clientNameController.text.trim(),
          ntn: _ntnController.text.trim(),
          taxYear: _taxYear,
          branch: _branchController.text.trim(),
          preparedDate: _preparedDate?.toIso8601String().split('T').first,
          largeTransactionThreshold: threshold,
        );
    setState(() {
      _saving = false;
      _saveMessage = ok ? 'Saved.' : null;
    });
  }

  @override
  Widget build(BuildContext context) {
    final session = ref.watch(sessionControllerProvider);
    _hydrateFromState(session);

    return AppShell(
      body: AppMain(
        child: AppCard(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              const AppCardHeader(
                icon: '🧾',
                title: 'Client Details',
                subtitle: 'Feeds the working paper\'s report headers and the large-transaction flag.',
              ),
              if (session.errorMessage != null) AppAlert(kind: AppAlertKind.error, message: session.errorMessage!),
              if (_saveMessage != null) AppAlert(kind: AppAlertKind.success, message: _saveMessage!),
              _field('Client Name', _clientNameController),
              _field('NTN', _ntnController),
              const SizedBox(height: 8),
              Text('TAX YEAR', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.muted, letterSpacing: 0.4)),
              const SizedBox(height: 6),
              DropdownButtonFormField<String>(
                initialValue: _taxYear,
                decoration: const InputDecoration(isDense: true),
                items: [
                  for (final option in taxYearOptions) DropdownMenuItem(value: option, child: Text(option, style: const TextStyle(fontSize: 13))),
                ],
                onChanged: (value) => setState(() => _taxYear = value),
              ),
              const SizedBox(height: 12),
              _field('Branch', _branchController),
              const SizedBox(height: 8),
              Text('PREPARED DATE', style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.muted, letterSpacing: 0.4)),
              const SizedBox(height: 6),
              InkWell(
                onTap: _pickPreparedDate,
                child: InputDecorator(
                  decoration: const InputDecoration(isDense: true),
                  child: Text(
                    _preparedDate == null ? 'Select a date' : _preparedDate!.toIso8601String().split('T').first,
                    style: TextStyle(fontSize: 13, color: _preparedDate == null ? AppColors.muted : AppColors.text),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              _field('Large Transaction Threshold', _thresholdController, keyboardType: TextInputType.number),
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerRight,
                child: FilledButton(
                  onPressed: _saving || session.sessionId == null ? null : _save,
                  child: Text(_saving ? 'Saving...' : 'Save'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _field(String label, TextEditingController controller, {TextInputType? keyboardType}) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        keyboardType: keyboardType,
        style: const TextStyle(fontSize: 13, color: AppColors.heading),
        decoration: InputDecoration(labelText: label, isDense: true),
      ),
    );
  }
}
