import 'dart:ui';

import 'package:flutter/material.dart';
import 'package:flutter/cupertino.dart';
import 'package:go_router/go_router.dart';
import 'package:zinemo/theme/app_theme.dart';

class AppShell extends StatelessWidget {
  final StatefulNavigationShell navigationShell;

  const AppShell({required this.navigationShell, super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Stack(
        children: [
          navigationShell,
          // Floating transparent pill nav bar with 5 items
          Positioned(
            left: 16,
            right: 16,
            bottom: 20,
            child: ClipRRect(
              borderRadius: BorderRadius.circular(32),
              child: BackdropFilter(
                filter: ImageFilter.blur(sigmaX: 12, sigmaY: 12),
                child: Container(
                  height: 70,
                  decoration: BoxDecoration(
                    color: Colors.black.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(32),
                    border: Border(
                      left: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 0.8,
                      ),
                      right: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 0.8,
                      ),
                      bottom: BorderSide(
                        color: Colors.white.withValues(alpha: 0.1),
                        width: 0.8,
                      ),
                      top: BorderSide.none,
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                    children: List.generate(5, (index) {
                      final isSelected = navigationShell.currentIndex == index;
                      final labels = [
                        'Home',
                        'Search',
                        'AI Recs',
                        'Progress',
                        'Profile',
                      ];
                      final icons = [
                        CupertinoIcons.home,
                        CupertinoIcons.search,
                        CupertinoIcons.sparkles,
                        CupertinoIcons.play_rectangle,
                        CupertinoIcons.person,
                      ];
                      final selectedIcons = [
                        CupertinoIcons.home,
                        CupertinoIcons.search,
                        CupertinoIcons.star_fill,
                        CupertinoIcons.play_rectangle_fill,
                        CupertinoIcons.person_fill,
                      ];

                      return Expanded(
                        child: GestureDetector(
                          onTap: () => navigationShell.goBranch(index),
                          child: Padding(
                            padding: const EdgeInsets.symmetric(vertical: 11),
                            child: Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Icon(
                                  isSelected
                                      ? selectedIcons[index]
                                      : icons[index],
                                  size: 20,
                                  color: isSelected
                                      ? AppTheme.primary
                                      : Colors.white.withValues(alpha: 0.5),
                                ),
                                if (isSelected) ...[
                                  const SizedBox(height: 2),
                                  Text(
                                    labels[index],
                                    style: const TextStyle(
                                      color: AppTheme.primary,
                                      fontSize: 8.5,
                                      fontWeight: FontWeight.w600,
                                    ),
                                  ),
                                ],
                              ],
                            ),
                          ),
                        ),
                      );
                    }),
                  ),
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
