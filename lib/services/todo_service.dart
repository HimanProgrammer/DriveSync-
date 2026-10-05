import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

class TodoItem {
  TodoItem({
    required this.id,
    required this.title,
    this.minutes,
    this.done = false,
  });

  final String id;
  final String title;

  /// Estimated time in minutes, or null when not given.
  final int? minutes;
  bool done;

  Map<String, dynamic> toJson() => {
    'id': id,
    'title': title,
    'minutes': minutes,
    'done': done,
  };

  factory TodoItem.fromJson(Map<String, dynamic> m) => TodoItem(
    id: m['id'] as String,
    title: m['title'] as String,
    minutes: (m['minutes'] as num?)?.toInt(),
    done: m['done'] as bool? ?? false,
  );
}

/// The user's to-do list, stored on the device so it works fully offline.
class TodoService extends ChangeNotifier {
  static const _kTodos = 'agent.todos';

  SharedPreferences? _prefs;
  final List<TodoItem> items = [];

  List<TodoItem> get open => items.where((t) => !t.done).toList();
  int get openMinutes => open.fold(0, (a, t) => a + (t.minutes ?? 0));

  Future<void> load() async {
    _prefs = await SharedPreferences.getInstance();
    final raw = _prefs!.getString(_kTodos);
    if (raw == null) return;
    try {
      items
        ..clear()
        ..addAll(
          (jsonDecode(raw) as List).map(
            (e) => TodoItem.fromJson(e as Map<String, dynamic>),
          ),
        );
    } catch (_) {
      // A corrupt list shouldn't stop the app; start fresh.
    }
    notifyListeners();
  }

  void add(String title, {int? minutes}) {
    final t = title.trim();
    if (t.isEmpty) return;
    items.add(
      TodoItem(
        id: DateTime.now().microsecondsSinceEpoch.toString(),
        title: t,
        minutes: minutes,
      ),
    );
    _save();
  }

  void toggle(TodoItem item) {
    item.done = !item.done;
    _save();
  }

  void remove(TodoItem item) {
    items.remove(item);
    _save();
  }

  void clearDone() {
    items.removeWhere((t) => t.done);
    _save();
  }

  /// What the agent says when asked to read the list.
  String spokenSummary() {
    final list = open;
    if (list.isEmpty) return 'Your to-do list is empty. Nice work!';
    final b = StringBuffer(
      'You have ${list.length} ${list.length == 1 ? 'task' : 'tasks'} left. ',
    );
    for (var i = 0; i < list.length; i++) {
      b.write('${i + 1}. ${list[i].title}');
      final m = list[i].minutes;
      if (m != null) b.write(', about ${formatMinutes(m)}');
      b.write('. ');
    }
    if (openMinutes > 0) {
      b.write('In total, about ${formatMinutes(openMinutes)}.');
    }
    return b.toString();
  }

  void _save() {
    _prefs?.setString(
      _kTodos,
      jsonEncode(items.map((t) => t.toJson()).toList()),
    );
    notifyListeners();
  }
}

String formatMinutes(int m) {
  if (m < 60) return '$m minutes';
  final h = m ~/ 60, r = m % 60;
  final hs = '$h ${h == 1 ? 'hour' : 'hours'}';
  return r == 0 ? hs : '$hs $r minutes';
}
