import 'dart:math' as math;

import 'package:flutter/material.dart';

import '../theme/app_theme.dart';

/// Dark card with optional border, matching the brand guide.
class BrandCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;
  final Color? color;
  final VoidCallback? onTap;

  const BrandCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(16),
    this.color,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final borderRadius = BorderRadius.circular(AppTheme.cardRadius);
    final decoration = BoxDecoration(
      color: color ?? AppTheme.card,
      borderRadius: borderRadius,
      border: Border.all(color: AppTheme.divider),
    );

    if (onTap != null) {
      return Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onTap,
          borderRadius: borderRadius,
          child: Ink(
            decoration: decoration,
            child: Padding(padding: padding, child: child),
          ),
        ),
      );
    }

    return Container(
      padding: padding,
      decoration: decoration,
      child: child,
    );
  }
}

/// Circular progress ring with the primary → success gradient.
class GradientProgressRing extends StatelessWidget {
  final double progress;
  final double size;
  final double strokeWidth;
  final Widget? child;
  final bool complete;

  const GradientProgressRing({
    super.key,
    required this.progress,
    this.size = 140,
    this.strokeWidth = 10,
    this.child,
    this.complete = false,
  });

  @override
  Widget build(BuildContext context) {
    final clamped = progress.clamp(0.0, 1.0);
    return SizedBox(
      width: size,
      height: size,
      child: CustomPaint(
        painter: _RingPainter(
          progress: clamped,
          strokeWidth: strokeWidth,
          complete: complete || clamped >= 1.0,
        ),
        child: child != null
            ? Center(child: child)
            : null,
      ),
    );
  }
}

class _RingPainter extends CustomPainter {
  final double progress;
  final double strokeWidth;
  final bool complete;

  _RingPainter({
    required this.progress,
    required this.strokeWidth,
    required this.complete,
  });

  @override
  void paint(Canvas canvas, Size size) {
    final center = Offset(size.width / 2, size.height / 2);
    final radius = (size.width - strokeWidth) / 2;
    final rect = Rect.fromCircle(center: center, radius: radius);

    final track = Paint()
      ..color = AppTheme.cardElevated
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;
    canvas.drawCircle(center, radius, track);

    if (progress <= 0) return;

    final gradient = complete ? AppTheme.successGradient : AppTheme.primaryGradient;
    final arc = Paint()
      ..shader = gradient.createShader(rect)
      ..style = PaintingStyle.stroke
      ..strokeWidth = strokeWidth
      ..strokeCap = StrokeCap.round;

    canvas.drawArc(
      rect,
      -math.pi / 2,
      2 * math.pi * progress,
      false,
      arc,
    );
  }

  @override
  bool shouldRepaint(covariant _RingPainter old) =>
      old.progress != progress || old.complete != complete;
}

/// Primary CTA with the blue → teal gradient.
class GradientButton extends StatelessWidget {
  final VoidCallback? onPressed;
  final Widget child;
  final EdgeInsetsGeometry padding;
  final bool expand;

  const GradientButton({
    super.key,
    required this.onPressed,
    required this.child,
    this.padding = const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
    this.expand = true,
  });

  @override
  Widget build(BuildContext context) {
    final enabled = onPressed != null;
    final button = DecoratedBox(
      decoration: BoxDecoration(
        gradient: enabled ? AppTheme.primaryGradient : null,
        color: enabled ? null : AppTheme.cardElevated,
        borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: onPressed,
          borderRadius: BorderRadius.circular(AppTheme.buttonRadius),
          child: Padding(
            padding: padding,
            child: DefaultTextStyle(
              style: TextStyle(
                color: enabled ? AppTheme.onPrimary : AppTheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
                fontSize: 16,
                fontFamily: AppTheme.fontFamily,
              ),
              textAlign: TextAlign.center,
              child: IconTheme(
                data: IconThemeData(
                  color: enabled ? AppTheme.onPrimary : AppTheme.onSurfaceVariant,
                  size: 20,
                ),
                child: child,
              ),
            ),
          ),
        ),
      ),
    );

    if (expand) {
      return SizedBox(width: double.infinity, child: button);
    }
    return button;
  }
}

/// App wordmark: "Anki" in white, "Block" in primary blue.
class AnkiBlockWordmark extends StatelessWidget {
  final double fontSize;

  const AnkiBlockWordmark({super.key, this.fontSize = 28});

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme.headlineMedium?.copyWith(
          fontSize: fontSize,
          fontWeight: FontWeight.w700,
        );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: 'Anki', style: base),
          TextSpan(
            text: 'Block',
            style: base?.copyWith(color: AppTheme.primary),
          ),
        ],
      ),
    );
  }
}

/// Headline with one accent-colored word.
class AccentHeadline extends StatelessWidget {
  final String before;
  final String accent;
  final String after;
  final TextAlign textAlign;
  final TextStyle? style;

  const AccentHeadline({
    super.key,
    required this.before,
    required this.accent,
    this.after = '',
    this.textAlign = TextAlign.center,
    this.style,
  });

  @override
  Widget build(BuildContext context) {
    final base = style ??
        Theme.of(context).textTheme.headlineMedium?.copyWith(
              fontWeight: FontWeight.w700,
              height: 1.25,
            );
    return Text.rich(
      TextSpan(
        children: [
          TextSpan(text: before, style: base),
          TextSpan(
            text: accent,
            style: base?.copyWith(color: AppTheme.accent),
          ),
          if (after.isNotEmpty) TextSpan(text: after, style: base),
        ],
      ),
      textAlign: textAlign,
    );
  }
}

/// Small pill badge, e.g. "Requires AnkiDroid".
class BrandBadge extends StatelessWidget {
  final String label;
  final IconData? icon;
  final Color? color;

  const BrandBadge({
    super.key,
    required this.label,
    this.icon,
    this.color,
  });

  @override
  Widget build(BuildContext context) {
    final c = color ?? AppTheme.accent;
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: c.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(color: c.withValues(alpha: 0.35)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: c),
            const SizedBox(width: 6),
          ],
          Text(
            label,
            style: Theme.of(context).textTheme.labelMedium?.copyWith(
                  color: c,
                  fontWeight: FontWeight.w600,
                ),
          ),
        ],
      ),
    );
  }
}
