import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import 'core/local/sync_controller.dart';
import 'core/theme.dart';
import 'features/auth/auth_controller.dart';
import 'features/auth/login_page.dart';
import 'features/home/home_shell.dart';
import 'features/workout/workout_repository.dart' show catalogProvider, todayProvider;

void main() {
  // Pantallas que aún leen del servidor y dependen del perfil (plan activo):
  // se refrescan cuando llega un cambio del perfil por la sincronización.
  SyncController.afterPull.add((ref, changed) {
    if (changed.contains('profile')) {
      ref.invalidate(catalogProvider);
      ref.invalidate(todayProvider);
    }
  });
  runApp(const ProviderScope(child: CuadernoApp()));
}

class CuadernoApp extends StatelessWidget {
  const CuadernoApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Cuaderno de definición',
      debugShowCheckedModeBanner: false,
      theme: buildTheme(Brightness.light),
      darkTheme: buildTheme(Brightness.dark),
      locale: const Locale('es', 'ES'),
      supportedLocales: const [Locale('es', 'ES')],
      localizationsDelegates: GlobalMaterialLocalizations.delegates,
      home: const _Root(),
    );
  }
}

class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    return ref.watch(authProvider).when(
          loading: () => const Scaffold(body: Center(child: CircularProgressIndicator())),
          error: (_, __) => const LoginPage(),
          data: (loggedIn) => loggedIn ? const HomeShell() : const LoginPage(),
        );
  }
}
