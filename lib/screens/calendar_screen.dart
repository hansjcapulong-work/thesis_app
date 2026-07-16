import 'package:flutter/material.dart';
import '../data/daily_activity_service.dart';

class CalendarScreen extends StatefulWidget {
  const CalendarScreen({Key? key}) : super(key: key);

  @override
  State<CalendarScreen> createState() => _CalendarScreenState();
}

class _CalendarScreenState extends State<CalendarScreen> {
  DateTime _displayedMonth = DateTime(DateTime.now().year, DateTime.now().month);
  Map<String, Map<String, dynamic>> _monthData = {};
  bool _loading = true;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    setState(() => _loading = true);
    final data = await DailyActivityService.getMonth(_displayedMonth.year, _displayedMonth.month);
    if (!mounted) return;
    setState(() {
      _monthData = data;
      _loading = false;
    });
  }

  void _changeMonth(int delta) {
    setState(() => _displayedMonth = DateTime(_displayedMonth.year, _displayedMonth.month + delta));
    _load();
  }

  void _showDayDetail(DateTime day) {
    final key = DailyActivityService.dateKey(day);
    final data = _monthData[key];
    final activities = List<Map<String, dynamic>>.from((data?['activities'] as List?) ?? []);

    showModalBottomSheet(
      context: context,
      backgroundColor: Colors.white,
      shape: const RoundedRectangleBorder(borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (_) => Padding(
        padding: const EdgeInsets.all(24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              '${monthNames[day.month - 1]} ${day.day}, ${day.year}',
              style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38)),
            ),
            const SizedBox(height: 12),
            if (activities.isEmpty)
              const Text('No activity recorded this day.', style: TextStyle(color: Colors.grey))
            else ...[
              Text(
                '${(((data?['secondsPracticed'] as int?) ?? 0) / 60).round()} minutes practiced',
                style: const TextStyle(color: Colors.grey),
              ),
              const SizedBox(height: 10),
              ...activities.map((a) => Padding(
                padding: const EdgeInsets.symmetric(vertical: 4),
                child: Text(
                  '• ${a['type'] == 'quiz' ? 'Took quiz: ' : 'Watched: '}${a['label']}',
                  style: const TextStyle(color: Color(0xFF2A1B38)),
                ),
              )),
            ],
            const SizedBox(height: 10),
          ],
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final firstDayOfMonth = DateTime(_displayedMonth.year, _displayedMonth.month, 1);
    final daysInMonth = DateTime(_displayedMonth.year, _displayedMonth.month + 1, 0).day;
    final leadingBlanks = (firstDayOfMonth.weekday - 1) % 7;
    final now = DateTime.now();

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: Color(0xFF2A1B38)),
        title: const Text('Practice Calendar', style: TextStyle(color: Color(0xFF2A1B38), fontWeight: FontWeight.bold)),
      ),
      body: Padding(
        padding: const EdgeInsets.all(20),
        child: Column(
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                IconButton(icon: const Icon(Icons.chevron_left, color: Color(0xFF2A1B38)), onPressed: () => _changeMonth(-1)),
                Text(
                  '${monthNames[_displayedMonth.month - 1]} ${_displayedMonth.year}',
                  style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Color(0xFF2A1B38)),
                ),
                IconButton(icon: const Icon(Icons.chevron_right, color: Color(0xFF2A1B38)), onPressed: () => _changeMonth(1)),
              ],
            ),
            const SizedBox(height: 10),
            Row(
              children: ['M', 'T', 'W', 'T', 'F', 'S', 'S']
                  .map((d) => Expanded(child: Center(child: Text(d, style: const TextStyle(color: Colors.grey, fontWeight: FontWeight.bold)))))
                  .toList(),
            ),
            const SizedBox(height: 10),
            Expanded(
              child: _loading
                  ? const Center(child: CircularProgressIndicator(color: Color(0xFF2A1B38)))
                  : GridView.builder(
                gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                  crossAxisCount: 7,
                  mainAxisSpacing: 8,
                  crossAxisSpacing: 8,
                ),
                itemCount: leadingBlanks + daysInMonth,
                itemBuilder: (context, index) {
                  if (index < leadingBlanks) return const SizedBox();
                  final dayNum = index - leadingBlanks + 1;
                  final day = DateTime(_displayedMonth.year, _displayedMonth.month, dayNum);
                  final key = DailyActivityService.dateKey(day);
                  final completed = _monthData[key]?['completedGoal'] == true;
                  final isToday = day.year == now.year && day.month == now.month && day.day == now.day;

                  return GestureDetector(
                    onTap: () => _showDayDetail(day),
                    child: Container(
                      decoration: BoxDecoration(
                        color: completed ? const Color(0xFF2A1B38) : Colors.grey.shade100,
                        borderRadius: BorderRadius.circular(10),
                        border: isToday ? Border.all(color: const Color(0xFF2A1B38), width: 1.5) : null,
                      ),
                      alignment: Alignment.center,
                      child: Text(
                        '$dayNum',
                        style: TextStyle(
                          color: completed ? Colors.white : const Color(0xFF2A1B38),
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],
        ),
      ),
    );
  }
}