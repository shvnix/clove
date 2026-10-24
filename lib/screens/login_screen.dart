import 'package:flutter/material.dart';

import '../data/database.dart';
import 'main_shell.dart';

const Color _obsidian = Color(0xFF0B0B0B);
const Color _inputSurface = Color(0xFF202020);
const Color _cloveMint = Color(0xFF1DE9B6);
const Color _primaryText = Color(0xFFFFFFFF);

class CloveLoginScreen extends StatefulWidget {
  final AppDatabase database;

  const CloveLoginScreen({super.key, required this.database});

  @override
  State<CloveLoginScreen> createState() => _CloveLoginScreenState();
}

class _CloveLoginScreenState extends State<CloveLoginScreen> {
  final TextEditingController _nameController = TextEditingController();

  final FocusNode _nameFocusNode = FocusNode();
  String? _errorMessage;

  Future<void> _continue() async {
    final String username = _nameController.text.trim();

    if (username.isEmpty) {
      setState(() {
        _errorMessage = 'Please enter your name to continue.';
      });

      _nameFocusNode.requestFocus();
      return;
    }

    if (username.length > 30) {
      setState(() {
        _errorMessage = 'Your name must be 30 characters or less.';
      });
      return;
    }

    FocusScope.of(context).unfocus();

    try {
      // Save the name before navigating.
      await AppDatabase.instance.saveProfile(username);

      if (!mounted) return;

      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => MainShell(username: username)),
      );
    } catch (error, stackTrace) {
      debugPrint('Failed to save profile: $error');
      debugPrintStack(stackTrace: stackTrace);

      if (!mounted) return;

      setState(() {
        _errorMessage = 'Could not save your name. Please try again.';
      });
    }
  }

  @override
  void dispose() {
    _nameController.dispose();
    _nameFocusNode.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: _obsidian,
      body: GestureDetector(
        behavior: HitTestBehavior.translucent,
        onTap: () {
          FocusScope.of(context).unfocus();
        },
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Main login screen
            SafeArea(
              child: LayoutBuilder(
                builder: (context, constraints) {
                  return SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 28,
                      vertical: 24,
                    ),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: constraints.maxHeight - 48,
                      ),
                      child: IntrinsicHeight(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const SizedBox(height: 24),

                            const Spacer(flex: 2),

                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Text(
                                  'CLOVE',
                                  style: TextStyle(
                                    color: _cloveMint,
                                    fontSize: 22,
                                    fontWeight: FontWeight.w800,
                                    letterSpacing: 4,
                                  ),
                                ),
                              ],
                            ),

                            const SizedBox(height: 82),

                            // Heading
                            const Text(
                              'Music\nis personal.',
                              style: TextStyle(
                                color: _primaryText,
                                fontSize: 34,
                                fontWeight: FontWeight.w700,
                                height: 1.15,
                                letterSpacing: -1,
                              ),
                            ),

                            const SizedBox(height: 10),

                            const Text(
                              'Let’s make this space yours.',
                              style: TextStyle(
                                color: Colors.white60,
                                fontSize: 13,
                                height: 1.5,
                              ),
                            ),

                            const SizedBox(height: 70),

                            const Text(
                              'WHAT SHOULD WE CALL YOU?',
                              style: TextStyle(
                                color: _cloveMint,
                                fontSize: 11,
                                fontWeight: FontWeight.w700,
                                letterSpacing: 2,
                              ),
                            ),

                            const SizedBox(height: 12),

                            // Username field
                            TextField(
                              controller: _nameController,
                              focusNode: _nameFocusNode,
                              autofocus: false,
                              maxLength: 30,
                              textCapitalization: TextCapitalization.words,
                              textInputAction: TextInputAction.go,
                              keyboardType: TextInputType.name,
                              style: const TextStyle(
                                color: _primaryText,
                                fontSize: 16,
                                fontWeight: FontWeight.w500,
                              ),
                              onChanged: (_) {
                                if (_errorMessage != null) {
                                  setState(() {
                                    _errorMessage = null;
                                  });
                                }
                              },
                              onSubmitted: (_) => _continue(),
                              decoration: InputDecoration(
                                counterText: '',
                                hintText: 'Enter your name',
                                hintStyle: const TextStyle(
                                  color: Colors.white38,
                                ),
                                prefixIcon: const Icon(
                                  Icons.person_outline_rounded,
                                  color: Colors.white54,
                                ),
                                filled: true,
                                fillColor: _inputSurface,
                                contentPadding: const EdgeInsets.symmetric(
                                  horizontal: 18,
                                  vertical: 17,
                                ),
                                border: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: BorderSide.none,
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(16),
                                  borderSide: const BorderSide(
                                    color: _cloveMint,
                                    width: 1.2,
                                  ),
                                ),
                                errorText: _errorMessage,
                              ),
                            ),

                            const SizedBox(height: 20),

                            // Continue button
                            SizedBox(
                              width: double.infinity,
                              height: 58,
                              child: FilledButton(
                                onPressed: _continue,
                                style: FilledButton.styleFrom(
                                  backgroundColor: _cloveMint,
                                  foregroundColor: _obsidian,
                                  elevation: 0,
                                  shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(16),
                                  ),
                                ),
                                child: const Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Text(
                                      'Let’s get started',
                                      style: TextStyle(
                                        fontSize: 15,
                                        fontWeight: FontWeight.w700,
                                      ),
                                    ),
                                    SizedBox(width: 10),
                                    Icon(Icons.arrow_forward_rounded, size: 20),
                                  ],
                                ),
                              ),
                            ),

                            const Spacer(flex: 3),

                            // Privacy disclaimer footer
                            Center(
                              child: Padding(
                                padding: const EdgeInsets.only(
                                  top: 24,
                                  bottom: 16,
                                ),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        const Icon(
                                          Icons.shield_outlined,
                                          color: _cloveMint,
                                          size: 16,
                                        ),
                                        const SizedBox(width: 8),
                                        const Text(
                                          'YOUR MUSIC. YOUR RULES. YOUR PRIVACY.',
                                          textAlign: TextAlign.center,
                                          style: TextStyle(
                                            color: _cloveMint,
                                            fontSize: 10,
                                            fontWeight: FontWeight.w700,
                                            letterSpacing: 1.1,
                                          ),
                                        ),
                                      ],
                                    ),

                                    const SizedBox(height: 10),

                                    Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 8,
                                      ),
                                      child: Text(
                                        'Your data stays on your device. CLOVE is '
                                        'designed to respect your privacy and keep '
                                        'your personal information under your control. '
                                        'Uninstalling the app may permanently erase '
                                        'locally stored data.',
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                          color: Colors.white.withValues(
                                            alpha: 0.45,
                                          ),
                                          fontSize: 10,
                                          height: 1.7,
                                          letterSpacing: 0.15,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),

            // Floating PNG logo at the top-right corner
            // Half inside the screen and half outside
            Positioned(
              top: -45,
              right: -250,
              child: IgnorePointer(
                child: Opacity(
                  opacity: 0.18,
                  child: ShaderMask(
                    blendMode: BlendMode.dstIn,
                    shaderCallback: (Rect bounds) {
                      return const LinearGradient(
                        begin: Alignment.topCenter,
                        end: Alignment.bottomCenter,
                        colors: [
                          Colors.white,
                          Colors.white,
                          Colors.transparent,
                        ],
                        stops: [0.0, 0.45, 1.0],
                      ).createShader(bounds);
                    },
                    child: Image.asset(
                      'assets/icon/icon.png',
                      width: 600,
                      height: 600,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}
