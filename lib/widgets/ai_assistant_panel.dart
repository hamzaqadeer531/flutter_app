import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../state/chat_state.dart';
import '../theme/app_colors.dart';

/// Conversational Q&A over the currently-loaded statement -- POST
/// /chat/{documentId}/stream (services/chat_service.py::ask_stream,
/// HTML feature-parity closure Phase 11), backed by Gemini on the
/// server. Stateless server-side: this dialog IS the conversation's
/// only home (see ChatController's docstring) -- closing it keeps the
/// history (ChatController isn't torn down), but a full app reload or a
/// new document (see AppShell's ref.listen) loses it.
///
/// The reply streams in token-by-token rather than appearing all at
/// once (ChatController.sendStreaming). No file attachments -- the
/// loaded statement already IS the context, so there's nothing else to
/// attach here.
class AiAssistantPanel extends ConsumerStatefulWidget {
  const AiAssistantPanel({super.key, required this.documentId});

  final String documentId;

  @override
  ConsumerState<AiAssistantPanel> createState() => _AiAssistantPanelState();
}

class _AiAssistantPanelState extends ConsumerState<AiAssistantPanel> {
  final _inputController = TextEditingController();
  final _scrollController = ScrollController();

  @override
  void dispose() {
    _inputController.dispose();
    _scrollController.dispose();
    super.dispose();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!_scrollController.hasClients) return;
      _scrollController.animateTo(
        _scrollController.position.maxScrollExtent,
        duration: const Duration(milliseconds: 200),
        curve: Curves.easeOut,
      );
    });
  }

  Future<void> _send() async {
    final text = _inputController.text.trim();
    if (text.isEmpty) return;
    _inputController.clear();
    _scrollToBottom();
    await ref.read(chatControllerProvider.notifier).sendStreaming(widget.documentId, text);
    _scrollToBottom();
  }

  @override
  Widget build(BuildContext context) {
    final chat = ref.watch(chatControllerProvider);
    ref.listen(chatControllerProvider.select((s) => s.messages), (_, _) => _scrollToBottom());

    return Dialog(
      backgroundColor: AppColors.panel,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(AppColors.radius)),
      child: SizedBox(
        width: 460,
        height: 560,
        child: Column(
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 8, 10),
              child: Row(
                children: [
                  const Text('🤖', style: TextStyle(fontSize: 18)),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text('AI Assistant',
                        style: TextStyle(fontSize: 14, fontWeight: FontWeight.bold, color: AppColors.heading)),
                  ),
                  IconButton(
                    icon: Icon(Icons.close, size: 18, color: AppColors.muted),
                    onPressed: () => Navigator.pop(context),
                  ),
                ],
              ),
            ),
            const Divider(height: 1, color: AppColors.border),
            Expanded(
              child: chat.messages.isEmpty
                  ? Center(
                      child: Padding(
                        padding: const EdgeInsets.all(24),
                        child: Text(
                          'Ask about the balances, transactions, or categories in this statement.',
                          textAlign: TextAlign.center,
                          style: TextStyle(fontSize: 12.5, color: AppColors.muted),
                        ),
                      ),
                    )
                  : ListView.builder(
                      controller: _scrollController,
                      padding: const EdgeInsets.all(14),
                      itemCount: chat.messages.length,
                      itemBuilder: (context, index) => _MessageBubble(message: chat.messages[index]),
                    ),
            ),
            if (chat.error != null)
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                child: Text('Could not reach the AI Assistant: ${chat.error}',
                    style: TextStyle(fontSize: 11.5, color: AppColors.red)),
              ),
            const Divider(height: 1, color: AppColors.border),
            Padding(
              padding: const EdgeInsets.all(10),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      enabled: !chat.sending,
                      decoration: const InputDecoration(hintText: 'Message AI Assistant...', isDense: true),
                      onSubmitted: (_) => _send(),
                    ),
                  ),
                  const SizedBox(width: 8),
                  chat.sending
                      ? const SizedBox(
                          width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2))
                      : IconButton(
                          icon: const Icon(Icons.send, color: AppColors.accent),
                          onPressed: _send,
                        ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _MessageBubble extends StatelessWidget {
  const _MessageBubble({required this.message});

  final ChatMessage message;

  @override
  Widget build(BuildContext context) {
    final isUser = message.role == 'user';
    return Align(
      alignment: isUser ? Alignment.centerRight : Alignment.centerLeft,
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        constraints: const BoxConstraints(maxWidth: 340),
        decoration: BoxDecoration(
          color: isUser ? AppColors.accent : AppColors.panel2,
          borderRadius: BorderRadius.circular(10),
        ),
        child: Text(
          message.text,
          style: TextStyle(fontSize: 12.5, color: isUser ? AppColors.accentOn : AppColors.text),
        ),
      ),
    );
  }
}
