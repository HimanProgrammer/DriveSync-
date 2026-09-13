import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

/// The DriveSync mark: a cloud with a sync glyph cut into it. Reused as the
/// app bar icon (static) and, animated, as the launch splash.
class DriveSyncLogo extends StatelessWidget {
  const DriveSyncLogo({super.key, this.size = 32});

  final double size;

  @override
  Widget build(BuildContext context) => SvgPicture.asset(
        'assets/branding/logo.svg',
        width: size,
        height: size,
      );
}

const _kDriveSyncGradient = [Color(0xFF38BDF8), Color(0xFF1D4ED8)];

/// A slow continuous spin on the sync glyph, a gentle breathing scale on the
/// cloud, and a soft pulsing glow behind it all — awake, not busy. Used while
/// the app boots and as a reusable "working" indicator.
class AnimatedDriveSyncLogo extends StatefulWidget {
  const AnimatedDriveSyncLogo({super.key, this.size = 140});

  final double size;

  @override
  State<AnimatedDriveSyncLogo> createState() => _AnimatedDriveSyncLogoState();
}

class _AnimatedDriveSyncLogoState extends State<AnimatedDriveSyncLogo>
    with TickerProviderStateMixin {
  late final AnimationController _spin =
      AnimationController(vsync: this, duration: const Duration(milliseconds: 2400))
        ..repeat();
  late final AnimationController _breathe = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 1600),
  )..repeat(reverse: true);

  @override
  void dispose() {
    _spin.dispose();
    _breathe.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: Listenable.merge([_spin, _breathe]),
      builder: (context, _) {
        final scale = 1.0 + (_breathe.value * 0.045);
        return SizedBox(
          width: widget.size * 1.3,
          height: widget.size * 1.3,
          child: Stack(
            alignment: Alignment.center,
            children: [
              // Soft glow that pulses with the breathing scale.
              Opacity(
                opacity: 0.25 + _breathe.value * 0.25,
                child: Container(
                  width: widget.size * 1.25,
                  height: widget.size * 1.25,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    gradient: RadialGradient(
                      colors: [
                        scheme.primary.withValues(alpha: 0.35),
                        scheme.primary.withValues(alpha: 0),
                      ],
                    ),
                  ),
                ),
              ),
              Transform.scale(
                scale: scale,
                child: SvgPicture.asset(
                  'assets/branding/logo_cloud_only.svg',
                  width: widget.size,
                  height: widget.size,
                ),
              ),
              // The sync glyph spins independently on top of the still cloud,
              // so the mark reads as "actively syncing" rather than static.
              Transform.rotate(
                angle: _spin.value * 6.28318,
                child: ShaderMask(
                  shaderCallback: (bounds) => const LinearGradient(
                    colors: _kDriveSyncGradient,
                  ).createShader(bounds),
                  child: Icon(Icons.sync, size: widget.size * 0.34, color: Colors.white),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
