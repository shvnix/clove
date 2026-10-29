import 'package:flutter/material.dart';

class MarqueeText extends StatefulWidget {
  const MarqueeText({
    super.key,
    required this.text,
    required this.style,
    this.gap = 36,
    this.pixelsPerSecond = 28,
  });

  final String text;
  final TextStyle style;
  final double gap;
  final double pixelsPerSecond;

  @override
  State<MarqueeText> createState() => _MarqueeTextState();
}

class _MarqueeTextState extends State<MarqueeText>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;

  double? _configuredDistance;
  Duration? _configuredDuration;
  bool? _configuredOverflow;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(seconds: 10),
    );
  }

  @override
  void didUpdateWidget(covariant MarqueeText oldWidget) {
    super.didUpdateWidget(oldWidget);

    if (oldWidget.text != widget.text ||
        oldWidget.style != widget.style ||
        oldWidget.gap != widget.gap ||
        oldWidget.pixelsPerSecond != widget.pixelsPerSecond) {
      _controller.stop();
      _controller.value = 0;

      _configuredDistance = null;
      _configuredDuration = null;
      _configuredOverflow = null;
    }
  }

  void _configure({required bool overflow, double distance = 0}) {
    final speed = widget.pixelsPerSecond.clamp(1.0, 200.0).toDouble();

    final duration = Duration(
      microseconds: (distance / speed * Duration.microsecondsPerSecond)
          .round()
          .clamp(1, 86400000000),
    );

    if (_configuredOverflow == overflow &&
        (!overflow ||
            (_configuredDistance == distance &&
                _configuredDuration == duration))) {
      return;
    }

    _configuredOverflow = overflow;
    _configuredDistance = overflow ? distance : null;
    _configuredDuration = overflow ? duration : null;

    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;

      if (!overflow) {
        _controller.stop();
        _controller.value = 0;
        return;
      }

      _controller.duration = duration;
      _controller.repeat();
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final viewportWidth = constraints.maxWidth;

        // A marquee requires a finite viewport.
        if (!viewportWidth.isFinite || viewportWidth <= 0) {
          _configure(overflow: false);

          return Text(
            widget.text,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.ellipsis,
            style: widget.style,
          );
        }

        // Measure the complete text using the current text style
        // and the user's text scaling settings.
        final painter = TextPainter(
          text: TextSpan(text: widget.text, style: widget.style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout();

        final textWidth = painter.width;
        final textHeight = painter.height;

        // Keep short titles stationary.
        final overflow = textWidth > viewportWidth;

        if (!overflow) {
          _configure(overflow: false);

          return SizedBox(
            width: viewportWidth,
            height: textHeight,
            child: Align(
              alignment: Alignment.centerLeft,
              child: Text(
                widget.text,
                maxLines: 1,
                softWrap: false,
                overflow: TextOverflow.clip,
                style: widget.style,
              ),
            ),
          );
        }

        // Responsive spacing and scrolling distance.
        final gap = widget.gap.clamp(12.0, 60.0).toDouble();
        final distance = textWidth + gap;

        _configure(overflow: true, distance: distance);

        return SizedBox(
          width: viewportWidth,
          height: textHeight,
          child: ClipRect(
            child: ShaderMask(
              blendMode: BlendMode.dstIn,
              shaderCallback: (bounds) {
                return const LinearGradient(
                  begin: Alignment.centerLeft,
                  end: Alignment.centerRight,
                  colors: [
                    Colors.transparent,
                    Colors.white,
                    Colors.white,
                    Colors.transparent,
                  ],
                  stops: [0.0, 0.035, 0.965, 1.0],
                ).createShader(bounds);
              },
              child: OverflowBox(
                alignment: Alignment.centerLeft,
                minWidth: 0,
                maxWidth: double.infinity,
                child: AnimatedBuilder(
                  animation: _controller,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Text(
                        widget.text,
                        maxLines: 1,
                        softWrap: false,
                        style: widget.style,
                      ),
                      SizedBox(width: gap),
                      Text(
                        widget.text,
                        maxLines: 1,
                        softWrap: false,
                        style: widget.style,
                      ),
                    ],
                  ),
                  builder: (context, child) {
                    final offset = _controller.value * distance;

                    return Transform.translate(
                      offset: Offset(-offset, 0),
                      child: child,
                    );
                  },
                ),
              ),
            ),
          ),
        );
      },
    );
  }
}
