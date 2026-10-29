import 'package:flutter/material.dart';

import '../services/clove_notifications.dart';

import 'package:flutter_svg/flutter_svg.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:package_info_plus/package_info_plus.dart';

import 'about_screen.dart';
import 'user_manual_screen.dart';

const Color _profileBackground = Color(0xFF181A19);
const Color _profileCard = Color(0xFF2A2A2A);
const Color _cloveMint = Color(0xFF1DE9B6);

class ProfileScreen extends StatefulWidget {
  const ProfileScreen({
    super.key,
    required this.username,
    required this.onSaveName,
    required this.onDeleteAccount,
    this.onOpenManual,
    this.onOpenAbout,
    this.onClose,
    this.onRecents,
    this.onUpdates,
    this.onSettings,
  });

  final String username;
  final Future<void> Function(String name) onSaveName;
  final Future<void> Function() onDeleteAccount;
  final Future<void> Function()? onOpenManual;
  final Future<void> Function()? onOpenAbout;
  final VoidCallback? onClose;
  final VoidCallback? onRecents;
  final VoidCallback? onUpdates;
  final VoidCallback? onSettings;

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  bool _showEditName = false;
  bool _showDeleteAccount = false;

  @override
  Widget build(BuildContext context) {
    final name = widget.username.trim().isEmpty
        ? 'User'
        : widget.username.trim();

    final initial = name[0].toUpperCase();
    final screenWidth = MediaQuery.sizeOf(context).width;

    final panelWidth = screenWidth < 600
        ? screenWidth * 0.88
        : screenWidth < 1000
        ? 360.0
        : 400.0;

    // Continue with the existing build method here.

    return Theme(
      data: Theme.of(context).copyWith(
        splashFactory: NoSplash.splashFactory,
        splashColor: Colors.transparent,
        highlightColor: Colors.transparent,
        hoverColor: Colors.transparent,
      ),
      child: Material(
        color: Colors.transparent,
        child: Stack(
          children: [
            // Transparent area outside the drawer.
            Positioned.fill(
              child: GestureDetector(
                onTap: widget.onClose,
                child: Container(color: Colors.transparent),
              ),
            ),

            // Left-side profile drawer.
            Align(
              alignment: Alignment.centerLeft,
              child: SizedBox(
                width: panelWidth,
                height: double.infinity,
                child: Material(
                  color: _profileBackground,
                  elevation: 18,
                  child: SafeArea(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Container(
                          margin: const EdgeInsets.fromLTRB(14, 16, 14, 12),
                          decoration: BoxDecoration(
                            color: _profileCard,
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Material(
                            type: MaterialType.transparency,
                            child: Column(
                              children: [
                                ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                    vertical: 8,
                                  ),
                                  leading: CircleAvatar(
                                    radius: 30,
                                    backgroundColor: _cloveMint,
                                    child: Text(
                                      initial,
                                      style: const TextStyle(
                                        color: Colors.black,
                                        fontSize: 36,
                                        fontWeight: FontWeight.w900,
                                      ),
                                    ),
                                  ),
                                  title: Text(
                                    name,
                                    maxLines: 1,
                                    overflow: TextOverflow.ellipsis,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 20,
                                      fontWeight: FontWeight.w800,
                                    ),
                                  ),
                                  subtitle: const Padding(
                                    padding: EdgeInsets.only(top: 6),
                                    child: Text(
                                      'Edit name',
                                      style: TextStyle(
                                        color: Colors.white60,
                                        fontSize: 14,
                                      ),
                                    ),
                                  ),
                                  onTap: () =>
                                      setState(() => _showEditName = true),
                                ),
                                const Divider(height: 1, color: Colors.white24),
                                ListTile(
                                  contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 14,
                                  ),
                                  leading: const Icon(
                                    Icons.delete_forever_outlined,
                                    color: Colors.white,
                                    size: 28,
                                  ),
                                  title: const Text(
                                    'Delete account',
                                    style: TextStyle(
                                      color: Colors.white,
                                      fontSize: 17,
                                    ),
                                  ),
                                  onTap: () =>
                                      setState(() => _showDeleteAccount = true),
                                ),
                              ],
                            ),
                          ),
                        ),

                        _menuItem(
                          leading: SvgPicture.asset(
                            'assets/icon/usermanual.svg',
                            width: 28,
                            height: 28,
                            colorFilter: const ColorFilter.mode(
                              Colors.white,
                              BlendMode.srcIn,
                            ),
                          ),
                          title: 'User Manual',
                          onTap: widget.onOpenManual == null
                              ? () =>
                                    _openPage(context, const UserManualScreen())
                              : () => widget.onOpenManual!(),
                        ),

                        _menuItem(
                          leading: SvgPicture.asset(
                            'assets/icon/aboutus.svg',
                            width: 28,
                            height: 28,
                            colorFilter: const ColorFilter.mode(
                              Colors.white,
                              BlendMode.srcIn,
                            ),
                          ),
                          title: 'About US',
                          onTap: widget.onOpenAbout == null
                              ? () => _openPage(context, const AboutScreen())
                              : () => widget.onOpenAbout!(),
                        ),

                        _menuItem(
                          leading: SvgPicture.asset(
                            'assets/icon/github.svg',
                            width: 28,
                            height: 28,
                            colorFilter: const ColorFilter.mode(
                              Colors.white,
                              BlendMode.srcIn,
                            ),
                          ),
                          title: 'GitHub link',
                          onTap: _openGithub,
                        ),

                        const Spacer(),

                        FutureBuilder<PackageInfo>(
                          future: PackageInfo.fromPlatform(),
                          builder: (context, snapshot) {
                            final version = snapshot.data?.version;

                            return Padding(
                              padding: const EdgeInsets.only(
                                bottom: 16,
                                top: 8,
                              ),
                              child: Column(
                                children: [
                                  Text(
                                    version == null ? 'Version' : 'V$version',
                                    textAlign: TextAlign.center,
                                    style: const TextStyle(
                                      color: Colors.white70,
                                      fontSize: 28,
                                      fontWeight: FontWeight.w500,
                                      letterSpacing: 2.5,
                                    ),
                                  ),
                                  const Text(
                                    'by',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 10,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                  const Text(
                                    'SHVNIX',
                                    textAlign: TextAlign.center,
                                    style: TextStyle(
                                      color: Colors.white54,
                                      fontSize: 14,
                                      fontWeight: FontWeight.w400,
                                      letterSpacing: 1.2,
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ),
              ),
            ),
            if (_showEditName || _showDeleteAccount)
              Positioned.fill(
                child: Stack(
                  children: [
                    // 1. Dark background: tapping outside closes the popup.
                    Positioned.fill(
                      child: GestureDetector(
                        behavior: HitTestBehavior.opaque,
                        onTap: () {
                          setState(() {
                            _showEditName = false;
                            _showDeleteAccount = false;
                          });
                        },
                        child: Container(color: Colors.black54),
                      ),
                    ),

                    // 2. Popup stays above the background.
                    Center(
                      child: _showEditName
                          ? _EditNameDialog(
                              currentName: widget.username,
                              onSave: widget.onSaveName,
                              onCancel: () {
                                setState(() {
                                  _showEditName = false;
                                });
                              },
                            )
                          : _DeleteAccountDialog(
                              onCancel: () {
                                setState(() {
                                  _showDeleteAccount = false;
                                });
                              },
                              onConfirm: () async {
                                setState(() {
                                  _showDeleteAccount = false;
                                });

                                try {
                                  await widget.onDeleteAccount();
                                } catch (error) {
                                  if (!context.mounted) return;

                                  CloveNotifications.show(
                                    context,
                                    SnackBar(
                                      content: Text(
                                        'Could not delete account: $error',
                                      ),
                                    ),
                                  );
                                }
                              },
                            ),
                    ),
                  ],
                ),
              ),
          ],
        ),
      ),
    );
  }

  Future<void> _openGithub() async {
    final uri = Uri.parse('https://github.com/shvnix/clove');

    try {
      final opened = await launchUrl(uri, mode: LaunchMode.externalApplication);

      if (!opened) {
        debugPrint('Could not open GitHub URL: $uri');
      }
    } catch (e) {
      debugPrint('Error opening GitHub: $e');
    }
  }

  void _openPage(BuildContext context, Widget page) {
    Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => page));
  }

  Widget _menuItem({
    required Widget leading,
    required String title,
    VoidCallback? onTap,
  }) {
    return ListTile(
      contentPadding: const EdgeInsets.symmetric(horizontal: 28, vertical: 4),
      leading: leading,
      title: Text(
        title,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 17,
          fontWeight: FontWeight.w500,
        ),
      ),
      onTap: onTap,
    );
  }
}

class _EditNameDialog extends StatefulWidget {
  const _EditNameDialog({
    required this.currentName,
    required this.onSave,
    required this.onCancel,
  });

  final String currentName;
  final Future<void> Function(String name) onSave;
  final VoidCallback onCancel;

  @override
  State<_EditNameDialog> createState() => _EditNameDialogState();
}

class _EditNameDialogState extends State<_EditNameDialog> {
  late final TextEditingController _controller;
  final _formKey = GlobalKey<FormState>();
  bool _saving = false;
  String? _error;

  @override
  void initState() {
    super.initState();
    _controller = TextEditingController(text: widget.currentName);
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    if (_saving || !(_formKey.currentState?.validate() ?? false)) return;
    final name = _controller.text.trim();
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      await widget.onSave(name);
      if (mounted) {
        widget.onCancel();
      }
    } catch (error) {
      if (!mounted) return;
      setState(() {
        _saving = false;
        _error = 'Could not save your name. Please try again.';
      });
      debugPrint('Failed to update local profile: $error');
    }
  }

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        final screenWidth = MediaQuery.sizeOf(context).width;
        final screenHeight = MediaQuery.sizeOf(context).height;

        return AlertDialog(
          backgroundColor: _profileCard,
          insetPadding: const EdgeInsets.symmetric(
            horizontal: 20,
            vertical: 24,
          ),
          title: const Text('Edit name'),
          content: SizedBox(
            width: screenWidth > 600 ? 400 : screenWidth * 0.85,
            child: ConstrainedBox(
              constraints: BoxConstraints(maxHeight: screenHeight * 0.55),
              child: SingleChildScrollView(
                child: Form(
                  key: _formKey,
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextFormField(
                        controller: _controller,
                        autofocus: true,
                        maxLength: 30,
                        textCapitalization: TextCapitalization.words,
                        decoration: const InputDecoration(labelText: 'Name'),
                        validator: (value) {
                          final name = value?.trim() ?? '';

                          if (name.isEmpty) {
                            return 'Enter a name.';
                          }

                          if (name.length > 30) {
                            return 'Use 30 characters or fewer.';
                          }

                          return null;
                        },
                      ),
                      if (_error != null) ...[
                        const SizedBox(height: 8),
                        Text(
                          _error!,
                          style: const TextStyle(color: Colors.redAccent),
                        ),
                      ],
                    ],
                  ),
                ),
              ),
            ),
          ),
          actions: [
            TextButton(
              onPressed: _saving ? null : widget.onCancel,
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Save'),
            ),
          ],
        );
      },
    );
  }
}

