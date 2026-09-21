import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:provider/provider.dart';

import '../app_state.dart';
import '../models/storage_models.dart';
import '../services/browse_service.dart';
import 'widgets/local_thumb.dart';
import 'widgets/toast_notification.dart';

// ── sort options ──────────────────────────────────────────────────────────────

enum _SortBy { name, size, modified, type }

enum _ViewMode { grid, list }

// ── page ─────────────────────────────────────────────────────────────────────

class BrowsePage extends StatefulWidget {
  const BrowsePage({super.key});
  @override
  State<BrowsePage> createState() => _BrowsePageState();
}

class _BrowsePageState extends State<BrowsePage> {
  final List<_Crumb> _stack = [];
  List<BrowseEntry>? _raw;   // unsorted, from the service
  List<BrowseEntry>? _items; // sorted + filtered
  String? _error;
  bool _loading = false;
  final Set<String> _selected = {};
  final BrowseService _svc = BrowseService();
  final TextEditingController _search = TextEditingController();

  _SortBy _sortBy = _SortBy.name;
  bool _sortAsc = true;
  _ViewMode _view = _ViewMode.grid;
  String _filter = '';

  @override
  void initState() {
    super.initState();
    _search.addListener(() {
      setState(() {
        _filter = _search.text.toLowerCase();
        _applySort();
      });
    });
    WidgetsBinding.instance.addPostFrameCallback((_) => _load(null));
  }

  @override
  void dispose() {
    _search.dispose();
    super.dispose();
  }

  // ── data ─────────────────────────────────────────────────────────────────

  Future<void> _load(String? path) async {
    setState(() {
      _loading = true;
      _error = null;
      _raw = null;
      _items = null;
      _selected.clear();
      _search.clear();
      _filter = '';
    });
    if (path == null) {
      if (!mounted) return;
      final volumes = context.read<AppState>().volumes;
      final entries = volumes
          .map((v) => BrowseEntry(name: v.label, path: v.path, isDir: true))
          .toList();
      setState(() {
        _raw = entries;
        _applySort();
        _loading = false;
      });
      return;
    }
    try {
      final entries = await _svc.list(path);
      if (!mounted) return;
      setState(() {
        _raw = entries;
        _applySort();
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = e.toString();
        _loading = false;
      });
    }
  }

  void _applySort() {
    if (_raw == null) return;
    var list = _raw!.where((e) {
      if (_filter.isEmpty) return true;
      return e.name.toLowerCase().contains(_filter);
    }).toList();

    list.sort((a, b) {
      // Always dirs first when sorting by name or type.
      if (_sortBy == _SortBy.name || _sortBy == _SortBy.type) {
        if (a.isDir != b.isDir) return a.isDir ? -1 : 1;
      }
      int cmp;
      switch (_sortBy) {
        case _SortBy.name:
          cmp = a.name.toLowerCase().compareTo(b.name.toLowerCase());
        case _SortBy.size:
          cmp = a.bytes.compareTo(b.bytes);
        case _SortBy.modified:
          final am = a.modified ?? DateTime(0);
          final bm = b.modified ?? DateTime(0);
          cmp = am.compareTo(bm);
        case _SortBy.type:
          final ae = p.extension(a.name).toLowerCase();
          final be = p.extension(b.name).toLowerCase();
          cmp = ae.compareTo(be);
      }
      return _sortAsc ? cmp : -cmp;
    });
    _items = list;
  }

  void _setSort(_SortBy by) {
    setState(() {
      if (_sortBy == by) {
        _sortAsc = !_sortAsc;
      } else {
        _sortBy = by;
        _sortAsc = true;
      }
      _applySort();
    });
  }

  // ── navigation ──────────────────────────────────────────────────────────

  void _open(BrowseEntry e) {
    if (!e.isDir) return;
    _stack.add(_Crumb(e.name, e.path));
    _load(e.path);
  }

  void _navigateToCrumb(int index) {
    if (index < 0) {
      _stack.clear();
      _load(null);
    } else {
      _stack.removeRange(index + 1, _stack.length);
      _load(_stack[index].path);
    }
  }

