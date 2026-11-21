import 'dart:convert';
import 'package:http/http.dart' as http;
import '../config/api_config.dart';

/// One earlier message in the conversation, sent so the coach can follow it.
class ChatTurn {
  final bool isUser;
  final String text;
  const ChatTurn(this.isUser, this.text);

  Map<String, dynamic> toJson() => {'role': isUser ? 'user' : 'assistant', 'content': text};
}

class AiService {
  // Some models think before answering, so allow a little longer than a normal request
  static const Duration _timeout = Duration(seconds: 60);

  /// Asks the coach. [history] is the conversation so far (oldest first), so
  /// replies follow on from what was said instead of starting from scratch.
  static Future<({String text, bool ok})> ask(String question,
      {String? date, List<ChatTurn> history = const []}) async {
    try {
      // The last 6 back-and-forths are plenty of context
      final recent = history.length > 12 ? history.sublist(history.length - 12) : history;
      final res = await http
          .post(
            Uri.parse('${ApiConfig.baseUrl}/ai/chat'),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode({
              'question': question,
              if (date != null) 'date': date,
              'history': recent.map((t) => t.toJson()).toList(),
            }),
          )
          .timeout(_timeout);

      if (res.statusCode == 200) {
        final data = jsonDecode(res.body);
        return (text: (data['answer'] ?? 'No response received.') as String, ok: true);
      }
      String detail = '';
      try {
        detail = jsonDecode(res.body)['detail']?.toString() ?? '';
      } catch (_) {}
      return (
        text: 'Sorry, the coach couldn\'t answer (server returned ${res.statusCode}). $detail'.trim(),
        ok: false,
      );
    } catch (e) {
      return (
        text: 'Could not reach the server. Make sure you\'re connected to your home network.',
        ok: false,
      );
    }
  }

  /// Tells the server to forget the conversation (when the chat is cleared).
  static Future<void> reset() async {
    try {
      await http
          .delete(Uri.parse('${ApiConfig.baseUrl}/ai/chat'))
          .timeout(const Duration(seconds: 10));
    } catch (_) {
      // Not reachable: the server forgets on its own after a few quiet hours
    }
  }
}
