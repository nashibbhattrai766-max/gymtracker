import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:gymtracker/config/api_config.dart';
import 'package:gymtracker/screens/ai_chat_screen.dart';

/// The coach gets the conversation so far with each question (so it can follow
/// it), without the greeting or error notes, and clearing the chat resets it.
void main() {
  setUpAll(() async {
    SharedPreferences.setMockInitialValues({'base_url': 'http://server'});
    await ApiConfig.load();
  });

  testWidgets('sends history, skips notes, and resets on clear', (tester) async {
    final sent = <Map<String, dynamic>>[];
    var deletes = 0;
    var replies = ['You went twice this month, that counts.', 'One small step: gym bag by the door.'];

    final mock = MockClient((req) async {
      if (req.method == 'DELETE') {
        deletes++;
        return http.Response('{"status":"cleared"}', 200);
      }
      sent.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response(jsonEncode({'answer': replies.removeAt(0)}), 200,
          headers: {'content-type': 'application/json; charset=utf-8'});
    });

    await http.runWithClient(() async {
      await tester.pumpWidget(const MaterialApp(home: AiChatScreen()));

      Future<void> say(String text) async {
        await tester.enterText(find.byType(TextField), text);
        await tester.testTextInput.receiveAction(TextInputAction.send);
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
        await tester.pumpAndSettle();
      }

      await say("you're not understanding me");
      expect(sent.last['question'], "you're not understanding me");
      expect(sent.last['history'], isEmpty, reason: 'the greeting is not conversation');

      await say('ok what should I do');
      final history = (sent.last['history'] as List).cast<Map>();
      expect(history.map((m) => m['role']), ['user', 'assistant']);
      expect(history.first['content'], "you're not understanding me");
      expect(history.last['content'], 'You went twice this month, that counts.');

      await tester.tap(find.byTooltip('Clear chat'));
      await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 50)));
      await tester.pumpAndSettle();
      expect(deletes, 1, reason: 'clearing the chat resets the server memory');
      expect(find.text('One small step: gym bag by the door.'), findsNothing);
    }, () => mock);
  });
}
