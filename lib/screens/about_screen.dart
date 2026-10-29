import 'package:clove/main.dart';
import 'package:clove/widgets/juggle_icon_button.dart';
import 'package:flutter/material.dart';
import 'package:flutter_svg/flutter_svg.dart';

import '../services/clove_notifications.dart';

import 'package:package_info_plus/package_info_plus.dart';
import 'package:url_launcher/url_launcher.dart';

const _obsidian = Color(0xFF0B0B0B);
const _mint = Color(0xFF1DE9B6);
const _secondary = Color(0xFFB7B5BE);

class AboutScreen extends StatelessWidget {
  const AboutScreen({super.key});

  static final Uri _projectUri = Uri.parse('https://github.com/shvnix/clove');

  Future<void> _openProject(BuildContext context) async {
    try {
      final opened = await launchUrl(
        _projectUri,
        mode: LaunchMode.externalApplication,
      );

      if (!opened && context.mounted) {
        CloveNotifications.show(
          context,
          const SnackBar(
            content: Text('Could not open the Clove project link.'),
          ),
        );
      }
    } catch (error) {
      debugPrint('Could not open Clove project link: $error');

      if (!context.mounted) return;

      CloveNotifications.show(
        context,
        const SnackBar(content: Text('Could not open the Clove project link.')),
      );
    }
  }

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
        title: const Text('About Clove'),
      ),
      body: Align(
        alignment: Alignment.topCenter,
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(28, 0, 28, 48),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              // Clove logo at the top
              Image.asset(
                'assets/icon/icon.png',
                width: 150,
                height: 150,
                fit: BoxFit.contain,
                alignment: Alignment.topCenter,
              ),

              const SizedBox(height: 8),

              const Text(
                'CLOVE',
                style: TextStyle(
                  color: _mint,
                  fontSize: 25,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 5,
                ),
              ),

              const SizedBox(height: 5),

              const Text(
                'by SHVNIX',
                style: TextStyle(color: _secondary, fontSize: 14),
              ),

              const SizedBox(height: 24),

              const Text(
                'Your music. Your device. Your control.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 19,
                  fontWeight: FontWeight.w800,
                  height: 1.4,
                ),
              ),

              const SizedBox(height: 12),

              const Text(
                'Clove is an offline-first music player designed '
                'to give you privacy, independence, and control '
                'over your listening experience. Your music library '
                'and app data stay on your device.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 14,
                  height: 1.6,
                ),
              ),

              const SizedBox(height: 22),

              const Text(
                'YOUR DATA, YOUR RESPONSIBILITY',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Clove does not keep a cloud backup of your local '
                'app data. Clearing app data or uninstalling Clove '
                'may permanently erase your playlists, preferences, '
                'and other locally stored information. Back up '
                'anything important before removing the app.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),

              const SizedBox(height: 22),

              const Text(
                'LOVE CLOVE?',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 13,
                  fontWeight: FontWeight.w800,
                  letterSpacing: 1.2,
                ),
              ),

              const SizedBox(height: 8),

              const Text(
                'Visit our GitHub repository for the latest '
                'releases, updates, and improvements. Enjoying '
                'Clove? Leave a star on GitHub to support the project '
                'and help others discover it.',
                textAlign: TextAlign.center,
                style: TextStyle(
                  color: Colors.white38,
                  fontSize: 13,
                  height: 1.6,
                ),
              ),

              const SizedBox(height: 18),

              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  return Text(
                    snapshot.hasData
                        ? 'Version ${snapshot.data!.version} '
                              '(${snapshot.data!.buildNumber})'
                        : 'Version',
                    style: const TextStyle(color: _secondary, fontSize: 13),
                  );
                },
              ),

              const SizedBox(height: 20),

              TextButton.icon(
                onPressed: () => _openProject(context),
                icon: SvgPicture.asset(
                  'assets/icon/github.svg',
                  width: 28,
                  height: 28,
                  colorFilter: const ColorFilter.mode(_mint, BlendMode.srcIn),
                ),
                label: const Text(
                  'GitHub link',
                  style: TextStyle(
                    color: cloveMint,
                    fontSize: 24,
                    fontWeight: FontWeight.w800,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
