import 'dart:convert';

import 'package:dio/dio.dart';
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

  /// Streaming counterpart to send() above (HTML feature-parity closure
  /// Phase 11) -- POST /chat/{id}/stream, an SSE response of {"text":
  /// "..."} chunks (or a terminal {"error": "..."} event -- see that
  /// route's own docstring for why an error can't become an HTTP
  /// status once streaming has started). The assistant's message
  /// grows in place as chunks arrive, so the UI updates live instead
  /// of waiting for the full reply.
  Future<void> sendStreaming(String documentId, String text) async {
    final userMessage = ChatMessage(role: 'user', text: text);
    final historyIncludingUserTurn = [...state.messages, userMessage];
    state = state.copyWith(messages: historyIncludingUserTurn, sending: true, error: null);

    try {
      final dio = _ref.read(apiClientProvider).dio;
      final response = await dio.post<ResponseBody>(
        '/chat/$documentId/stream',
        data: {'messages': historyIncludingUserTurn.map((m) => m.toJson()).toList()},
        options: Options(responseType: ResponseType.stream),
      );

      final buffer = StringBuffer();
      var assistantText = '';
      String? streamError;

      await for (final chunkBytes in response.data!.stream) {
        buffer.write(utf8.decode(chunkBytes, allowMalformed: true));
        var content = buffer.toString();
        var splitIndex = content.indexOf('\n\n');
        while (splitIndex != -1) {
          final rawEvent = content.substring(0, splitIndex).trim();
          content = content.substring(splitIndex + 2);
          if (rawEvent.startsWith('data: ')) {
            final data = jsonDecode(rawEvent.substring(6)) as Map<String, dynamic>;
            if (data.containsKey('text')) {
              assistantText += data['text'] as String;
              state = state.copyWith(
                messages: [...historyIncludingUserTurn, ChatMessage(role: 'assistant', text: assistantText)],
              );
            } else if (data.containsKey('error')) {
              streamError = data['error'] as String;
            }
          }
          splitIndex = content.indexOf('\n\n');
        }
        buffer
          ..clear()
          ..write(content);
      }

      state = state.copyWith(sending: false, error: streamError);
    } catch (error) {
      state = state.copyWith(sending: false, error: error.toString());
    }
  }

  void reset() => state = const ChatState();
}

final chatControllerProvider = StateNotifierProvider<ChatController, ChatState>((ref) => ChatController(ref));
