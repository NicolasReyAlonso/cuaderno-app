import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../auth/auth_controller.dart';
import '../body/body_page.dart';
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
    // Si la pulsera está conectada, al abrir la app se leen los últimos 30 días sin avisar
    WidgetsBinding.instance.addPostFrameCallback((_) => ref.read(healthProvider.notifier).syncIfConnected());
  }

  static const _titles = ['Entreno', 'Comidas', 'Peso y medidas', 'Guía'];

  @override
  Widget build(BuildContext context) {
    final wide = MediaQuery.sizeOf(context).width >= 840;
    final pages = [
      const WorkoutPage(),
      const NutritionPage(),
      const BodyPage(),
      const _NextPhase(icon: Icons.menu_book_outlined, title: 'Guía', text: 'Cómo progresar y cuándo ajustar calorías. Llega en la fase 3.'),
    ];
    final destinations = const [
      (Icons.fitness_center, 'Entreno'),
      (Icons.restaurant, 'Comidas'),
      (Icons.monitor_weight_outlined, 'Peso'),
      (Icons.menu_book_outlined, 'Guía'),
    ];
    final body = IndexedStack(index: _tab, children: pages);
    return Scaffold(
      appBar: AppBar(
        title: Text(_titles[_tab]),
        actions: [
          IconButton(
            tooltip: 'Planes',
            icon: const Icon(Icons.calendar_view_week),
            onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const ProgramsPage())),
          ),
          IconButton(
            tooltip: 'Cerrar sesión',
            icon: const Icon(Icons.logout),
            onPressed: () => ref.read(authProvider.notifier).logout(),
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

class _NextPhase extends StatelessWidget {
  const _NextPhase({required this.icon, required this.title, required this.text});
  final IconData icon;
  final String title, text;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: Column(mainAxisSize: MainAxisSize.min, children: [
            Icon(icon, size: 40, color: t.colorScheme.primary),
            const SizedBox(height: 12),
            Text(title, style: t.textTheme.titleLarge),
            const SizedBox(height: 8),
            Text(text, textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
          ]),
        ),
      ),
    );
  }
}
