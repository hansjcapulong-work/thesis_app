import 'package:flutter/material.dart';
import '../services/conversation_history_service.dart';

const _purple = Color(0xFF2A1B38);

class HistoryScreen extends StatefulWidget {
  const HistoryScreen({Key? key}) : super(key: key);

  @override
  State<HistoryScreen> createState() => _HistoryScreenState();
}

class _HistoryScreenState extends State<HistoryScreen> {
  final Set<String> _selectedIds = {};
  bool _deleting = false;

  void _toggleSession(String id, bool selected) {
    setState(() {
      if (selected) {
        _selectedIds.add(id);
      } else {
        _selectedIds.remove(id);
      }
    });
  }

  void _toggleGroup(_DateGroup group, bool selectAll) {
    setState(() {
      for (final s in group.sessions) {
        if (selectAll) {
          _selectedIds.add(s.id);
        } else {
          _selectedIds.remove(s.id);
        }
      }
    });
  }

  void _clearSelection() {
    setState(() => _selectedIds.clear());
  }

  Future<void> _confirmAndDelete() async {
    final count = _selectedIds.length;
    if (count == 0) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete conversations?'),
        content: Text(
          count == 1
              ? 'This conversation will be permanently deleted.'
              : 'These $count conversations will be permanently deleted.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    );

    if (confirmed != true) return;

    setState(() => _deleting = true);
    try {
      await ConversationHistoryService.deleteSessions(_selectedIds.toList());
      _selectedIds.clear();
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Could not delete: $e')),
        );
      }
    } finally {
      if (mounted) setState(() => _deleting = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    final hasSelection = _selectedIds.isNotEmpty;

    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: _purple),
        leading: hasSelection
            ? IconButton(
          icon: const Icon(Icons.close, color: _purple),
          onPressed: _clearSelection,
        )
            : null,
        title: Text(
          hasSelection ? '${_selectedIds.length} selected' : 'Conversation History',
          style: const TextStyle(color: _purple, fontWeight: FontWeight.bold, fontSize: 16),
        ),
        actions: [
          if (hasSelection)
            IconButton(
              icon: _deleting
                  ? const SizedBox(
                width: 18,
                height: 18,
                child: CircularProgressIndicator(strokeWidth: 2, color: _purple),
              )
                  : const Icon(Icons.delete_outline, color: _purple),
              onPressed: _deleting ? null : _confirmAndDelete,
            ),
        ],
      ),
      body: StreamBuilder<List<ConversationSession>>(
        stream: ConversationHistoryService.streamSessions(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator(color: _purple));
          }
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Text(
                  'Could not load history.\n${snapshot.error}',
                  textAlign: TextAlign.center,
                  style: const TextStyle(color: Colors.grey),
                ),
              ),
            );
          }

          final sessions = snapshot.data ?? [];
          if (sessions.isEmpty) {
            return const Center(
              child: Text('No conversations yet.', style: TextStyle(color: Colors.grey)),
            );
          }

          // Drop selections for sessions that no longer exist (e.g. deleted
          // from elsewhere) so the count/dialog stay accurate.
          final liveIds = sessions.map((s) => s.id).toSet();
          _selectedIds.retainWhere(liveIds.contains);

          final groups = _groupByDate(sessions);

          return ListView.builder(
            padding: const EdgeInsets.all(16),
            itemCount: groups.length,
            itemBuilder: (context, index) {
              final group = groups[index];
              final allSelected = group.sessions.every((s) => _selectedIds.contains(s.id));
              final anySelected = group.sessions.any((s) => _selectedIds.contains(s.id));

              return Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Padding(
                    padding: const EdgeInsets.only(bottom: 8, top: 8),
                    child: Row(
                      children: [
                        SizedBox(
                          width: 32,
                          height: 32,
                          child: Checkbox(
                            value: allSelected ? true : (anySelected ? null : false),
                            tristate: true,
                            activeColor: _purple,
                            onChanged: (_) => _toggleGroup(group, !allSelected),
                          ),
                        ),
                        Text(
                          group.label,
                          style: TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                            color: Colors.grey.shade600,
                            letterSpacing: 0.3,
                          ),
                        ),
                      ],
                    ),
                  ),
                  ...group.sessions.map((s) => _SessionCard(
                    session: s,
                    selected: _selectedIds.contains(s.id),
                    onSelectedChanged: (v) => _toggleSession(s.id, v),
                  )),
                ],
              );
            },
          );
        },
      ),
    );
  }

  List<_DateGroup> _groupByDate(List<ConversationSession> sessions) {
    final groups = <_DateGroup>[];
    for (final session in sessions) {
      final label = _dateLabel(session.startedAt);
      if (groups.isNotEmpty && groups.last.label == label) {
        groups.last.sessions.add(session);
      } else {
        groups.add(_DateGroup(label: label, sessions: [session]));
      }
    }
    return groups;
  }

  String _dateLabel(DateTime date) {
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final that = DateTime(date.year, date.month, date.day);
    final diff = today.difference(that).inDays;
    if (diff == 0) return 'Today';
    if (diff == 1) return 'Yesterday';
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    return '${months[date.month - 1]} ${date.day}';
  }
}

