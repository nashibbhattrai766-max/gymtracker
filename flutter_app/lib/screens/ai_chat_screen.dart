import 'package:flutter/material.dart';
import 'package:flutter_animate/flutter_animate.dart';
import 'package:intl/intl.dart';
import '../config/profile.dart';
import '../services/ai_service.dart';

class AiChatScreen extends StatefulWidget {
  const AiChatScreen({super.key});
  @override
  State<AiChatScreen> createState() => _AiChatScreenState();
}

class _Message {
  final String text;
  final bool isUser;
  final bool isNote; // greeting, "chat cleared" or an error: not part of the conversation
  final DateTime time;
  _Message({required this.text, required this.isUser, this.isNote = false})
      : time = DateTime.now();
}

class _AiChatScreenState extends State<AiChatScreen> {
  final _controller    = TextEditingController();
  final _scrollCtrl    = ScrollController();
  final List<_Message> _messages = [];
  bool _thinking = false;

  // Suggested quick questions
  static const _suggestions = [
    'How did I do this week? 📊',
    'What\'s my current streak? 🔥',
    'How has my weight changed? ⚖️',
    'How many calories on average? 🍽️',
    'Am I improving this month? 📈',
    'What should I focus on? 🎯',
    'How\'s my gym attendance? 💪',
    'What was my best week? 🏆',
  ];

  @override
  void initState() {
    super.initState();
    // Welcome message
    _messages.add(_Message(
      text: "${Profile.greeting} 👋 I'm your GymTracker coach. Ask me about your progress, or just tell me how things are going. Building habits takes time, and I'm here for the whole journey.",
      isUser: false,
      isNote: true,
    ));
  }

  @override
  void dispose() {
    _controller.dispose();
    _scrollCtrl.dispose();
    super.dispose();
  }

  Future<void> _send(String question) async {
    if (question.trim().isEmpty || _thinking) return;

    final q = question.trim();
    _controller.clear();

    setState(() {
      _messages.add(_Message(text: q, isUser: true));
      _thinking = true;
    });
    _scrollToBottom();

    final today = DateFormat('yyyy-MM-dd').format(DateTime.now());
    // Everything said so far (not the question just added), so the coach follows the conversation
    final history = [
      for (final m in _messages.sublist(0, _messages.length - 1))
        if (!m.isNote) ChatTurn(m.isUser, m.text),
    ];
    final reply = await AiService.ask(q, date: today, history: history);

    if (!mounted) return;
    setState(() {
      _thinking = false;
      _messages.add(_Message(text: reply.text, isUser: false, isNote: !reply.ok));
    });
    _scrollToBottom();
  }

