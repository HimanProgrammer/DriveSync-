import 'package:flutter/material.dart';

import '../../app_state.dart';
import '../../models/storage_models.dart';

/// Phone home header: greeting, search, category shortcuts and a banner,
/// in the style of a modern mobile app.
class PhoneHome extends StatelessWidget {
  const PhoneHome({super.key, required this.state});
  final AppState state;

  static const _cats = [
    (FileCategory.images, Icons.photo_outlined, 'Photos'),
    (FileCategory.videos, Icons.videocam_outlined, 'Videos'),
    (FileCategory.documents, Icons.description_outlined, 'Docs'),
    (FileCategory.audio, Icons.music_note_outlined, 'Music'),
    (FileCategory.archives, Icons.folder_zip_outlined, 'Archives'),
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final scheme = theme.colorScheme;
    final name = state.account?.displayName ?? 'there';
    final pendingDeletes = state.sync.pendingDeletions.length;
    final scan = state.currentScan;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // Greeting + notification bell.
        Row(
          children: [
            CircleAvatar(
              radius: 22,
              backgroundColor: scheme.primaryContainer,
              child: ClipOval(
                child: Transform.scale(
                  scale: 2.2,
                  alignment: const Alignment(0, -0.75),
                  child: Image.asset('assets/branding/agent_mascot.webp'),
                ),
              ),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text('Hello 👋', style: theme.textTheme.bodyMedium),
                  Text(
                    name,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: theme.textTheme.titleLarge?.copyWith(
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                ],
              ),
            ),
            Badge(
              isLabelVisible: pendingDeletes > 0,
              label: Text('$pendingDeletes'),
              child: IconButton.outlined(
                tooltip: pendingDeletes > 0
                    ? '$pendingDeletes files ready to delete'
                    : 'No notifications',
                onPressed: () => ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(
                      pendingDeletes > 0
                          ? '$pendingDeletes uploaded files are waiting for you '
                                'to approve deleting them (Backup tab).'
                          : 'No notifications.',
                    ),
                  ),
                ),
                icon: const Icon(Icons.notifications_none),
              ),
            ),
          ],
        ),
        const SizedBox(height: 16),

        // Search + filter.
        Row(
          children: [
            Expanded(
              child: TextField(
                textInputAction: TextInputAction.search,
                onSubmitted: (q) => _search(context, q),
                decoration: InputDecoration(
                  hintText: 'Search your big files',
                  prefixIcon: const Icon(Icons.search),
                  filled: true,
                  fillColor: scheme.surfaceContainerHighest,
                  contentPadding: const EdgeInsets.symmetric(vertical: 0),
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide.none,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),
            IconButton.filled(
              style: IconButton.styleFrom(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(14),
                ),
                minimumSize: const Size(48, 48),
              ),
              tooltip: 'Analyse storage',
              onPressed: state.progress == null ? state.startScan : null,
              icon: const Icon(Icons.tune),
            ),
          ],
        ),
        const SizedBox(height: 18),

        // Category shortcuts.
        Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            for (final (cat, icon, label) in _cats)
              _CategoryButton(
                icon: icon,
                label: label,
                size: scan?.categories
                    .where((c) => c.category == cat)
                    .map((c) => formatBytes(c.bytes))
                    .firstOrNull,
                onTap: () => _search(context, '', category: cat),
              ),
          ],
        ),
        const SizedBox(height: 18),

        // Banner.
        _Banner(state: state),
        const SizedBox(height: 16),
      ],
    );
  }

  void _search(BuildContext context, String query, {FileCategory? category}) {
    final scan = state.currentScan;
    if (scan == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: const Text('Analyse your storage first to find files.'),
          action: SnackBarAction(label: 'Analyse', onPressed: state.startScan),
        ),
      );
      return;
    }
    final q = query.trim().toLowerCase();
    final hits = scan.largestFiles
        .where((f) => category == null || f.category == category)
        .where((f) => q.isEmpty || f.name.toLowerCase().contains(q))
        .toList();
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (context) => hits.isEmpty
          ? const Padding(
              padding: EdgeInsets.all(24),
              child: Text('No matching big files found.'),
            )
          : ListView(
              children: [
                for (final f in hits)
                  ListTile(
                    leading: const Icon(Icons.insert_drive_file_outlined),
                    title: Text(
                      f.name,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    subtitle: Text(
                      '${formatBytes(f.bytes)} · ${f.ageInDays} days old',
                    ),
                  ),
              ],
            ),
    );
  }
}

class _CategoryButton extends StatelessWidget {
  const _CategoryButton({
    required this.icon,
    required this.label,
    required this.onTap,
    this.size,
  });
  final IconData icon;
  final String label;
  final String? size;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.all(4),
        child: Column(
          children: [
            Container(
              width: 52,
              height: 52,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Icon(icon, color: theme.colorScheme.primary),
            ),
            const SizedBox(height: 6),
            Text(label, style: theme.textTheme.labelMedium),
            if (size != null) Text(size!, style: theme.textTheme.labelSmall),
          ],
        ),
      ),
    );
  }
}

class _Banner extends StatelessWidget {
  const _Banner({required this.state});
  final AppState state;

  @override
  Widget build(BuildContext context) {
    final (title, subtitle, button, action) = !state.isConnected
        ? (
            'Back up to Google Drive',
            'Connect your account to keep big files safe and free up space.',
            'Connect Drive',
            state.connectDrive,
          )
        : state.sync.status.pendingCount > 0
        ? (
            'Free up space',
            '${state.sync.status.pendingCount} files are ready to back up.',
            'Back up now',
            () => state.backupNow(),
          )
        : (
            'Your phone, tidy',
            'Find big files you no longer use and move them to Drive.',
            'Analyse storage',
            state.startScan,
          );
    return Container(
      padding: const EdgeInsets.fromLTRB(18, 16, 8, 16),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(20),
        gradient: const LinearGradient(
          colors: [Color(0xFF1D4ED8), Color(0xFF3B82F6)],
          begin: Alignment.topLeft,
          end: Alignment.bottomRight,
        ),
      ),
      child: Row(
        children: [
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.w700,
                  ),
                ),
                const SizedBox(height: 4),
                Text(
                  subtitle,
                  style: const TextStyle(color: Colors.white70, fontSize: 13),
                ),
                const SizedBox(height: 12),
                FilledButton(
                  style: FilledButton.styleFrom(
                    backgroundColor: Colors.white,
                    foregroundColor: const Color(0xFF1D4ED8),
                  ),
                  onPressed: action,
                  child: Text(button),
                ),
              ],
            ),
          ),
          Image.asset('assets/branding/agent_mascot.webp', height: 110),
        ],
      ),
    );
  }
}
