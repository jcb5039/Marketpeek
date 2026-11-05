import 'package:flutter/material.dart';

import 'home/home_screen.dart';
import 'settings/settings_screen.dart';
import 'widgets_tab/widgets_screen.dart';

/// 하단 탭: 홈 / 위젯 / 설정
class RootShell extends StatefulWidget {
  const RootShell({super.key});

  @override
  State<RootShell> createState() => _RootShellState();
}

class _RootShellState extends State<RootShell> {
  int _index = 0;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: const [HomeScreen(), WidgetsScreen(), SettingsScreen()],
      ),
      bottomNavigationBar: NavigationBar(
        height: 64,
        selectedIndex: _index,
        onDestinationSelected: (i) => setState(() => _index = i),
        destinations: const [
          NavigationDestination(icon: Icon(Icons.home_outlined), selectedIcon: Icon(Icons.home), label: '홈'),
          NavigationDestination(icon: Icon(Icons.widgets_outlined), selectedIcon: Icon(Icons.widgets), label: '위젯'),
          NavigationDestination(icon: Icon(Icons.tune), label: '설정'),
        ],
      ),
    );
  }
}
