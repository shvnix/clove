import 'package:flutter/material.dart';

class SearchScreen extends StatelessWidget {
  const SearchScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF0B0B0B),
      appBar: AppBar(
        backgroundColor: const Color(0xFF0B0B0B),
        foregroundColor: Colors.white,
        title: const Text('Search'),
      ),
      body: const Center(
        child: Text(
          'Search Screen',
          style: TextStyle(color: Colors.white),
        ),
      ),
    );
  }
}