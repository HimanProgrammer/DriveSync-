import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../services/todo_service.dart';

/// To-do list the DriveSync Agent can read out loud. Stored on the device,
/// so it works offline.
class TodoPage extends StatefulWidget {
  const TodoPage({super.key});

  @override
  State<TodoPage> createState() => _TodoPageState();
}

class _TodoPageState extends State<TodoPage> {
  final _title = TextEditingController();
  final _minutes = TextEditingController();
  final FlutterTts _tts = FlutterTts();
  bool _reading = false;

  @override
  void initState() {
    super.initState();
    _tts.setPitch(1.25);
    _tts.setSpeechRate(0.5);
    _tts.setCompletionHandler(() => _setReading(false));
    _tts.setCancelHandler(() => _setReading(false));
    _tts.setErrorHandler((_) => _setReading(false));
  }

  void _setReading(bool v) {
    if (mounted) setState(() => _reading = v);
  }

  Future<void> _read(TodoService todos) async {
    if (_reading) {
      await _tts.stop();
      _setReading(false);
      return;
    }
    _setReading(true);
    await _tts.speak(todos.spokenSummary());
  }

  void _add(TodoService todos) {
    todos.add(_title.text, minutes: int.tryParse(_minutes.text.trim()));
    _title.clear();
    _minutes.clear();
  }

  @override
  void dispose() {
    _tts.stop();
    _title.dispose();
    _minutes.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final todos = context.watch<AppState>().todos;
    final theme = Theme.of(context);

    return ListView(
      padding: const EdgeInsets.all(20),
      children: [
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Image.asset('assets/branding/agent_mascot.webp', height: 80),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text('My To-Do List', style: theme.textTheme.titleLarge),
                      const SizedBox(height: 4),
                      Text(
                        todos.open.isEmpty
                            ? 'Nothing left to do.'
                            : '${todos.open.length} left'
                                  '${todos.openMinutes > 0 ? ' · about ${formatMinutes(todos.openMinutes)}' : ''}',
                      ),
                    ],
                  ),
                ),
                FilledButton.icon(
                  onPressed: () => _read(todos),
                  icon: Icon(_reading ? Icons.stop : Icons.record_voice_over),
                  label: Text(_reading ? 'Stop' : 'Read my list'),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        Card(
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _title,
                    decoration: const InputDecoration(
                      labelText: 'New task',
                      hintText: 'e.g. Back up holiday photos',
                    ),
                    onSubmitted: (_) => _add(todos),
                  ),
                ),
                const SizedBox(width: 12),
                SizedBox(
                  width: 110,
                  child: TextField(
                    controller: _minutes,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Est. minutes',
                    ),
                    onSubmitted: (_) => _add(todos),
                  ),
                ),
                const SizedBox(width: 12),
                IconButton.filled(
                  tooltip: 'Add task',
                  onPressed: () => _add(todos),
                  icon: const Icon(Icons.add),
                ),
              ],
            ),
          ),
        ),
        const SizedBox(height: 16),
        if (todos.items.isEmpty)
          const Padding(
            padding: EdgeInsets.all(24),
            child: Center(child: Text('Add your first task above.')),
          )
        else
          Card(
            child: Column(
              children: [
                for (final t in todos.items)
                  CheckboxListTile(
                    value: t.done,
                    onChanged: (_) => todos.toggle(t),
                    controlAffinity: ListTileControlAffinity.leading,
                    title: Text(
                      t.title,
                      style: t.done
                          ? const TextStyle(
                              decoration: TextDecoration.lineThrough,
                            )
                          : null,
                    ),
                    subtitle: t.minutes == null
                        ? null
                        : Text('About ${formatMinutes(t.minutes!)}'),
                    secondary: IconButton(
                      tooltip: 'Delete',
                      icon: const Icon(Icons.delete_outline),
                      onPressed: () => todos.remove(t),
                    ),
                  ),
                if (todos.items.any((t) => t.done))
                  TextButton(
                    onPressed: todos.clearDone,
                    child: const Text('Clear completed'),
                  ),
              ],
            ),
          ),
      ],
    );
  }
}
