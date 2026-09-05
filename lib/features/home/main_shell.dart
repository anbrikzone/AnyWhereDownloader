import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/update/update_providers.dart';
import '../../l10n/app_localizations.dart';
import '../library/library_controller.dart';
import '../library/library_screen.dart';
import 'home_screen.dart';

/// Top-level bottom-nav shell: Home and Library as separate tabs, each
/// keeping its own full `Scaffold` (own AppBar; Library also has its own
/// contextual selection action bar, which stacks visually above this
/// shell's persistent nav bar rather than conflicting with it, since only
/// one `Scaffold.bottomNavigationBar` slot is ever the outermost one).
/// Settings is reached via a gear icon in Home's own AppBar (pushed as a
/// normal route), not a third bottom-nav tab — moved there per explicit
/// user request after trying it as a tab.
class MainShell extends ConsumerStatefulWidget {
  const MainShell({super.key});

  @override
  ConsumerState<MainShell> createState() => _MainShellState();
}

class _MainShellState extends ConsumerState<MainShell> {
  int _index = 0;

  // Library's controller requests gallery permission as soon as it's
  // created — keeping it out of the widget tree until the user actually
  // opens the tab avoids an unexpected permission prompt on app launch.
  bool _libraryVisited = false;

  @override
  void initState() {
    super.initState();
    // Silent, best-effort GitHub-release check — throttled to ≤ once/day
    // inside the controller. Mirrors the native yt-dlp self-heal that
    // already runs on every cold start; never blocks the UI.
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(updateControllerProvider.notifier).maybeCheckOnStartup();
    });
  }

  void _onDestinationSelected(int index) {
    final wasVisited = _libraryVisited;
    setState(() {
      _index = index;
      if (index == 1) _libraryVisited = true;
    });
    // The IndexedStack keeps LibraryScreen alive once visited, so
    // re-selecting its tab never remounts it and LibraryController never
    // reloads on its own. Nudge a refresh on every *return* to the tab
    // (not the first open — the controller already loads once when it
    // first mounts) so files downloaded meanwhile show up without a
    // manual Refresh tap. refresh() no-ops unless gallery permission is
    // already granted, so this can't surface the permission prompt.
    if (index == 1 && wasVisited && !ref.read(libraryControllerProvider).busy) {
      ref.read(libraryControllerProvider.notifier).refresh();
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      body: IndexedStack(
        index: _index,
        children: [
          const HomeScreen(),
          _libraryVisited ? const LibraryScreen() : const SizedBox.shrink(),
        ],
      ),
      bottomNavigationBar: NavigationBar(
        selectedIndex: _index,
        onDestinationSelected: _onDestinationSelected,
        destinations: [
          NavigationDestination(
            icon: const Icon(Icons.home_outlined),
            selectedIcon: const Icon(Icons.home),
            label: l10n.navHome,
          ),
          NavigationDestination(
            icon: const Icon(Icons.photo_library_outlined),
            selectedIcon: const Icon(Icons.photo_library),
            label: l10n.navLibrary,
          ),
        ],
      ),
    );
  }
}
