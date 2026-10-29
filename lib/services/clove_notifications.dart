import 'dart:async';

import 'package:flutter/material.dart';

/// Shared, single-message alert host anchored to Clove's persistent controls.
class CloveNotifications {
  CloveNotifications._();

  static final miniPlayerAnchorKey = GlobalKey(
    debugLabel: 'mini-player-alert-anchor',
  );
  static final navigationAnchorKey = GlobalKey(
    debugLabel: 'navigation-alert-anchor',
  );
  static final ValueNotifier<SnackBar?> current = ValueNotifier<SnackBar?>(
    null,
  );
  static int _revision = 0;
  static Timer? _timer;

  static void show(BuildContext context, SnackBar alert) {
    // Standalone routes and widget tests may not have the shell's anchored
    // controls mounted. Preserve the route's normal messenger in that case.
    if (miniPlayerAnchorKey.currentContext == null &&
        navigationAnchorKey.currentContext == null) {
      ScaffoldMessenger.maybeOf(context)?.showSnackBar(alert);
      return;
    }
    _timer?.cancel();
    final revision = ++_revision;
    current.value = alert;
    _timer = Timer(alert.duration, () {
      if (_revision == revision) current.value = null;
    });
  }
}

/// Draws alerts above the mini-player (or navigation when playback is absent).
class CloveAlertHost extends StatefulWidget {
  const CloveAlertHost({super.key});

  @override
  State<CloveAlertHost> createState() => _CloveAlertHostState();
}

class _CloveAlertHostState extends State<CloveAlertHost> {
  SnackBar? _alert;
  Rect? _anchor;
  bool _showing = false;

  @override
  void initState() {
    super.initState();
    _alert = CloveNotifications.current.value;
    CloveNotifications.current.addListener(_onAlertChanged);
  }

  @override
  void dispose() {
    CloveNotifications.current.removeListener(_onAlertChanged);
    super.dispose();
  }

  void _onAlertChanged() {
    final next = CloveNotifications.current.value;
    setState(() {
      _alert = next;
      _anchor = null;
      _showing = false;
    });
    if (next != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        _measureAnchor();
      });
    }
  }

  void _measureAnchor() {
    if (!mounted || _alert == null) return;
    final miniContext = CloveNotifications.miniPlayerAnchorKey.currentContext;
    final navContext = CloveNotifications.navigationAnchorKey.currentContext;
    final anchorContext = miniContext ?? navContext;
    final hostBox = context.findRenderObject();
    final anchorBox = anchorContext?.findRenderObject();
    if (hostBox is! RenderBox ||
        anchorBox is! RenderBox ||
        !hostBox.hasSize ||
        !anchorBox.hasSize) {
      setState(() => _anchor = null);
      return;
    }
    final topLeft = anchorBox.localToGlobal(Offset.zero, ancestor: hostBox);
    final rect = topLeft & anchorBox.size;
    setState(() => _anchor = rect);
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted || _anchor == null || _alert == null) return;
      setState(() => _showing = true);
    });
  }

  @override
  Widget build(BuildContext context) {
    final alert = _alert;
    final anchor = _anchor;
    if (alert == null || anchor == null) return const SizedBox.expand();

    final theme = Theme.of(context);
    final snackTheme = theme.snackBarTheme;
    final color =
        alert.backgroundColor ??
        snackTheme.backgroundColor ??
        theme.colorScheme.inverseSurface;
    final textStyle =
        (snackTheme.contentTextStyle ?? theme.textTheme.bodyMedium)?.copyWith(
          color: alert.backgroundColor == null
              ? theme.colorScheme.onInverseSurface
              : null,
        );
    final margin = (alert.margin ?? snackTheme.insetPadding ?? EdgeInsets.zero)
        .resolve(Directionality.of(context));
    final padding =
        alert.padding ??
        const EdgeInsets.symmetric(horizontal: 24, vertical: 14);
    final shape =
        alert.shape ??
        snackTheme.shape ??
        const RoundedRectangleBorder(borderRadius: BorderRadius.zero);
    return Positioned(
      left: anchor.left + margin.left,
      right: MediaQuery.sizeOf(context).width - anchor.right + margin.right,
      bottom: MediaQuery.sizeOf(context).height - anchor.top + 8,
      child: IgnorePointer(
        child: AnimatedSlide(
          duration: const Duration(milliseconds: 180),
          curve: Curves.easeOutCubic,
          offset: _showing ? Offset.zero : const Offset(0, 0.2),
          child: AnimatedOpacity(
            duration: const Duration(milliseconds: 140),
            opacity: _showing ? 1 : 0,
            child: Material(
              color: color,
              elevation: alert.elevation ?? snackTheme.elevation ?? 6,
              shape: shape,
              clipBehavior: Clip.antiAlias,
              child: Padding(
                padding: padding,
                child: DefaultTextStyle(
                  style: textStyle ?? const TextStyle(),
                  child: Semantics(liveRegion: true, child: alert.content),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