  // ── selection ────────────────────────────────────────────────────────────

  void _toggleItem(BrowseEntry e) {
    setState(() {
      if (_selected.contains(e.path)) {
        _selected.remove(e.path);
      } else {
        _selected.add(e.path);
      }
    });
  }

  bool get _allSelected {
    final items = _items;
    if (items == null || items.isEmpty) return false;
    return items.every((e) => _selected.contains(e.path));
  }

  void _toggleSelectAll() {
    final items = _items ?? [];
    setState(() {
      if (_allSelected) {
        _selected.clear();
      } else {
        for (final e in items) {
          _selected.add(e.path);
        }
      }
    });
  }

  // ── queue for backup ─────────────────────────────────────────────────────

  Future<void> _queueSelected(BuildContext ctx) async {
    final items = _items;
    if (items == null) return;
    final chosen = items.where((e) => _selected.contains(e.path)).toList();

    final files = await _svc.collectFiles(chosen);
    if (!ctx.mounted) return;

    if (files.isEmpty) {
      showToast(
        ctx,
        type: ToastType.warning,
        title: 'Nothing to queue',
        message: 'The selected item(s) contain no readable files.',
      );
      return;
    }

    ctx.read<AppState>().sync.queue(files);
    setState(_selected.clear);

    showToast(
      ctx,
      type: ToastType.success,
      title: 'Added to backup queue',
      message:
          '${files.length} file${files.length == 1 ? '' : 's'} '
          'queued for upload to Google Drive.',
    );
  }

  // ── build ────────────────────────────────────────────────────────────────

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isRoot = _stack.isEmpty;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // ── address / breadcrumb bar ──
        _BreadcrumbBar(
          stack: _stack,
          isRoot: isRoot,
          onNavigate: _navigateToCrumb,
        ),

        // ── toolbar ──
        _Toolbar(
          sortBy: _sortBy,
          sortAsc: _sortAsc,
          view: _view,
          allSelected: _allSelected,
          anySelected: _selected.isNotEmpty,
          itemCount: _items?.length ?? 0,
          selectedCount: _selected.length,
          searchController: _search,
          onSetSort: _setSort,
          onToggleView: () =>
              setState(() => _view = _view == _ViewMode.grid
                  ? _ViewMode.list
                  : _ViewMode.grid),
          onSelectAll: _toggleSelectAll,
          onQueueBackup: () => _queueSelected(context),
          onClearSelection: () => setState(_selected.clear),
        ),

        // ── content ──
        Expanded(
          child: _loading
              ? const Center(child: CircularProgressIndicator())
              : _error != null
              ? _ErrorView(message: _error!)
              : (_items?.isEmpty ?? true)
              ? _filter.isNotEmpty
                  ? _EmptySearch(query: _filter)
                  : const _EmptyView()
              : _view == _ViewMode.grid
              ? _GridView(
                  items: _items!,
                  selected: _selected,
                  onTap: (e) => e.isDir ? _open(e) : _toggleItem(e),
                  onLongPress: _toggleItem,
                  onToggle: _toggleItem,
                )
              : _ListView(
                  items: _items!,
                  selected: _selected,
                  sortBy: _sortBy,
                  sortAsc: _sortAsc,
                  onSetSort: _setSort,
                  onTap: (e) => e.isDir ? _open(e) : _toggleItem(e),
                  onToggle: _toggleItem,
                  allSelected: _allSelected,
                  onSelectAll: _toggleSelectAll,
                ),
        ),
      ],
    );
  }
}

// ── breadcrumb bar ────────────────────────────────────────────────────────────

class _Crumb {
  const _Crumb(this.label, this.path);
  final String label;
  final String path;
}

