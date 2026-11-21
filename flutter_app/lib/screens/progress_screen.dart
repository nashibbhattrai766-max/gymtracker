import 'package:flutter/material.dart';
import 'insights_screen.dart';
import 'monthly_screen.dart';
import 'weekly_screen.dart';

/// Week, Month and Insights under one tab (keeps the bottom bar to 5 items).
class ProgressScreen extends StatefulWidget {
  const ProgressScreen({super.key});
  @override
  State<ProgressScreen> createState() => _ProgressScreenState();
}

class _ProgressScreenState extends State<ProgressScreen> {
  int _view = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          SafeArea(
            bottom: false,
            child: Padding(
              padding: const EdgeInsets.fromLTRB(16, 10, 16, 0),
              child: SizedBox(
                width: double.infinity,
                child: SegmentedButton<int>(
                  segments: const [
                    ButtonSegment(value: 0, label: Text('Week'), icon: Icon(Icons.bar_chart_rounded)),
                    ButtonSegment(value: 1, label: Text('Month'), icon: Icon(Icons.calendar_month_rounded)),
                    ButtonSegment(value: 2, label: Text('Insights'), icon: Icon(Icons.auto_awesome_rounded)),
                  ],
                  selected: {_view},
                  showSelectedIcon: false,
                  onSelectionChanged: (s) => setState(() => _view = s.first),
                ),
              ),
            ),
          ),
          // The inner screens keep their own app bars (titles + prev/next
          // arrows); remove the status-bar padding they'd otherwise add again.
          Expanded(
            child: MediaQuery.removePadding(
              context: context,
              removeTop: true,
              child: IndexedStack(
                index: _view,
                children: const [WeeklyScreen(), MonthlyScreen(), InsightsScreen()],
              ),
            ),
          ),
        ],
      ),
    );
  }
}