  void _scrollToBottom() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (_scrollCtrl.hasClients) {
        _scrollCtrl.animateTo(
          _scrollCtrl.position.maxScrollExtent,
          duration: const Duration(milliseconds: 300),
          curve: Curves.easeOut,
        );
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: Row(
          children: [
            Container(
              width: 34,
              height: 34,
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.secondary,
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 18),
            ),
            const SizedBox(width: 10),
            const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text('AI Coach',
                    style: TextStyle(
                        fontSize: 16, fontWeight: FontWeight.w700)),
                Text('Powered by Groq',
                    style: TextStyle(
                        fontSize: 10,
                        color: Colors.white38,
                        fontWeight: FontWeight.w400)),
              ],
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_outline_rounded,
                color: Colors.white38),
            tooltip: 'Clear chat',
            onPressed: () {
              AiService.reset(); // the server forgets the conversation too
              setState(() {
                _messages.clear();
                _messages.add(_Message(
                  text: "Fresh start! What's on your mind? 💪",
                  isUser: false,
                  isNote: true,
                ));
              });
            },
          ),
        ],
      ),
      body: Column(
        children: [
          // ── Messages list ──────────────────────────────────────────────
          Expanded(
            child: ListView.builder(
              controller: _scrollCtrl,
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
              itemCount: _messages.length + (_thinking ? 1 : 0),
              itemBuilder: (ctx, i) {
                if (i == _messages.length) {
                  return _thinkingBubble(theme);
                }
                final msg = _messages[i];
                return _messageBubble(msg, theme);
              },
            ),
          ),

          // ── Suggestions ────────────────────────────────────────────────
          if (_messages.length <= 1 && !_thinking)
            _suggestionsBar(theme),

          // ── Input bar ──────────────────────────────────────────────────
          _inputBar(theme),
        ],
      ),
    );
  }

  Widget _messageBubble(_Message msg, ThemeData theme) {
    final isUser = msg.isUser;
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Row(
        mainAxisAlignment:
            isUser ? MainAxisAlignment.end : MainAxisAlignment.start,
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          if (!isUser) ...[
            Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(right: 8, bottom: 2),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.secondary,
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 14),
            ),
          ],
          Flexible(
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 12),
              decoration: BoxDecoration(
                gradient: isUser
                    ? LinearGradient(
                        colors: [
                          theme.colorScheme.primary,
                          theme.colorScheme.primary.withOpacity(0.8),
                        ],
                      )
                    : null,
                color: isUser
                    ? null
                    : theme.colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.only(
                  topLeft:     const Radius.circular(18),
                  topRight:    const Radius.circular(18),
                  bottomLeft:  Radius.circular(isUser ? 18 : 4),
                  bottomRight: Radius.circular(isUser ? 4  : 18),
                ),
              ),
              child: Text(
                msg.text,
                style: TextStyle(
                  color: isUser ? Colors.white : Colors.white,
                  fontSize: 14,
                  height: 1.5,
                ),
              ),
            ).animate().fadeIn(duration: 300.ms).slideY(begin: 0.1),
          ),
          if (isUser) ...[
            Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(left: 8, bottom: 2),
              decoration: BoxDecoration(
                color: Colors.white12,
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.person_rounded,
                  color: Colors.white54, size: 16),
            ),
          ],
        ],
      ),
    );
  }

  Widget _thinkingBubble(ThemeData theme) => Padding(
        padding: const EdgeInsets.only(bottom: 12),
        child: Row(
          children: [
            Container(
              width: 30,
              height: 30,
              margin: const EdgeInsets.only(right: 8),
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  colors: [
                    theme.colorScheme.primary,
                    theme.colorScheme.secondary,
                  ],
                ),
                borderRadius: BorderRadius.circular(10),
              ),
              child: const Icon(Icons.auto_awesome_rounded,
                  color: Colors.white, size: 14),
            ),
            Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 16, vertical: 14),
              decoration: BoxDecoration(
                color: theme.colorScheme.surfaceContainerHighest,
                borderRadius: const BorderRadius.only(
                  topLeft:     Radius.circular(18),
                  topRight:    Radius.circular(18),
                  bottomRight: Radius.circular(18),
                  bottomLeft:  Radius.circular(4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('Thinking',
                      style: TextStyle(
                          color: Colors.white54, fontSize: 13)),
                  const SizedBox(width: 8),
                  _dot(0, theme),
                  _dot(150, theme),
                  _dot(300, theme),
                ],
              ),
            ),
          ],
        ),
      );

  Widget _dot(int delayMs, ThemeData theme) => Container(
        width: 6,
        height: 6,
        margin: const EdgeInsets.symmetric(horizontal: 2),
        decoration: BoxDecoration(
          color: theme.colorScheme.primary,
          shape: BoxShape.circle,
        ),
      )
          .animate(onPlay: (c) => c.repeat())
          .moveY(
              begin: 0,
              end: -4,
              delay: Duration(milliseconds: delayMs),
              duration: 400.ms,
              curve: Curves.easeInOut)
          .then()
          .moveY(begin: -4, end: 0, duration: 400.ms);

  Widget _suggestionsBar(ThemeData theme) => Container(
        height: 44,
        margin: const EdgeInsets.only(bottom: 4),
        child: ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          scrollDirection: Axis.horizontal,
          itemCount: _suggestions.length,
          separatorBuilder: (_, __) => const SizedBox(width: 8),
          itemBuilder: (_, i) => GestureDetector(
            onTap: () => _send(_suggestions[i]),
            child: Container(
              padding: const EdgeInsets.symmetric(
                  horizontal: 14, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.primary.withOpacity(0.15),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                    color:
                        theme.colorScheme.primary.withOpacity(0.3)),
              ),
              child: Text(
                _suggestions[i],
                style: TextStyle(
                  color: theme.colorScheme.primary,
                  fontSize: 12,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ),
        ),
      );

  Widget _inputBar(ThemeData theme) => Container(
        padding: EdgeInsets.fromLTRB(
            16, 8, 16, MediaQuery.of(context).padding.bottom + 8),
        decoration: BoxDecoration(
          color: theme.colorScheme.surface,
          border: Border(
              top: BorderSide(color: Colors.white10)),
        ),
        child: Row(
          children: [
            Expanded(
              child: TextField(
                controller: _controller,
                enabled: !_thinking,
                maxLines: null,
                textInputAction: TextInputAction.send,
                onSubmitted: _send,
                decoration: InputDecoration(
                  hintText: 'Ask about your fitness data...',
                  hintStyle:
                      const TextStyle(color: Colors.white30, fontSize: 14),
                  contentPadding: const EdgeInsets.symmetric(
                      horizontal: 16, vertical: 12),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(24),
                    borderSide: BorderSide.none,
                  ),
                  filled: true,
                  fillColor: theme.colorScheme.surfaceContainerHighest,
                ),
                style: const TextStyle(color: Colors.white, fontSize: 14),
              ),
            ),
            const SizedBox(width: 8),
            GestureDetector(
              onTap: _thinking
                  ? null
                  : () => _send(_controller.text),
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 200),
                width: 46,
                height: 46,
                decoration: BoxDecoration(
                  gradient: _thinking
                      ? null
                      : LinearGradient(
                          colors: [
                            theme.colorScheme.primary,
                            theme.colorScheme.secondary,
                          ],
                        ),
                  color: _thinking ? Colors.white12 : null,
                  borderRadius: BorderRadius.circular(23),
                ),
                child: Icon(
                  _thinking
                      ? Icons.hourglass_top_rounded
                      : Icons.send_rounded,
                  color: _thinking ? Colors.white24 : Colors.white,
                  size: 20,
                ),
              ),
            ),
          ],
        ),
      );
}