class _BreadcrumbBar extends StatelessWidget {
  const _BreadcrumbBar({
    required this.stack,
    required this.isRoot,
    required this.onNavigate,
  });
  final List<_Crumb> stack;
  final bool isRoot;
  final void Function(int) onNavigate;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Container(
      color: scheme.surfaceContainerHighest,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
      child: Row(
        children: [
          // Back button
          IconButton(
            icon: const Icon(Icons.arrow_back, size: 18),
            tooltip: 'Back',
            onPressed: stack.isEmpty
                ? null
                : () => onNavigate(stack.length - 2),
            padding: EdgeInsets.zero,
            constraints: const BoxConstraints(minWidth: 32, minHeight: 32),
          ),
          const SizedBox(width: 4),
          // Breadcrumb chips
          Expanded(
            child: SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  _CrumbChip(
                    label: 'This PC',
                    icon: Icons.computer,
                    onTap: () => onNavigate(-1),
                    isLast: isRoot,
                  ),
                  for (int i = 0; i < stack.length; i++) ...[
                    Icon(
                      Icons.chevron_right,
                      size: 16,
                      color: scheme.onSurfaceVariant,
                    ),
                    _CrumbChip(
                      label: stack[i].label,
                      icon: Icons.folder,
                      onTap: () => onNavigate(i),
                      isLast: i == stack.length - 1,
                    ),
                  ],
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class _CrumbChip extends StatelessWidget {
  const _CrumbChip({
    required this.label,
    required this.icon,
    required this.onTap,
    required this.isLast,
  });
  final String label;
  final IconData icon;
  final VoidCallback onTap;
  final bool isLast;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(6),
      onTap: isLast ? null : onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              icon,
              size: 15,
              color: isLast ? scheme.primary : scheme.onSurfaceVariant,
            ),
            const SizedBox(width: 4),
            Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isLast ? FontWeight.w600 : FontWeight.normal,
                color: isLast ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ── toolbar ───────────────────────────────────────────────────────────────────

class _Toolbar extends StatelessWidget {
  const _Toolbar({
    required this.sortBy,
    required this.sortAsc,
    required this.view,
    required this.allSelected,
    required this.anySelected,
    required this.itemCount,
    required this.selectedCount,
    required this.searchController,
    required this.onSetSort,
    required this.onToggleView,
    required this.onSelectAll,
    required this.onQueueBackup,
    required this.onClearSelection,
  });

  final _SortBy sortBy;
  final bool sortAsc;
  final _ViewMode view;
  final bool allSelected;
  final bool anySelected;
  final int itemCount;
  final int selectedCount;
  final TextEditingController searchController;
  final void Function(_SortBy) onSetSort;
  final VoidCallback onToggleView;
  final VoidCallback onSelectAll;
  final VoidCallback onQueueBackup;
  final VoidCallback onClearSelection;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isSmall = MediaQuery.sizeOf(context).width < 700;

    return Container(
      decoration: BoxDecoration(
        color: anySelected
            ? scheme.primaryContainer.withValues(alpha: 0.3)
            : scheme.surface,
        border: Border(
          bottom: BorderSide(color: scheme.outlineVariant),
        ),
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          // Top row: select-all + sort chips + search + view toggle
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            child: Row(
              children: [
                // Select all checkbox
                Tooltip(
                  message: allSelected ? 'Deselect all' : 'Select all',
                  child: Checkbox(
                    value: allSelected,
                    tristate: anySelected && !allSelected,
                    onChanged: (_) => onSelectAll(),
                  ),
                ),
                if (!isSmall) ...[
                  _SortChip(
                    label: 'Name',
                    active: sortBy == _SortBy.name,
                    asc: sortAsc,
                    onTap: () => onSetSort(_SortBy.name),
                  ),
                  _SortChip(
                    label: 'Size',
                    active: sortBy == _SortBy.size,
                    asc: sortAsc,
                    onTap: () => onSetSort(_SortBy.size),
                  ),
                  _SortChip(
                    label: 'Date',
                    active: sortBy == _SortBy.modified,
                    asc: sortAsc,
                    onTap: () => onSetSort(_SortBy.modified),
                  ),
                  _SortChip(
                    label: 'Type',
                    active: sortBy == _SortBy.type,
                    asc: sortAsc,
                    onTap: () => onSetSort(_SortBy.type),
                  ),
                ] else
                  PopupMenuButton<_SortBy>(
                    tooltip: 'Sort by',
                    icon: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        const Icon(Icons.sort, size: 16),
                        const SizedBox(width: 4),
                        Text(
                          _sortLabel(sortBy),
                          style: const TextStyle(fontSize: 12),
                        ),
                        Icon(
                          sortAsc
                              ? Icons.arrow_upward
                              : Icons.arrow_downward,
                          size: 14,
                        ),
                      ],
                    ),
                    onSelected: onSetSort,
                    itemBuilder: (_) => [
                      for (final s in _SortBy.values)
                        PopupMenuItem(
                          value: s,
                          child: Text(_sortLabel(s)),
                        ),
                    ],
                  ),
                const Spacer(),
                // Search
                SizedBox(
                  width: isSmall ? 130 : 200,
                  height: 32,
                  child: TextField(
                    controller: searchController,
                    style: const TextStyle(fontSize: 13),
                    decoration: InputDecoration(
                      hintText: 'Search',
                      hintStyle: const TextStyle(fontSize: 13),
                      prefixIcon: const Icon(Icons.search, size: 16),
                      suffixIcon: searchController.text.isNotEmpty
                          ? IconButton(
                              icon: const Icon(Icons.close, size: 14),
                              padding: EdgeInsets.zero,
                              onPressed: () => searchController.clear(),
                            )
                          : null,
                      isDense: true,
                      contentPadding: const EdgeInsets.symmetric(vertical: 6),
                      border: OutlineInputBorder(
                        borderRadius: BorderRadius.circular(20),
                        borderSide: BorderSide(color: scheme.outline),
                      ),
                    ),
                  ),
                ),
                const SizedBox(width: 4),
                // Grid / List toggle
                IconButton(
                  tooltip: view == _ViewMode.grid ? 'List view' : 'Grid view',
                  icon: Icon(
                    view == _ViewMode.grid
                        ? Icons.view_list_outlined
                        : Icons.grid_view_outlined,
                    size: 20,
                  ),
                  onPressed: onToggleView,
                ),
              ],
            ),
          ),
          // Selection action bar
          if (anySelected)
            Container(
              padding: const EdgeInsets.fromLTRB(16, 0, 12, 6),
              child: Row(
                children: [
                  Text(
                    '$selectedCount of $itemCount selected',
                    style: TextStyle(
                      fontSize: 12,
                      color: scheme.primary,
                      fontWeight: FontWeight.w600,
                    ),
                  ),
                  const SizedBox(width: 8),
                  TextButton(
                    onPressed: onClearSelection,
                    child: const Text('Clear'),
                  ),
                  const Spacer(),
                  FilledButton.icon(
                    onPressed: onQueueBackup,
                    icon: const Icon(Icons.playlist_add, size: 18),
                    label: const Text('Queue for backup'),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }

  static String _sortLabel(_SortBy s) => switch (s) {
        _SortBy.name => 'Name',
        _SortBy.size => 'Size',
        _SortBy.modified => 'Date modified',
        _SortBy.type => 'Type',
      };
}

class _SortChip extends StatelessWidget {
  const _SortChip({
    required this.label,
    required this.active,
    required this.asc,
    required this.onTap,
  });
  final String label;
  final bool active;
  final bool asc;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      borderRadius: BorderRadius.circular(16),
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.normal,
                color: active ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
            if (active) ...[
              const SizedBox(width: 2),
              Icon(
                asc ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: scheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ── grid view ─────────────────────────────────────────────────────────────────

class _GridView extends StatelessWidget {
  const _GridView({
    required this.items,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onToggle,
  });
  final List<BrowseEntry> items;
  final Set<String> selected;
  final void Function(BrowseEntry) onTap;
  final void Function(BrowseEntry) onLongPress;
  final void Function(BrowseEntry) onToggle;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(builder: (context, c) {
      final cols = (c.maxWidth / 110).floor().clamp(2, 12);
      return GridView.builder(
        padding: const EdgeInsets.all(16),
        gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
          crossAxisCount: cols,
          mainAxisSpacing: 10,
          crossAxisSpacing: 10,
          childAspectRatio: 0.8,
        ),
        itemCount: items.length,
        itemBuilder: (ctx, i) {
          final e = items[i];
          final sel = selected.contains(e.path);
          return _GridTile(
            entry: e,
            selected: sel,
            onTap: () => onTap(e),
            onLongPress: () => onLongPress(e),
            onToggle: () => onToggle(e),
          );
        },
      );
    });
  }
}

class _GridTile extends StatelessWidget {
  const _GridTile({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onLongPress,
    required this.onToggle,
  });
  final BrowseEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onLongPress;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return GestureDetector(
      onTap: onTap,
      onLongPress: onLongPress,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 100),
        decoration: BoxDecoration(
          color: selected
              ? scheme.primaryContainer.withValues(alpha: 0.5)
              : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: selected ? scheme.primary : Colors.transparent,
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.all(6),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            // Icon + checkbox overlay
            Stack(
              clipBehavior: Clip.none,
              children: [
                SizedBox(
                  width: 72,
                  height: 72,
                  child: _entryIcon(context),
                ),
                // Checkbox top-left
                Positioned(
                  top: -4,
                  left: -4,
                  child: GestureDetector(
                    onTap: onToggle,
                    child: AnimatedContainer(
                      duration: const Duration(milliseconds: 100),
                      width: 20,
                      height: 20,
                      decoration: BoxDecoration(
                        color: selected ? scheme.primary : Colors.transparent,
                        borderRadius: BorderRadius.circular(4),
                        border: Border.all(
                          color: selected
                              ? scheme.primary
                              : scheme.outline.withValues(alpha: 0.6),
                          width: 1.5,
                        ),
                      ),
                      child: selected
                          ? Icon(Icons.check, size: 14, color: scheme.onPrimary)
                          : null,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 6),
            Text(
              entry.name,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontSize: 11,
                fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
            if (!entry.isDir && entry.bytes > 0)
              Text(
                formatBytes(entry.bytes),
                style: TextStyle(
                  fontSize: 10,
                  color: scheme.onSurfaceVariant,
                ),
              ),
          ],
        ),
      ),
    );
  }

  Widget _entryIcon(BuildContext context) {
    if (entry.isDir) return const _FolderIcon();
    final ext = p.extension(entry.name).toLowerCase();
    if (const {'.jpg', '.jpeg', '.png', '.gif', '.webp', '.heic', '.bmp'}
        .contains(ext)) {
      return ClipRRect(
        borderRadius: BorderRadius.circular(6),
        child: localThumb(entry.path, 72, _FileIcon(ext: ext)),
      );
    }
    return _FileIcon(ext: ext);
  }
}

// ── list view ─────────────────────────────────────────────────────────────────

class _ListView extends StatelessWidget {
  const _ListView({
    required this.items,
    required this.selected,
    required this.sortBy,
    required this.sortAsc,
    required this.onSetSort,
    required this.onTap,
    required this.onToggle,
    required this.allSelected,
    required this.onSelectAll,
  });
  final List<BrowseEntry> items;
  final Set<String> selected;
  final _SortBy sortBy;
  final bool sortAsc;
  final void Function(_SortBy) onSetSort;
  final void Function(BrowseEntry) onTap;
  final void Function(BrowseEntry) onToggle;
  final bool allSelected;
  final VoidCallback onSelectAll;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Column(
      children: [
        // Column headers
        Container(
          decoration: BoxDecoration(
            color: scheme.surfaceContainerHighest,
            border: Border(
              bottom: BorderSide(color: scheme.outlineVariant),
            ),
          ),
          child: Row(
            children: [
              SizedBox(
                width: 40,
                child: Checkbox(
                  value: allSelected,
                  onChanged: (_) => onSelectAll(),
                ),
              ),
              Expanded(
                flex: 5,
                child: _ColHeader(
                  label: 'Name',
                  active: sortBy == _SortBy.name,
                  asc: sortAsc,
                  onTap: () => onSetSort(_SortBy.name),
                ),
              ),
              Expanded(
                flex: 2,
                child: _ColHeader(
                  label: 'Date modified',
                  active: sortBy == _SortBy.modified,
                  asc: sortAsc,
                  onTap: () => onSetSort(_SortBy.modified),
                ),
              ),
              Expanded(
                flex: 1,
                child: _ColHeader(
                  label: 'Type',
                  active: sortBy == _SortBy.type,
                  asc: sortAsc,
                  onTap: () => onSetSort(_SortBy.type),
                ),
              ),
              Expanded(
                flex: 1,
                child: _ColHeader(
                  label: 'Size',
                  active: sortBy == _SortBy.size,
                  asc: sortAsc,
                  onTap: () => onSetSort(_SortBy.size),
                  rightAlign: true,
                ),
              ),
              const SizedBox(width: 12),
            ],
          ),
        ),
        // Rows
        Expanded(
          child: ListView.builder(
            padding: EdgeInsets.zero,
            itemCount: items.length,
            itemBuilder: (ctx, i) {
              final e = items[i];
              final sel = selected.contains(e.path);
              return _ListRow(
                entry: e,
                selected: sel,
                onTap: () => onTap(e),
                onToggle: () => onToggle(e),
              );
            },
          ),
        ),
      ],
    );
  }
}

class _ColHeader extends StatelessWidget {
  const _ColHeader({
    required this.label,
    required this.active,
    required this.asc,
    required this.onTap,
    this.rightAlign = false,
  });
  final String label;
  final bool active;
  final bool asc;
  final VoidCallback onTap;
  final bool rightAlign;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 10),
        child: Row(
          mainAxisAlignment:
              rightAlign ? MainAxisAlignment.end : MainAxisAlignment.start,
          children: [
            if (active && rightAlign) ...[
              Icon(
                asc ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: scheme.primary,
              ),
              const SizedBox(width: 2),
            ],
            Text(
              label,
              style: TextStyle(
                fontSize: 12,
                fontWeight: active ? FontWeight.w700 : FontWeight.w500,
                color: active ? scheme.primary : scheme.onSurfaceVariant,
              ),
            ),
            if (active && !rightAlign) ...[
              const SizedBox(width: 2),
              Icon(
                asc ? Icons.arrow_upward : Icons.arrow_downward,
                size: 12,
                color: scheme.primary,
              ),
            ],
          ],
        ),
      ),
    );
  }
}

class _ListRow extends StatelessWidget {
  const _ListRow({
    required this.entry,
    required this.selected,
    required this.onTap,
    required this.onToggle,
  });
  final BrowseEntry entry;
  final bool selected;
  final VoidCallback onTap;
  final VoidCallback onToggle;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final ext = entry.isDir
        ? 'Folder'
        : p.extension(entry.name).isEmpty
        ? 'File'
        : p.extension(entry.name).substring(1).toUpperCase();

    return InkWell(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 80),
        color: selected
            ? scheme.primaryContainer.withValues(alpha: 0.4)
            : Colors.transparent,
        child: Row(
          children: [
            // Checkbox
            SizedBox(
              width: 40,
              child: Checkbox(
                value: selected,
                onChanged: (_) => onToggle(),
              ),
            ),
            // Small icon
            SizedBox(
              width: 24,
              height: 24,
              child: entry.isDir
                  ? const _FolderIcon(size: 24)
                  : _FileIcon(
                      ext: p.extension(entry.name).toLowerCase(),
                      size: 24,
                    ),
            ),
            const SizedBox(width: 8),
            // Name
            Expanded(
              flex: 5,
              child: Text(
                entry.name,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: selected ? FontWeight.w600 : FontWeight.normal,
                ),
              ),
            ),
            // Date modified
            Expanded(
              flex: 2,
              child: Text(
                entry.modified != null
                    ? _fmtDate(entry.modified!)
                    : '',
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            // Type
            Expanded(
              flex: 1,
              child: Text(
                ext,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            // Size
            Expanded(
              flex: 1,
              child: Text(
                entry.isDir ? '' : formatBytes(entry.bytes),
                textAlign: TextAlign.end,
                style: TextStyle(
                  fontSize: 12,
                  color: scheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 12),
          ],
        ),
      ),
    );
  }

  static String _fmtDate(DateTime dt) {
    final now = DateTime.now();
    if (dt.year == now.year &&
        dt.month == now.month &&
        dt.day == now.day) {
      return 'Today ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
    }
    return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}  '
        '${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
  }
}

// ── folder icon ───────────────────────────────────────────────────────────────

class _FolderIcon extends StatelessWidget {
  const _FolderIcon({this.size = 72});
  final double size;

  @override
  Widget build(BuildContext context) {
    return CustomPaint(
      painter: _FolderPainter(
        color: const Color(0xFFFFC107),
        tabColor: const Color(0xFFFFD54F),
      ),
      size: Size(size, size),
    );
  }
}

class _FolderPainter extends CustomPainter {
  _FolderPainter({required this.color, required this.tabColor});
  final Color color;
  final Color tabColor;

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()..style = PaintingStyle.fill;
    final w = size.width;
    final h = size.height;

    paint.color = color.withValues(alpha: 0.55);
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, h * 0.22, w, h * 0.78),
        const Radius.circular(5),
      ),
      paint,
    );
    paint.color = tabColor;
    final tabPath = Path()
      ..moveTo(w * 0.04, h * 0.22)
      ..lineTo(w * 0.04, h * 0.14)
      ..quadraticBezierTo(w * 0.04, h * 0.10, w * 0.08, h * 0.10)
      ..lineTo(w * 0.38, h * 0.10)
      ..lineTo(w * 0.44, h * 0.22)
      ..close();
    canvas.drawPath(tabPath, paint);
    paint.color = color;
    canvas.drawRRect(
      RRect.fromRectAndRadius(
        Rect.fromLTWH(0, h * 0.26, w, h * 0.74),
        const Radius.circular(5),
      ),
      paint,
    );
  }

  @override
  bool shouldRepaint(covariant _FolderPainter old) =>
      old.color != color || old.tabColor != tabColor;
}

// ── file icon ─────────────────────────────────────────────────────────────────

class _FileIcon extends StatelessWidget {
  const _FileIcon({required this.ext, this.size = 72});
  final String ext;
  final double size;

