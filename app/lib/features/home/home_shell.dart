import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/local/sync_controller.dart';
import '../../core/local/sync_widgets.dart';
import '../auth/auth_controller.dart';
import '../body/body_page.dart';
import '../guide/guide_page.dart';
import '../health/health_page.dart';
import '../health/health_repository.dart';
import '../nutrition/nutrition_page.dart';
import '../programs/programs_page.dart';
import '../workout/workout_page.dart';

class HomeShell extends ConsumerStatefulWidget {
  const HomeShell({super.key});

  @override
  ConsumerState<HomeShell> createState() => _HomeShellState();
}

class _HomeShellState extends ConsumerState<HomeShell> {
  int _tab = 0;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addPostFrameCallback((_) {
      ref.read(syncControllerProvider.notifier).syncNow();
      // Si la pulsera está conectada, al abrir la app se leen los últimos 30 días sin avisar
      ref.read(healthProvider.notifier).syncIfConnected();
    });
  }

  Future<void> _logout() async {
    final ops = ref.read(outboxProvider).valueOrNull ?? const [];
    if (ops.isNotEmpty) {
      final ok = await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: const Text('Hay cambios sin enviar'),
          content: Text('${ops.length} ${ops.length == 1 ? 'cambio no ha llegado' : 'cambios no han llegado'} al servidor. '
              'Se quedan en este dispositivo y se enviarán si vuelves a entrar con esta cuenta; con otra cuenta se borrarán.'),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Cerrar sesión')),
          ],
        ),
      );
      if (ok != true) return;
    }
    await ref.read(authProvider.notifier).logout();
  }

  static const _titles = ['Entreno', 'Comidas', 'Peso y medidas', 'Salud', 'Guía'];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final pages = [
      const WorkoutPage(),
      const NutritionPage(),
      const BodyPage(),
      const HealthPage(),
      const GuidePage(),
    ];
    final destinations = const [
      (Icons.fitness_center, 'Entreno'),
      (Icons.restaurant, 'Comidas'),
      (Icons.monitor_weight_outlined, 'Peso'),
      (Icons.favorite_outline, 'Salud'),
      (Icons.menu_book_outlined, 'Guía'),
    ];
    final body = IndexedStack(index: _tab, children: pages);
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          const SyncStatusButton(),
          IconButton(
            tooltip: 'Planes',
            icon: const Icon(Icons.calendar_view_week),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProgramsPage())),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: _logout,
          ),
        ],
      ),
      body: wide
          ? Row(children: [
              NavigationRail(
                selectedIndex: _tab,
                onDestinationSelected: (i) => setState(() => _tab = i),
                labelType: NavigationRailLabelType.all,
                destinations: [for (final d in destinations) NavigationRailDestination(icon: Icon(d.$1), label: Text(d.$2))],
              ),
              const VerticalDivider(width: 1),
              Expanded(child: body),
            ])
          : body,
      bottomNavigationBar: wide
          ? null
          : NavigationBar(
              selectedIndex: _tab,
              onDestinationSelected: (i) => setState(() => _tab = i),
              destinations: [for (final d in destinations) NavigationDestination(icon: Icon(d.$1), label: d.$2)],
            ),
    );
  }
}
