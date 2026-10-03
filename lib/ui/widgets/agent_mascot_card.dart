import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_tts/flutter_tts.dart';

import '../../app_state.dart';

/// The DriveSync agent character. He says (out loud and in a speech bubble)
/// what the sync is doing, bobbing while he talks. Tap him to hear it again.
class AgentMascotCard extends StatefulWidget {
  const AgentMascotCard({super.key, required this.state});
  final AppState state;

  @override
  State<AgentMascotCard> createState() => _AgentMascotCardState();
}

class _AgentMascotCardState extends State<AgentMascotCard>
    with SingleTickerProviderStateMixin {
  final FlutterTts _tts = FlutterTts();
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 350),
  );
  bool _muted = false;
  bool _talking = false;
  String? _lastSpoken;
  int _heardId = 0;
  String? _announcement;
  Timer? _clearAnnouncement;

  @override
  void initState() {
    super.initState();
    _tts.setSpeechRate(0.5);
    _tts.setPitch(1.25);
    _tts.setStartHandler(() => _setTalking(true));
    _tts.setCompletionHandler(() => _setTalking(false));
    _tts.setCancelHandler(() => _setTalking(false));
    _tts.setErrorHandler((_) => _setTalking(false));
  }

  void _setTalking(bool value) {
    if (!mounted) return;
    setState(() => _talking = value);
    if (value) {
      _bob.repeat(reverse: true);
    } else {
      _bob.animateTo(0);
    }
  }

  String _message() {
    final state = widget.state;
    if (_announcement != null) return _announcement!;
    final s = state.sync.status;
    if (state.isOffline) {
      return "You're offline. I'll pick up the backup as soon as you're back.";
    }
    if (!state.isConnected) {
      return "Hi! Connect Google Drive and I'll keep your files backed up.";
    }
    if (s.running) {
      return 'Uploading. ${s.doneCount} done, ${s.pendingCount} to go.';
    }
    if (s.failedCount > 0) {
      return "${s.failedCount} files failed. Check History and I'll retry.";
    }
    if (s.pendingCount > 0) {
      return '${s.pendingCount} files are waiting. Tap Back up when ready!';
    }
    if (s.lastRun != null) {
      return 'All caught up! Your files are safe on Google Drive.';
    }
    return 'Ready when you are. Pick a drive and run a scan.';
  }

  Future<void> _speak(String text) async {
    _lastSpoken = text;
    if (_muted) return;
    await _tts.stop();
    await _tts.speak(text);
  }

  @override
  void dispose() {
    _clearAnnouncement?.cancel();
    _tts.stop();
    _bob.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final agent = widget.state.agent;
    if (agent.announcementId != _heardId && agent.announcement != null) {
      _heardId = agent.announcementId;
      _announcement = agent.announcement;
      _clearAnnouncement?.cancel();
      _clearAnnouncement = Timer(const Duration(seconds: 12), () {
        if (mounted) setState(() => _announcement = null);
      });
    }
    final message = _message();
    // Speak whenever the status message changes. Progress counts change on
    // every file, so while uploading only announce the start, not each tick.
    final key = widget.state.sync.status.running ? 'running' : message;
    if (key != (_lastSpoken == null ? null : _keyFor(_lastSpoken!))) {
      _lastSpoken = message;
      WidgetsBinding.instance.addPostFrameCallback((_) => _speak(message));
    }

    return Card(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(12, 12, 8, 12),
        child: Row(
          children: [
            GestureDetector(
              onTap: () => _speak(message),
              child: AnimatedBuilder(
                animation: _bob,
                builder: (context, child) => Transform.translate(
                  offset: Offset(0, -6 * _bob.value),
                  child: Transform.rotate(
                    angle: 0.04 * (_bob.value - 0.5) * (_talking ? 1 : 0),
                    child: child,
                  ),
                ),
                child: Image.asset(
                  'assets/branding/agent_mascot.webp',
                  height: 110,
                  fit: BoxFit.contain,
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: AnimatedContainer(
                duration: const Duration(milliseconds: 250),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: scheme.primaryContainer,
                  borderRadius: BorderRadius.circular(16),
                  border: Border.all(
                    color: _talking ? scheme.primary : Colors.transparent,
                    width: 2,
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      _talking ? 'DriveSync Agent is talking…' : 'DriveSync Agent',
                      style: Theme.of(context).textTheme.labelLarge?.copyWith(
                            color: scheme.onPrimaryContainer,
                            fontWeight: FontWeight.w700,
                          ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      message,
                      style: TextStyle(color: scheme.onPrimaryContainer),
                    ),
                  ],
                ),
              ),
            ),
            IconButton(
              tooltip: agent.dailyLabel == null
                  ? 'Set daily backup time'
                  : 'Daily backup at ${agent.dailyLabel} (tap to change)',
              icon: Icon(agent.dailyLabel == null
                  ? Icons.alarm_add
                  : Icons.alarm_on),
              onPressed: () => _pickDailyTime(context),
            ),
            IconButton(
              tooltip: _muted ? 'Unmute agent' : 'Mute agent',
              icon: Icon(_muted ? Icons.volume_off : Icons.volume_up),
              onPressed: () {
                setState(() => _muted = !_muted);
                if (_muted) _tts.stop();
              },
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _pickDailyTime(BuildContext context) async {
    final agent = widget.state.agent;
    final current = agent.dailyTime;
    final picked = await showTimePicker(
      context: context,
      initialTime: current == null
          ? const TimeOfDay(hour: 21, minute: 0)
          : TimeOfDay(hour: current.$1, minute: current.$2),
      helpText: 'Daily backup time',
      cancelText: current == null ? 'Cancel' : 'Turn off',
    );
    if (picked != null) {
      await agent.setDailyTime(picked.hour, picked.minute);
    } else if (current != null) {
      await agent.setDailyTime(null, null);
    }
  }

  String _keyFor(String spoken) =>
      spoken.startsWith('Uploading.') ? 'running' : spoken;
}