class _DateGroup {
  final String label;
  final List<ConversationSession> sessions;
  _DateGroup({required this.label, required this.sessions});
}

class _SessionCard extends StatelessWidget {
  final ConversationSession session;
  final bool selected;
  final ValueChanged<bool> onSelectedChanged;

  const _SessionCard({
    required this.session,
    required this.selected,
    required this.onSelectedChanged,
  });

  String _formatTime(DateTime dt) {
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '$hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    final preview = session.entries.isNotEmpty ? session.entries.first.text : '';

    return GestureDetector(
      onTap: () => Navigator.push(
        context,
        MaterialPageRoute(builder: (_) => ConversationDetailScreen(session: session)),
      ),
      child: Container(
        margin: const EdgeInsets.only(bottom: 10),
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: selected ? _purple.withOpacity(0.05) : Colors.white,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: selected ? _purple.withOpacity(0.4) : Colors.grey.shade200),
        ),
        child: Row(
          children: [
            SizedBox(
              width: 32,
              height: 32,
              child: Checkbox(
                value: selected,
                activeColor: _purple,
                onChanged: (v) => onSelectedChanged(v ?? false),
              ),
            ),
            Container(
              width: 38,
              height: 38,
              decoration: const BoxDecoration(color: Color(0xFFEEEDFE), shape: BoxShape.circle),
              child: const Icon(Icons.chat_bubble_outline, size: 18, color: Color(0xFF3C3489)),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatTime(session.startedAt),
                        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.w600, color: _purple),
                      ),
                      Text(
                        '${session.entries.length} messages',
                        style: TextStyle(fontSize: 12, color: Colors.grey.shade500),
                      ),
                    ],
                  ),
                  const SizedBox(height: 4),
                  Text(
                    preview,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: TextStyle(fontSize: 13, color: Colors.grey.shade700),
                  ),
                ],
              ),
            ),
            Icon(Icons.chevron_right, size: 18, color: Colors.grey.shade400),
          ],
        ),
      ),
    );
  }
}

class ConversationDetailScreen extends StatelessWidget {
  final ConversationSession session;
  const ConversationDetailScreen({Key? key, required this.session}) : super(key: key);

  String _formatFullDate(DateTime dt) {
    const months = [
      'Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun',
      'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec',
    ];
    final hour = dt.hour % 12 == 0 ? 12 : dt.hour % 12;
    final minute = dt.minute.toString().padLeft(2, '0');
    final period = dt.hour >= 12 ? 'PM' : 'AM';
    return '${months[dt.month - 1]} ${dt.day}, $hour:$minute $period';
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.white,
      appBar: AppBar(
        backgroundColor: Colors.white,
        elevation: 0,
        iconTheme: const IconThemeData(color: _purple),
        title: Text(
          _formatFullDate(session.startedAt),
          style: const TextStyle(color: _purple, fontWeight: FontWeight.bold, fontSize: 16),
        ),
      ),
      body: session.entries.isEmpty
          ? const Center(child: Text('No messages in this conversation.', style: TextStyle(color: Colors.grey)))
          : ListView.builder(
        padding: const EdgeInsets.all(16),
        itemCount: session.entries.length,
        itemBuilder: (context, index) => _buildBubble(context, session.entries[index]),
      ),
    );
  }

  Widget _buildBubble(BuildContext context, ConversationEntryData entry) {
    final isSigned = entry.source == 'signed';
    return Align(
      alignment: isSigned ? Alignment.centerLeft : Alignment.centerRight,
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 4),
        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
        constraints: BoxConstraints(maxWidth: MediaQuery.of(context).size.width * 0.7),
        decoration: BoxDecoration(
          color: isSigned ? _purple.withOpacity(0.08) : _purple,
          borderRadius: BorderRadius.circular(14),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              isSigned ? 'Signed' : 'Spoken',
              style: TextStyle(
                color: isSigned ? _purple.withOpacity(0.6) : Colors.white54,
                fontSize: 10,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(height: 2),
            Text(
              entry.text,
              style: TextStyle(
                color: isSigned ? _purple : Colors.white,
                fontSize: 14,
                fontWeight: FontWeight.w500,
              ),
            ),
          ],
        ),
      ),
    );
  }
}