import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/settings/settings_providers.dart';
import 'core/theme/app_theme.dart';
import 'features/home/main_shell.dart';
import 'l10n/app_localizations.dart';

void main() {
  runApp(const ProviderScope(child: AnyWhereDownloaderApp()));
}

class AnyWhereDownloaderApp extends ConsumerWidget {
  const AnyWhereDownloaderApp({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final themeMode = ref.watch(themeModeProvider);
    final locale = ref.watch(localeProvider);
    return MaterialApp(
      title: 'AnyWhere Downloader',
      debugShowCheckedModeBanner: false,
      theme: AppTheme.light,
      darkTheme: AppTheme.dark,
      themeMode: themeMode,
      locale: locale,
      localizationsDelegates: const [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: AppLocalizations.supportedLocales,
      home: const MainShell(),
    );
  }
}
