import 'online_music_provider.dart';
import 'youtube_music_provider.dart';

class OnlineMusicProviderRegistry {
  OnlineMusicProviderRegistry({required this.provider});

  final OnlineMusicProvider provider;

  factory OnlineMusicProviderRegistry.forCurrentBuild() =>
      OnlineMusicProviderRegistry(provider: YoutubeMusicProvider());
}