class _DeleteAccountDialog extends StatelessWidget {
  const _DeleteAccountDialog({required this.onCancel, required this.onConfirm});

  final VoidCallback onCancel;
  final Future<void> Function() onConfirm;

  @override
  Widget build(BuildContext context) {
    final screenWidth = MediaQuery.sizeOf(context).width;
    final screenHeight = MediaQuery.sizeOf(context).height;

    return AlertDialog(
      backgroundColor: _profileCard,
      insetPadding: const EdgeInsets.symmetric(horizontal: 20, vertical: 24),
      title: const Text('Delete account?'),
      content: SizedBox(
        width: screenWidth > 600 ? 400 : screenWidth * 0.85,
        child: ConstrainedBox(
          constraints: BoxConstraints(maxHeight: screenHeight * 0.45),
          child: const SingleChildScrollView(
            child: Text(
              'This permanently removes your local profile, playlists, '
              'liked songs, and playlist artwork from this device. '
              'Playback will stop and the queue will be cleared.',
            ),
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: onCancel,
          style: TextButton.styleFrom(foregroundColor: Colors.white),
          child: const Text('Cancel'),
        ),
        TextButton(
          onPressed: onConfirm,
          style: TextButton.styleFrom(foregroundColor: Colors.redAccent),
          child: const Text('Delete account'),
        ),
      ],
    );
  }
}
