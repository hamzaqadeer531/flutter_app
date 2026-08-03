import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:go_router/go_router.dart';

import '../state/auth_state.dart';
import '../state/chat_state.dart';
import '../state/workflow_state.dart';
import '../theme/app_colors.dart';
import 'ai_assistant_panel.dart';

/// The top navigation bar every authenticated screen sits under —
/// pixel-matched to the HTML source's `.nav` bar (56px navy bar, bank
/// icon, title + subtitle, right-aligned badge/actions). The HTML nav
/// bar's "No bank selected" badge and Templates/AI Learning/Settings
/// buttons are specific to the single-statement wizard workflow (later
/// screens); this shell exposes an optional `trailing` slot for
/// screen-specific actions instead of hardcoding them here.
class AppShell extends ConsumerWidget {
  const AppShell({super.key, required this.body, this.trailing});

  final Widget body;
  final Widget? trailing;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final user = ref.watch(authControllerProvider).user;
    final documentId = ref.watch(workflowControllerProvider.select((s) => s.documentId));

    // A new document means any prior conversation was about a DIFFERENT
    // statement -- resending that history as context for the new one
    // would confuse the assistant, so drop it rather than carry it over
    // silently.
    ref.listen<String?>(workflowControllerProvider.select((s) => s.documentId), (previous, next) {
      if (previous != null && previous != next) {
        ref.read(chatControllerProvider.notifier).reset();
      }
    });

    return Scaffold(
      backgroundColor: AppColors.bodyBackground,
      floatingActionButton: documentId == null
          ? null
          : FloatingActionButton(
              tooltip: 'AI Assistant -- ask questions about this statement',
              backgroundColor: AppColors.accent,
              foregroundColor: AppColors.accentOn,
              onPressed: () => showDialog(
                context: context,
                builder: (context) => AiAssistantPanel(documentId: documentId),
              ),
              child: const Text('🤖', style: TextStyle(fontSize: 22)),
            ),
      body: Column(
        children: [
          Container(
            height: 56,
            padding: const EdgeInsets.symmetric(horizontal: 28),
            decoration: const BoxDecoration(
              color: AppColors.navy,
              border: Border(bottom: BorderSide(color: AppColors.border, width: 1)),
              boxShadow: [BoxShadow(color: Color(0x73000000), blurRadius: 8, offset: Offset(0, 2))],
            ),
            child: Row(
              children: [
                Container(
                  width: 38,
                  height: 38,
                  alignment: Alignment.center,
                  decoration: BoxDecoration(color: AppColors.accent, borderRadius: BorderRadius.circular(7)),
                  child: const Text('🏦', style: TextStyle(fontSize: 20)),
                ),
                const SizedBox(width: 14),
                const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      'Bank Working Generator',
                      style: TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'BakerTilly Mehmood Idrees Qamar, Chartered Accountants',
                      style: TextStyle(color: Color(0x8CFFFFFF), fontSize: 11),
                    ),
                  ],
                ),
                const Spacer(),
                if (trailing != null) ...[trailing!, const SizedBox(width: 14)],
                const _ScreenNavMenu(),
                const SizedBox(width: 10),
                _UserMenu(email: user?.userId, role: user?.role),
              ],
            ),
          ),
          Expanded(child: body),
        ],
      ),
    );
  }
}

/// Global "go anywhere" menu so every screen is reachable from every
/// other screen — the HTML source didn't need this (a single-page
/// wizard), but this app is multi-route, so a persistent nav affordance
/// replaces the HTML's Templates/AI Learning/Settings nav buttons plus
/// adds the net-new screens (Dataset Manager, Administration).
class _ScreenNavMenu extends StatelessWidget {
  const _ScreenNavMenu();

  static const _destinations = [
    ('/dashboard', '📊 Dashboard'),
    ('/upload', '📄 Upload Statement'),
    ('/client-details', '🧾 Client Details'),
    ('/review', '🔍 Review Transactions'),
    ('/verify', '✅ Verify & Check'),
    ('/summary', '📈 Analytics & Export'),
    ('/reports', '📤 Reports'),
    ('/templates', '🧩 Templates'),
    ('/dataset-manager', '🗂️ Dataset Manager'),
    ('/admin', '🛡️ Administration'),
    ('/ai-dashboard', '🤖 AI Usage & Cost'),
    ('/settings', '⚙️ Settings'),
  ];

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<String>(
      tooltip: 'Navigate',
      offset: const Offset(0, 44),
      color: AppColors.panel2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
      itemBuilder: (context) => [
        for (final destination in _destinations)
          PopupMenuItem<String>(value: destination.$1, child: Text(destination.$2)),
      ],
      onSelected: (path) => context.go(path),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: const Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.apps, size: 15, color: Colors.white),
            SizedBox(width: 6),
            Text('Menu', style: TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600)),
            Icon(Icons.arrow_drop_down, size: 18, color: Colors.white),
          ],
        ),
      ),
    );
  }
}

class _UserMenu extends ConsumerWidget {
  const _UserMenu({this.email, this.role});

  final String? email;
  final String? role;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return PopupMenuButton<String>(
      tooltip: 'Account',
      offset: const Offset(0, 44),
      color: AppColors.panel2,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(8),
        side: const BorderSide(color: AppColors.border),
      ),
      itemBuilder: (context) => [
        PopupMenuItem<String>(
          enabled: false,
          child: Text(
            role ?? '',
            style: TextStyle(fontSize: 11, fontWeight: FontWeight.bold, color: AppColors.muted, letterSpacing: 0.4),
          ),
        ),
        const PopupMenuDivider(),
        const PopupMenuItem<String>(value: 'signout', child: Text('Sign out')),
      ],
      onSelected: (value) {
        if (value == 'signout') ref.read(authControllerProvider.notifier).logout();
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
        decoration: BoxDecoration(
          color: Colors.white.withValues(alpha: 0.08),
          borderRadius: BorderRadius.circular(20),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Icon(Icons.person_outline, size: 15, color: Colors.white),
            const SizedBox(width: 6),
            Text(
              (role ?? 'account').toUpperCase(),
              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.w600),
            ),
            const SizedBox(width: 2),
            const Icon(Icons.arrow_drop_down, size: 18, color: Colors.white),
          ],
        ),
      ),
    );
  }
}
