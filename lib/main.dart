import 'package:flutter/material.dart';
import 'screens/splash_screen.dart';


const Color cloveObsidian = Color(0xFF0B0B0B);
const Color cloveInput = Color(0xFF202020);
const Color cloveMint = Color(0xFF1DE9B6);
const Color cloveText = Color(0xFFFFFFFF);

void main() {
  runApp(const CloveApp());
}

class CloveApp extends StatelessWidget {
  const CloveApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      debugShowCheckedModeBanner: false,
      title: 'Clove',
      theme: ThemeData(
        useMaterial3: true,
        scaffoldBackgroundColor: cloveObsidian,
        colorScheme: const ColorScheme.dark(
          primary: cloveMint,
          surface: cloveObsidian,
          onPrimary: cloveObsidian,
          onSurface: cloveText,
        ),
        inputDecorationTheme: InputDecorationTheme(
          filled: true,
          fillColor: cloveInput,
          hintStyle: const TextStyle(color: Colors.white38),
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
              color: cloveMint,
              width: 1.3,
            ),
          ),
        ),
      ),
      home: const CloveSplashScreen(),
    );
  }
}
