import 'package:flutter/material.dart';

import '../services/clove_notifications.dart';

const _queueMint = Color(0xFF1DE9B6);

/// Reveals a queue background progressively as the row is swiped.
class QueueSwipe extends StatefulWidget {
  const QueueSwipe({
    super.key,
    required this.onQueue,
    required this.successMessage,
    required this.child,
    this.onSwipeLeft,
    this.leftSuccessMessage = 'Added to Liked Songs',
    this.leftFailureMessage = 'Could not add to Liked Songs.',
  });

  final Future<bool> Function() onQueue;
  final String successMessage;
  final Widget child;
  final Future<bool> Function()? onSwipeLeft;
  final String leftSuccessMessage;
  final String leftFailureMessage;

  @override
  State<QueueSwipe> createState() => _QueueSwipeState();
}

class _QueueSwipeState extends State<QueueSwipe> {
  static const _threshold = 76.0;
  static const _maxOffset = 112.0;
  static const _settleDuration = Duration(milliseconds: 190);

  double _offset = 0;
  bool _dragging = false;
  bool _queueing = false;

  Future<void> _finishDrag(DragEndDetails details) async {
    if (!_dragging || _queueing) return;

    final shouldQueue =
        _offset >= _threshold ||
        (_offset >= 28 && details.velocity.pixelsPerSecond.dx >= 750);
    final shouldLike =
        widget.onSwipeLeft != null &&
        (_offset <= -_threshold ||
            (_offset <= -28 && details.velocity.pixelsPerSecond.dx <= -750));

    _queueing = shouldQueue || shouldLike;

    setState(() {
      _dragging = false;
      _offset = 0;
    });

    if (!shouldQueue && !shouldLike) return;

    try {
      final completed = shouldLike
          ? await widget.onSwipeLeft!()
          : await widget.onQueue();

      if (!mounted || !completed) return;

      CloveNotifications.show(
        context,
        SnackBar(
          content: Text(
            shouldLike ? widget.leftSuccessMessage : widget.successMessage,
          ),
          duration: const Duration(milliseconds: 1100),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(10),
          ),
        ),
      );
    } catch (_) {
      if (!mounted) return;

      CloveNotifications.show(
        context,
        SnackBar(
          content: Text(
            shouldLike ? widget.leftFailureMessage : 'Could not add to queue.',
          ),
          duration: Duration(milliseconds: 1400),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _queueing = false);
      } else {
        _queueing = false;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    // Background grows with the swipe distance.
    final revealWidth = _offset.abs().clamp(0.0, _maxOffset);
    final revealProgress = (revealWidth / _threshold).clamp(0.0, 1.0);

    return GestureDetector(
      behavior: HitTestBehavior.translucent,
      onHorizontalDragStart: _queueing
          ? null
          : (_) {
              _dragging = true;
            },
      onHorizontalDragUpdate: _queueing
          ? null
          : (details) {
              setState(() {
                final nextOffset = _offset + details.delta.dx;
                _offset = widget.onSwipeLeft == null
                    ? nextOffset.clamp(0.0, _maxOffset)
                    : nextOffset.clamp(-_maxOffset, _maxOffset);
              });
            },
      onHorizontalDragEnd: _finishDrag,
      onHorizontalDragCancel: () {
        if (!_dragging) return;

        setState(() {
          _dragging = false;
          _offset = 0;
        });
      },
      child: ClipRect(
        child: Stack(
          alignment: Alignment.centerLeft,
          children: [
            // Green background is revealed progressively.
            Positioned.fill(
              child: Align(
                alignment: _offset < 0
                    ? Alignment.centerRight
                    : Alignment.centerLeft,
                child: SizedBox(
                  width: _dragging ? revealWidth : 0,
                  child: ColoredBox(
                    color: _offset < 0 ? _queueMint : _queueMint,
                    child: Center(
                      child: Opacity(
                        opacity: _dragging ? revealProgress : 0,
                        child: Transform.scale(
                          scale: 0.65 + (0.35 * revealProgress),
                          child: Icon(
                            _offset < 0
                                ? Icons.favorite_rounded
                                : Icons.playlist_add_rounded,
                            color: Colors.black,
                            size: 32,
                          ),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
            ),

            // Original song or playlist row slides over the background.
            AnimatedContainer(
              duration: _dragging ? Duration.zero : _settleDuration,
              curve: Curves.easeOutCubic,
              transform: Matrix4.translationValues(_offset, 0, 0),
              child: widget.child,
            ),
          ],
        ),
      ),
    );
  }
}
