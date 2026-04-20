import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';

class BottomNavBar extends StatelessWidget {
  const BottomNavBar({super.key, required this.activeTab});

  final String activeTab;

  @override
  Widget build(BuildContext context) {
    const tabs = <_NavTab>[
      _NavTab(
        id: 'home',
        icon: Icons.home_rounded,
        label: 'Home',
        route: '/home',
      ),
      _NavTab(
        id: 'play',
        icon: Icons.play_arrow_rounded,
        label: 'Play',
        route: '/game/fruits',
      ),
      _NavTab(
        id: 'progress',
        icon: Icons.trending_up_rounded,
        label: 'Progress',
        route: '/progress',
      ),
      _NavTab(
        id: 'profile',
        icon: Icons.person_rounded,
        label: 'Profile',
        route: '/profile',
      ),
    ];

    return SafeArea(
      top: false,
      child: Container(
        margin: const EdgeInsets.fromLTRB(16, 0, 16, 8),
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        decoration: BoxDecoration(
          color: Colors.white,
          borderRadius: BorderRadius.circular(24),
          border: Border.all(color: const Color(0x14000000)),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceAround,
          children: tabs.map((_NavTab tab) {
            final isActive = tab.id == activeTab;
            return Expanded(
              child: InkWell(
                borderRadius: BorderRadius.circular(18),
                onTap: () => context.go(tab.route),
                child: AnimatedContainer(
                  duration: const Duration(milliseconds: 220),
                  padding: const EdgeInsets.symmetric(
                    vertical: 10,
                    horizontal: 8,
                  ),
                  decoration: BoxDecoration(
                    color: isActive
                        ? const Color(0x1A4CC9F0)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(18),
                  ),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    children: <Widget>[
                      Icon(
                        tab.icon,
                        color: isActive
                            ? const Color(0xFF4CC9F0)
                            : const Color(0xFF6B6B6B),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        tab.label,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: isActive
                              ? FontWeight.w700
                              : FontWeight.w500,
                          color: isActive
                              ? const Color(0xFF4CC9F0)
                              : const Color(0xFF6B6B6B),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            );
          }).toList(),
        ),
      ),
    );
  }
}

class _NavTab {
  const _NavTab({
    required this.id,
    required this.icon,
    required this.label,
    required this.route,
  });

  final String id;
  final IconData icon;
  final String label;
  final String route;
}