  static const _extColor = {
    '.pdf': Color(0xFFE53935),
    '.ai': Color(0xFFFF6D00),
    '.psd': Color(0xFF1565C0),
    '.xd': Color(0xFFAD1457),
    '.indd': Color(0xFFC62828),
    '.jpg': Color(0xFF43A047),
    '.jpeg': Color(0xFF43A047),
    '.png': Color(0xFF00897B),
    '.gif': Color(0xFF6D4C41),
    '.webp': Color(0xFF00897B),
    '.heic': Color(0xFF4CAF50),
    '.bmp': Color(0xFF43A047),
    '.mp4': Color(0xFF7B1FA2),
    '.mov': Color(0xFF7B1FA2),
    '.avi': Color(0xFF6A1B9A),
    '.mkv': Color(0xFF6A1B9A),
    '.wmv': Color(0xFF6A1B9A),
    '.mp3': Color(0xFFE91E63),
    '.wav': Color(0xFFE91E63),
    '.flac': Color(0xFFD81B60),
    '.aac': Color(0xFFD81B60),
    '.zip': Color(0xFF4A148C),
    '.rar': Color(0xFF4A148C),
    '.7z': Color(0xFF4A148C),
    '.tar': Color(0xFF4A148C),
    '.gz': Color(0xFF4A148C),
    '.doc': Color(0xFF1565C0),
    '.docx': Color(0xFF1565C0),
    '.xls': Color(0xFF2E7D32),
    '.xlsx': Color(0xFF2E7D32),
    '.ppt': Color(0xFFBF360C),
    '.pptx': Color(0xFFBF360C),
    '.txt': Color(0xFF546E7A),
    '.csv': Color(0xFF2E7D32),
    '.dart': Color(0xFF0288D1),
    '.py': Color(0xFF0288D1),
    '.js': Color(0xFFF9A825),
    '.ts': Color(0xFF0277BD),
    '.html': Color(0xFFE64A19),
    '.css': Color(0xFF1565C0),
    '.json': Color(0xFF00695C),
    '.xml': Color(0xFF00695C),
    '.exe': Color(0xFF37474F),
    '.msi': Color(0xFF37474F),
    '.apk': Color(0xFF2E7D32),
    '.iso': Color(0xFF37474F),
    '.svg': Color(0xFFFF6D00),
    '.eps': Color(0xFFFF6D00),
    '.ttf': Color(0xFF6D4C41),
    '.otf': Color(0xFF6D4C41),
  };

