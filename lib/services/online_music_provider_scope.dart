import 'package:flutter/widgets.dart';

import 'online_music_provider.dart';

class OnlineMusicProviderScope extends InheritedWidget {
  const OnlineMusicProviderScope({
    required this.provider,
    required super.child,
    super.key,
  });

  final OnlineMusicProvider provider;

  static OnlineMusicProvider of(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<OnlineMusicProviderScope>();
    if (scope == null) throw StateError('OnlineMusicProviderScope is missing.');
    return scope.provider;
  }

  @override
  bool updateShouldNotify(OnlineMusicProviderScope oldWidget) =>
      !identical(provider, oldWidget.provider);
}
