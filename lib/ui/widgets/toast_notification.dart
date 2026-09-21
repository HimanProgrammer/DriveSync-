import 'package:flutter/material.dart';

enum ToastType { success, warning, error, info }

/// Show a Windows-style toast that slides in from the top-right,
/// stays for [duration], then slides back out.
void showToast(
  BuildContext context, {
  required String title,
  required String message,
  ToastType type = ToastType.success,
  Duration duration = const Duration(seconds: 4),
  VoidCallback? onAction,
  String? actionLabel,
}) {
  final overlay = Overlay.of(context, rootOverlay: true);
  late OverlayEntry entry;
  entry = OverlayEntry(
    builder: (_) => _ToastOverlay(
      title: title,
      message: message,
      type: type,
      duration: duration,
      onAction: onAction,
      actionLabel: actionLabel,
      onDismiss: () => entry.remove(),
    ),
  );
  overlay.insert(entry);
}

class _ToastOverlay extends StatefulWidget {
  const _ToastOverlay({
    required this.title,
    required this.message,
    required this.type,
    required this.duration,
    required this.onDismiss,
    this.onAction,
    this.actionLabel,
  });
  final String title;
  final String message;
  final ToastType type;
  final Duration duration;
  final VoidCallback onDismiss;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  State<_ToastOverlay> createState() => _ToastOverlayState();
}

class _ToastOverlayState extends State<_ToastOverlay>
    with SingleTickerProviderStateMixin {
  late final AnimationController _ctrl;
  late final Animation<Offset> _slide;
  late final Animation<double> _fade;

  @override
  void initState() {
    super.initState();
    _ctrl = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 320),
    );
    _slide = Tween<Offset>(
      begin: const Offset(1.2, 0),
      end: Offset.zero,
    ).animate(CurvedAnimation(parent: _ctrl, curve: Curves.easeOutCubic));
    _fade = CurvedAnimation(parent: _ctrl, curve: Curves.easeIn);

    _ctrl.forward();

    // Auto dismiss
    Future.delayed(widget.duration - const Duration(milliseconds: 400), () {
      if (mounted) _dismiss();
    });
  }

  Future<void> _dismiss() async {
    if (!mounted) return;
    await _ctrl.reverse();
    widget.onDismiss();
  }

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Positioned(
      top: 24,
      right: 24,
      child: SlideTransition(
        position: _slide,
        child: FadeTransition(
          opacity: _fade,
          child: _ToastCard(
            title: widget.title,
            message: widget.message,
            type: widget.type,
            duration: widget.duration,
            onClose: _dismiss,
            onAction: widget.onAction,
            actionLabel: widget.actionLabel,
          ),
        ),
      ),
    );
  }
}

class _ToastCard extends StatefulWidget {
  const _ToastCard({
    required this.title,
    required this.message,
    required this.type,
    required this.duration,
    required this.onClose,
    this.onAction,
    this.actionLabel,
  });
  final String title;
  final String message;
  final ToastType type;
  final Duration duration;
  final VoidCallback onClose;
  final VoidCallback? onAction;
  final String? actionLabel;

  @override
  State<_ToastCard> createState() => _ToastCardState();
}

class _ToastCardState extends State<_ToastCard>
    with SingleTickerProviderStateMixin {
  late final AnimationController _progress;

  @override
  void initState() {
    super.initState();
    _progress = AnimationController(
      vsync: this,
      duration: widget.duration,
    )..forward();
  }

  @override
  void dispose() {
    _progress.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final isDark = Theme.of(context).brightness == Brightness.dark;

    final (accent, bg, icon, iconBg) = switch (widget.type) {
      ToastType.success => (
          const Color(0xFF2E7D32),
          isDark ? const Color(0xFF1B2E1C) : const Color(0xFFE8F5E9),
          Icons.check_circle_rounded,
          const Color(0xFF4CAF50),
        ),
      ToastType.warning => (
          const Color(0xFFF57F17),
          isDark ? const Color(0xFF2C2310) : const Color(0xFFFFF8E1),
          Icons.warning_amber_rounded,
          const Color(0xFFFFC107),
        ),
      ToastType.error => (
          const Color(0xFFC62828),
          isDark ? const Color(0xFF2C1010) : const Color(0xFFFFEBEE),
          Icons.error_rounded,
          const Color(0xFFEF5350),
        ),
      ToastType.info => (
          scheme.primary,
          isDark
              ? scheme.primaryContainer.withValues(alpha: 0.3)
              : scheme.primaryContainer.withValues(alpha: 0.2),
          Icons.info_rounded,
          scheme.primary,
        ),
    };

    return Material(
      color: Colors.transparent,
      child: Container(
        width: 340,
        decoration: BoxDecoration(
          color: bg,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(
            color: accent.withValues(alpha: 0.35),
            width: 1.2,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: isDark ? 0.45 : 0.12),
              blurRadius: 20,
              offset: const Offset(0, 6),
            ),
          ],
        ),
        child: ClipRRect(
          borderRadius: BorderRadius.circular(14),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // ── content row ──
              Padding(
                padding: const EdgeInsets.fromLTRB(14, 14, 10, 10),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Icon bubble
                    Container(
                      width: 40,
                      height: 40,
                      decoration: BoxDecoration(
                        color: iconBg.withValues(alpha: 0.18),
                        shape: BoxShape.circle,
                      ),
                      child: Icon(icon, color: iconBg, size: 22),
                    ),
                    const SizedBox(width: 12),
                    // Text
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            widget.title,
                            style: TextStyle(
                              fontWeight: FontWeight.w700,
                              fontSize: 14,
                              color: accent,
                            ),
                          ),
                          const SizedBox(height: 3),
                          Text(
                            widget.message,
                            style: TextStyle(
                              fontSize: 13,
                              color: isDark
                                  ? Colors.white70
                                  : Colors.black87,
                              height: 1.35,
                            ),
                          ),
                          if (widget.actionLabel != null &&
                              widget.onAction != null) ...[
                            const SizedBox(height: 8),
                            InkWell(
                              onTap: () {
                                widget.onAction!();
                                widget.onClose();
                              },
                              borderRadius: BorderRadius.circular(6),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(
                                    vertical: 2),
                                child: Text(
                                  widget.actionLabel!,
                                  style: TextStyle(
                                    color: accent,
                                    fontWeight: FontWeight.w600,
                                    fontSize: 13,
                                    decoration: TextDecoration.underline,
                                    decorationColor: accent,
                                  ),
                                ),
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                    // Close button
                    IconButton(
                      icon: Icon(
                        Icons.close,
                        size: 16,
                        color: isDark ? Colors.white54 : Colors.black45,
                      ),
                      onPressed: widget.onClose,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(
                        minWidth: 28,
                        minHeight: 28,
                      ),
                      tooltip: 'Dismiss',
                    ),
                  ],
                ),
              ),
              // ── progress bar (auto-dismiss countdown) ──
              AnimatedBuilder(
                animation: _progress,
                builder: (_, __) => LinearProgressIndicator(
                  value: 1 - _progress.value,
                  minHeight: 3,
                  backgroundColor: accent.withValues(alpha: 0.12),
                  valueColor: AlwaysStoppedAnimation(
                    accent.withValues(alpha: 0.6),
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
