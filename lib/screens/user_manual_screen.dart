import 'package:clove/widgets/juggle_icon_button.dart';
import 'package:flutter/material.dart';

const _obsidian = Color(0xFF0B0B0B);
const _mint = Color(0xFF1DE9B6);
const _secondary = Color(0xFFB7B5BE);

class UserManualScreen extends StatelessWidget {
  const UserManualScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _obsidian,
      appBar: AppBar(
  surfaceTintColor: Colors.transparent,
  scrolledUnderElevation: 0,
  elevation: 0,
  backgroundColor: _obsidian,
  foregroundColor: Colors.white,
  centerTitle: true,

  leading: JuggleIconButton(
    tooltip: 'Go back',
    onPressed: () => Navigator.of(context).maybePop(),
    size: 48,
    icon: const Icon(
      Icons.arrow_back_ios_new_rounded,
      color: Colors.white,
      size: 22,
    ),
  ),

  title: const Text('User Manual'),
),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(22, 12, 22, 32),
        children: const [
          _ManualSection(
            title: 'Getting started',
            body: 'Use the bottom navigation to move between Home, Your Library, and Luna. The search control opens music search. Tap a song to start playback.',
          ),
          _ManualSection(
            title: 'Playback and queue',
            body: 'Use Play/Pause, Previous, and Next in the mini-player or Now Playing screen. Drag the progress slider to seek. Shuffle and repeat are available in Now Playing. Open Up Next from the queue control to see upcoming tracks; remove an upcoming entry there without removing it from a playlist. Swipe a song right to append it to the queue. Swipe a playlist right to append its tracks in order.',
          ),
          _ManualSection(
            title: 'Local Music',
            body: 'Open Local Music from Your Library to scan audio already stored on this device. Allow Clove audio access when Android asks. Pull down to refresh the scan. If access was changed in Android Settings, return to Clove and refresh. Local files that were moved or deleted may no longer play.',
          ),
          _ManualSection(
            title: 'Playlists and Liked Songs',
            body: 'Use the plus action in Your Library to create a playlist. Open a playlist to play or shuffle its tracks, edit its name or cover, pin it, or manage its songs. Long-press a playlist entry for edit and delete actions. Use the save action by the mini-player to add the current song to Liked Songs or one or more playlists. Liked Songs is managed as its own collection.',
          ),
          _ManualSection(
            title: 'Search, albums, and artists',
            body: 'Search filters the available music results. In Your Library, Albums and Artists group the scanned local tracks; select a group to view its songs.',
          ),
          _ManualSection(
            title: 'Background playback',
            body: 'Playback can continue when Clove is in the background. Use Android’s media notification, lock-screen controls, or compatible headset controls for playback commands. Dismissing Clove from Recents stops its playback service.',
          ),
          _ManualSection(
            title: 'Troubleshooting',
            body: 'If Local Music is empty, check Android app permissions and run a scan again. If a song is missing, confirm that it is stored locally and recognized by Android’s media library. If playback cannot open a track, it may have been moved, removed, or become unavailable.',
          ),
          _ManualSection(
            title: 'Luna',
            body: 'The Luna tab is present in this build, but voice-assistant controls are not currently available.',
          ),
        ],
      ),
    );
  }
}

class _ManualSection extends StatelessWidget {
  const _ManualSection({required this.title, required this.body});

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            title,
            style: const TextStyle(
              color: _mint,
              fontSize: 17,
              fontWeight: FontWeight.w700,
            ),
          ),
          const SizedBox(height: 8),
          Text(
            body,
            style: const TextStyle(
              color: _secondary,
              fontSize: 14,
              height: 1.5,
            ),
          ),
        ],
      ),
    );
  }
}
