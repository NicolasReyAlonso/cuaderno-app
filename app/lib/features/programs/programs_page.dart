import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import 'models.dart';
import 'program_editor_page.dart';
import 'programs_repository.dart';

/// Lunes de la semana de [d]: el inicio por defecto al activar un plan.
DateTime mondayOf(DateTime d) => DateTime(d.year, d.month, d.day).subtract(Duration(days: d.weekday - 1));

class ProgramsPage extends ConsumerWidget {
  const ProgramsPage({super.key});

  void _show(BuildContext context, String text) => ScaffoldMessenger.of(context).showSnackBar(SnackBar(content: Text(text)));

  Future<void> _run(BuildContext context, WidgetRef ref, Future<void> Function() action, String done) async {
    try {
      await action();
      refreshAfterPlanChange(ref);
      if (context.mounted) _show(context, done);
    } catch (e) {
      if (context.mounted) _show(context, apiMessage(e));
    }
  }

  Future<void> _activate(BuildContext context, WidgetRef ref, ProgramSummary p) async {
    final start = await showDatePicker(
      context: context,
      helpText: p.weeks > 1 ? '¿Qué día empieza la semana 1?' : '¿Desde qué día usas este plan?',
      initialDate: mondayOf(DateTime.now()),
      firstDate: DateTime(2024),
      lastDate: DateTime.now().add(const Duration(days: 60)),
    );
    if (start == null || !context.mounted) return;
    await _run(context, ref, () => ref.read(programsRepositoryProvider).activate(p.id, start), '«${p.name}» es tu plan activo.');
  }

  Future<void> _delete(BuildContext context, WidgetRef ref, ProgramSummary p) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text('¿Borrar «${p.name}»?'),
        content: const Text('Las sesiones que hiciste con él se quedan en tu historial.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true || !context.mounted) return;
    await _run(context, ref, () => ref.read(programsRepositoryProvider).delete(p.id), 'Plan borrado.');
  }

  Future<void> _duplicate(BuildContext context, WidgetRef ref, ProgramSummary p) async {
    try {
      final copy = await ref.read(programsRepositoryProvider).duplicate(p.id);
      refreshAfterPlanChange(ref);
      if (context.mounted) await _open(context, copy.id);
    } catch (e) {
      if (context.mounted) _show(context, apiMessage(e));
    }
  }

  Future<void> _open(BuildContext context, String? id) =>
      Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => ProgramEditorPage(programId: id)));

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Planes')),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _open(context, null),
        icon: const Icon(Icons.add),
        label: const Text('Nuevo plan'),
      ),
      body: ref.watch(programsProvider).when(
            loading: () => const Center(child: CircularProgressIndicator()),
            error: (e, _) => Center(
              child: Column(mainAxisSize: MainAxisSize.min, children: [
                Text(apiMessage(e), textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.tonal(onPressed: () => ref.invalidate(programsProvider), child: const Text('Reintentar')),
              ]),
            ),
            data: (programs) => ListView(
              padding: const EdgeInsets.fromLTRB(16, 8, 16, 96),
              children: [
                Center(
                  child: ConstrainedBox(
                    constraints: const BoxConstraints(maxWidth: 820),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      for (final p in programs)
                        Card(
                          child: ListTile(
                            onTap: () => _open(context, p.id),
                            leading: Icon(p.active ? Icons.check_circle : Icons.calendar_view_week,
                                color: p.active ? t.colorScheme.primary : t.colorScheme.onSurfaceVariant),
                            title: Text(p.name),
                            subtitle: Text([
                              p.weeks == 1 ? '1 semana' : '${p.weeks} semanas',
                              '${p.daysPerWeek} días por semana',
                              if (!p.mine) 'plantilla',
                              if (p.active) 'activo',
                            ].join(' · ')),
                            trailing: PopupMenuButton<String>(
                              tooltip: 'Opciones',
                              onSelected: (v) => switch (v) {
                                'activate' => _activate(context, ref, p),
                                'duplicate' => _duplicate(context, ref, p),
                                'delete' => _delete(context, ref, p),
                                _ => _open(context, p.id),
                              },
                              itemBuilder: (_) => [
                                if (!p.active) const PopupMenuItem(value: 'activate', child: Text('Activar')),
                                PopupMenuItem(value: 'open', child: Text(p.mine ? 'Editar' : 'Ver')),
                                const PopupMenuItem(value: 'duplicate', child: Text('Duplicar')),
                                if (p.mine && !p.active) const PopupMenuItem(value: 'delete', child: Text('Borrar')),
                              ],
                            ),
                          ),
                        ),
                    ]),
                  ),
                ),
              ],
            ),
          ),
    );
  }
}
