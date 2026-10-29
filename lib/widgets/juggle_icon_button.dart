import 'package:flutter/material.dart';

class JuggleIconButton extends StatefulWidget {
  final Widget icon;
  final VoidCallback? onPressed;
  final double size;
  final String? tooltip;

  const JuggleIconButton({
    super.key,
    required this.icon,
    required this.onPressed,
    this.size = 48,
    this.tooltip,
  });

  @override
  State<JuggleIconButton> createState() => _JuggleIconButtonState();
}

class _JuggleIconButtonState extends State<JuggleIconButton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _rotation;
  late final Animation<double> _scale;

  @override
  void initState() {
    super.initState();

    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 350),
    );

    _rotation = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 0.0, end: -0.18),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -0.18, end: 0.18),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.18, end: -0.10),
        weight: 25,
      ),
      TweenSequenceItem(
        tween: Tween(begin: -0.10, end: 0.0),
        weight: 25,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeInOut,
      ),
    );

    _scale = TweenSequence<double>([
      TweenSequenceItem(
        tween: Tween(begin: 1.0, end: 1.15),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 1.15, end: 0.95),
        weight: 30,
      ),
      TweenSequenceItem(
        tween: Tween(begin: 0.95, end: 1.0),
        weight: 40,
      ),
    ]).animate(
      CurvedAnimation(
        parent: _controller,
        curve: Curves.easeOut,
      ),
    );
  }

  void _handleTap() {
    if (widget.onPressed == null) return;

    _controller.forward(from: 0);
    widget.onPressed!();
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Tooltip(
      message: widget.tooltip ?? '',
      child: GestureDetector(
        behavior: HitTestBehavior.opaque,
        onTap: _handleTap,
        child: SizedBox(
          width: widget.size,
          height: widget.size,
          child: Center(
            child: AnimatedBuilder(
              animation: _controller,
              child: widget.icon,
              builder: (context, child) {
                return Transform.rotate(
                  angle: _rotation.value,
                  child: Transform.scale(
                    scale: _scale.value,
                    child: child,
                  ),
                );
              },
            ),
          ),
        ),
      ),
    );
  }
}
