import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'auth_state.dart';

/// One turn of the AI Assistant conversation. role is 'user' or
/// 'assistant' -- matches ChatMessageWire on the backend exactly, so
/// toJson() can be sent as-is in POST /chat/{id}'s messages array.
class ChatMessage {
  const ChatMessage({required this.role, required this.text});

  final String role;
  final String text;

  Map<String, dynamic> toJson() => {'role': role, 'text': text};
}

class ChatState {
  const ChatState({this.messages = const [], this.sending = false, this.error});

  final List<ChatMessage> messages;
  final bool sending;
  final String? error;

  ChatState copyWith({List<ChatMessage>? messages, bool? sending, String? error}) {
    return ChatState(messages: messages ?? this.messages, sending: sending ?? this.sending, error: error);
  }
}

/// Stateless on the server (see services/chat_service.py's docstring) --
/// this controller is the ONLY place the conversation lives; a full page
/// reload loses it, same trade-off as leaving the app was for the prior
/// HTML tool's browser session before it added IndexedDB persistence.
/// Keyed to whichever document is currently loaded -- reset() is called
/// whenever the workflow moves to a different document (see
/// WorkflowController.reset()/uploadAndProcess()).
class ChatController extends StateNotifier<ChatState> {
  ChatController(this._ref) : super(const ChatState());

  final Ref _ref;

  Future<void> send(String documentId, String text) async {
    final userMessage = ChatMessage(role: 'user', text: text);
    final historyIncludingUserTurn = [...state.messages, userMessage];
    state = state.copyWith(messages: historyIncludingUserTurn, sending: true, error: null);

    try {
      final dio = _ref.read(apiClientProvider).dio;
      final response = await dio.post(
        '/chat/$documentId',
        data: {'messages': historyIncludingUserTurn.map((m) => m.toJson()).toList()},
      );
      final reply = response.data['reply'] as String;
      state = state.copyWith(
        messages: [...historyIncludingUserTurn, ChatMessage(role: 'assistant', text: reply)],
        sending: false,
      );
    } catch (error) {
      state = state.copyWith(sending: false, error: error.toString());
    }
  }

  void reset() => state = const ChatState();
}

final chatControllerProvider = StateNotifierProvider<ChatController, ChatState>((ref) => ChatController(ref));
