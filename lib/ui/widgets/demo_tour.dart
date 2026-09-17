import 'package:flutter/material.dart';

class TourStep {
  const TourStep({
    required this.title,
    required this.body,
    required this.targetIndex,
    required this.arrowDirection,
  });

  final String title;
  final String body;

  /// Index into the nav destinations this step points at.
  final int targetIndex;

  /// Which way the arrow points, from the callout toward the nav item.
  final AxisDirection arrowDirection;
}

const kTourSteps = <TourStep>[
  TourStep(
    title: 'Dashboard',
    body:
        'See how full each drive is, connect Google Drive, and check the '
        'Jio Gemini Pro Pack offer here.',
    targetIndex: 0,
    arrowDirection: AxisDirection.down,
  ),
  TourStep(
    title: 'Files',
    body:
        'After a scan, tick the checkboxes to pick exactly which files to '
        'back up — each row shows its drive/partition.',
    targetIndex: 1,
    arrowDirection: AxisDirection.down,
  ),
  TourStep(
    title: 'Backup',
    body:
        'Start the upload, watch live progress, and see where every '
        'file is headed in Drive.',
    targetIndex: 2,
    arrowDirection: AxisDirection.down,
  ),
  TourStep(
    title: 'History',
    body:
        'A permanent log of everything uploaded, plus a live look at '
        'what is actually sitting in your Drive right now.',
    targetIndex: 3,
    arrowDirection: AxisDirection.down,
  ),
  TourStep(
    title: 'Settings',
    body:
        'Switch between Auto and Manual mode, and fine-tune what gets '
        'backed up automatically.',
    targetIndex: 4,
    arrowDirection: AxisDirection.down,
  ),
];

/// A short arrow-and-text walkthrough of the five tabs, shown on top of the
/// app. Runs every time the app starts — there is no "seen it" flag — so a
/// prominent Skip is always one tap away.
class DemoTour extends StatefulWidget {
  const DemoTour({
    super.key,
    required this.wide,
    required this.onStepChanged,
    required this.onFinished,
  });

  /// True when the destinations render in a side [NavigationRail] rather than
  /// a bottom [NavigationBar] — changes where the callout is anchored.
  final bool wide;

  /// Called as the tour advances so the page behind it can preview the
  /// highlighted tab.
  final ValueChanged<int> onStepChanged;
  final VoidCallback onFinished;

  @override
  State<DemoTour> createState() => _DemoTourState();
}

class _DemoTourState extends State<DemoTour> {
  int _step = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      widget.onStepChanged(kTourSteps[_step].targetIndex);
    });
  }

  void _go(int next) {
    if (next >= kTourSteps.length) {
      widget.onFinished();
      return;
    }
    setState(() => _step = next);
    widget.onStepChanged(kTourSteps[next].targetIndex);
  }

  @override
  Widget build(BuildContext context) {
    final step = kTourSteps[_step];
    final size = MediaQuery.sizeOf(context);
    final destinationCount = kTourSteps.length;

    // Ballpark anchor for the arrow: evenly spaced along the bottom bar, or
    // evenly spaced down the rail. Good enough for a five-item nav without
    // needing GlobalKeys on every destination.
    final Offset anchor = widget.wide
        ? Offset(56, 96.0 + step.targetIndex * 72)
        : Offset(
            (size.width / destinationCount) * (step.targetIndex + 0.5),
            size.height - 78,
          );

    return Positioned.fill(
      child: Stack(
        children: [
          // Dim the app behind the tour without hiding it — the highlighted
          // tab is already showing through via onStepChanged.
          ModalBarrier(
            dismissible: false,
            color: Colors.black.withValues(alpha: 0.45),
          ),
          _Arrow(anchor: anchor, pointingDown: !widget.wide),
          _Callout(
            step: step,
            index: _step,
            total: kTourSteps.length,
            wide: widget.wide,
            anchor: anchor,
            onSkip: widget.onFinished,
            onNext: () => _go(_step + 1),
            onBack: _step == 0 ? null : () => _go(_step - 1),
          ),
        ],
      ),
    );
  }
}

class _Arrow extends StatelessWidget {
  const _Arrow({required this.anchor, required this.pointingDown});
  final Offset anchor;
  final bool pointingDown;

  @override
  Widget build(BuildContext context) {
    const size = 36.0;
    return AnimatedPositioned(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      left: anchor.dx - size / 2,
      top: pointingDown ? anchor.dy - size - 8 : anchor.dy + 8,
      child: TweenAnimationBuilder<double>(
        tween: Tween(begin: 0, end: 1),
        duration: const Duration(milliseconds: 900),
        curve: Curves.easeInOut,
        builder: (context, t, child) => Transform.translate(
          offset: Offset(
            0,
            (pointingDown ? 1 : -1) * 6 * (0.5 - (t - 0.5).abs()) * 2,
          ),
          child: child,
        ),
        child: Icon(
          pointingDown
              ? Icons.arrow_downward_rounded
              : Icons.arrow_back_rounded,
          size: size,
          color: Colors.white,
          shadows: const [Shadow(blurRadius: 8, color: Colors.black54)],
        ),
      ),
    );
  }
}

class _Callout extends StatelessWidget {
  const _Callout({
    required this.step,
    required this.index,
    required this.total,
    required this.wide,
    required this.anchor,
    required this.onSkip,
    required this.onNext,
    required this.onBack,
  });

  final TourStep step;
  final int index;
  final int total;
  final bool wide;
  final Offset anchor;
  final VoidCallback onSkip;
  final VoidCallback onNext;
  final VoidCallback? onBack;

  @override
  Widget build(BuildContext context) {
    final size = MediaQuery.sizeOf(context);
    const cardWidth = 300.0;
    final left = wide
        ? anchor.dx + 44
        : (anchor.dx - cardWidth / 2).clamp(
            16.0,
            size.width - cardWidth - 16.0,
          );
    final top = wide ? anchor.dy - 20 : anchor.dy - 210;

    return AnimatedPositioned(
      duration: const Duration(milliseconds: 350),
      curve: Curves.easeOutCubic,
      left: left,
      top: top,
      width: cardWidth,
      child: Material(
        elevation: 8,
        borderRadius: BorderRadius.circular(16),
        color: Theme.of(context).colorScheme.surfaceContainerHighest,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                children: [
                  Expanded(
                    child: Text(
                      step.title,
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  Text(
                    '${index + 1}/$total',
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ],
              ),
              const SizedBox(height: 8),
              Text(step.body, style: Theme.of(context).textTheme.bodyMedium),
              const SizedBox(height: 14),
              Row(
                children: [
                  TextButton(onPressed: onSkip, child: const Text('Skip')),
                  const Spacer(),
                  if (onBack != null)
                    TextButton(onPressed: onBack, child: const Text('Back')),
                  FilledButton(
                    onPressed: onNext,
                    child: Text(index + 1 == total ? 'Got it' : 'Next'),
                  ),
                ],
              ),
            ],
          ),
        ),
      ),
    );
  }
}