  @override
  Widget build(BuildContext context) {
    final color = _extColor[ext] ?? const Color(0xFF78909C);
    final raw = ext.isEmpty
        ? 'FILE'
        : ext.substring(1).toUpperCase();
    final label = raw.length > 4 ? raw.substring(0, 4) : raw;

    return CustomPaint(
      painter: _FilePainter(color: color, label: label, size: size),
      size: Size(size, size),
    );
  }
}

class _FilePainter extends CustomPainter {
  _FilePainter({
    required this.color,
    required this.label,
    required this.size,
  });
  final Color color;
  final String label;
  final double size;

  @override
  void paint(Canvas canvas, Size sz) {
    final w = sz.width;
    final h = sz.height;
    final fold = w * 0.28;
    const rr = Radius.circular(4);

    final body = Path()
      ..moveTo(0, 0)
      ..lineTo(w - fold, 0)
      ..lineTo(w, fold)
      ..lineTo(w, h)
      ..lineTo(0, h)
      ..close();

    canvas.drawPath(body, Paint()..color = Colors.white);

    canvas.drawPath(
      Path()
        ..moveTo(w - fold, 0)
        ..lineTo(w, fold)
        ..lineTo(w - fold, fold)
        ..close(),
      Paint()..color = color.withValues(alpha: 0.35),
    );

    canvas.drawRRect(
      RRect.fromRectAndCorners(
        Rect.fromLTWH(0, h * 0.58, w, h * 0.42),
        bottomLeft: rr,
        bottomRight: rr,
      ),
      Paint()..color = color,
    );

    // Only draw label if icon is big enough
    if (size >= 30) {
      final tp = TextPainter(
        text: TextSpan(
          text: label,
          style: TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: w * (label.length > 3 ? 0.18 : 0.22),
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: w);
      tp.paint(canvas, Offset((w - tp.width) / 2, h * 0.66));
    }

    canvas.drawPath(
      body,
      Paint()
        ..color = color.withValues(alpha: 0.4)
        ..style = PaintingStyle.stroke
        ..strokeWidth = 1,
    );
  }

  @override
  bool shouldRepaint(covariant _FilePainter old) =>
      old.color != color || old.label != label || old.size != size;
}

// ── empty / error ─────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  const _EmptyView();
  @override
  Widget build(BuildContext context) => Center(
    child: Text(
      'This folder is empty.',
      style: Theme.of(context).textTheme.bodySmall,
    ),
  );
}

class _EmptySearch extends StatelessWidget {
  const _EmptySearch({required this.query});
  final String query;
  @override
  Widget build(BuildContext context) => Center(
    child: Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Icon(
          Icons.search_off,
          size: 40,
          color: Theme.of(context).colorScheme.outline,
        ),
        const SizedBox(height: 10),
        Text(
          'No results for "$query"',
          style: Theme.of(context).textTheme.bodySmall,
        ),
      ],
    ),
  );
}

class _ErrorView extends StatelessWidget {
  const _ErrorView({required this.message});
  final String message;
  @override
  Widget build(BuildContext context) => Center(
    child: Padding(
      padding: const EdgeInsets.all(32),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.lock_outline,
            size: 48,
            color: Theme.of(context).colorScheme.error,
          ),
          const SizedBox(height: 12),
          Text(
            message,
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ],
      ),
    ),
  );
}
