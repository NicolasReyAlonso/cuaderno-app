import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../theme.dart';
import 'local_db.dart';
import 'sync_api.dart';
import 'sync_controller.dart';

const _months = ['ene', 'feb', 'mar', 'abr', 'may', 'jun', 'jul', 'ago', 'sep', 'oct', 'nov', 'dic'];

/// Cómo se llama cada tipo de registro y cada campo en la pantalla de conflictos.
/// Los pasos siguientes añaden comidas, entreno y planes.
const _titles = {
  'body_entry': 'Peso y medidas',
  'profile': 'Punto de partida y objetivos',
  'food': 'Alimento propio',
  'dish': 'Plato',
  'diary_item': 'Entrada del diario',
};
const _fields = {
  'weight_kg': 'Peso (kg)',
  'waist_cm': 'Cintura (cm)',
  'kcal': 'Calorías',
  'protein_g': 'Proteína (g)',
  'name': 'Nombre',
  'start_date': 'Fecha de inicio',
  'start_weight_kg': 'Peso inicial (kg)',
  'start_body_fat_pct': 'Grasa inicial (%)',
  'kcal_target': 'Objetivo de kcal',
  'protein_target_g': 'Objetivo de proteína (g)',
  'program_id': 'Plan activo',
  'program_started_on': 'Inicio del plan',
  'category': 'Categoría',
  'protein': 'Proteína (g)',
  'carbs': 'Carbohidratos (g)',
  'fat': 'Grasa (g)',
  'default_portion_g': 'Ración (g)',
  'servings': 'Raciones',
  'cooked_weight_g': 'Peso cocinado (g)',
  'ingredients': 'Ingredientes',
  'meal': 'Comida',
  'grams': 'Gramos',
};
// Campos que la app guarda para mostrar pero que no decide el usuario
const _hidden = {'date', 'weight_source', 'food_id', 'dish_id', 'created_at'};

String _dateText(String iso) {
  final d = DateTime.tryParse(iso);
  return d == null ? iso : '${d.day} ${_months[d.month - 1]} ${d.year}';
}

/// «Peso y medidas del 20 oct 2026», «Plato: Arroz con marisco», «Entrada del diario: Bol (20 oct 2026)».
String describe(String entity, String id, [Map<String, dynamic>? data]) {
  final title = _titles[entity] ?? entity;
  if (RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(id)) return '$title del ${_dateText(id)}';
  final name = data?['name'];
  final date = data?['date'];
  if (name is String && name.isNotEmpty) return '$title: $name${date is String ? ' (${_dateText(date)})' : ''}';
  return title;
}

String _value(Object? v) {
  if (v == null) return '—';
  if (v is num) {
    final s = v == v.roundToDouble() ? v.toStringAsFixed(0) : v.toString();
    return s.replaceAll('.', ',');
  }
  if (v is String && RegExp(r'^\d{4}-\d{2}-\d{2}$').hasMatch(v)) return _dateText(v);
  if (v is List) return v.length == 1 ? '1 elemento' : '${v.length} elementos';
  return '$v';
}

/// Icono de la barra superior: al día, sin conexión, enviando o con algo por resolver.
class SyncStatusButton extends ConsumerWidget {
  const SyncStatusButton({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final cs = Theme.of(context).colorScheme;
    final s = ref.watch(syncControllerProvider);
    final ops = ref.watch(outboxProvider).valueOrNull ?? const <OutboxOp>[];
    final problems = ops.where((o) => o.state == 'conflict' || o.state == 'rejected').length;
    final pending = ops.length - problems;
    final (IconData icon, String tip, Color? color, int badge) = problems > 0
        ? (Icons.sync_problem, '$problems ${problems == 1 ? 'cambio necesita' : 'cambios necesitan'} que elijas', cs.error, problems)
        : s.online == false
            ? (Icons.cloud_off_outlined, 'Sin conexión: los cambios se guardan en el dispositivo', null, pending)
            : pending > 0
                ? (Icons.cloud_upload_outlined, '$pending ${pending == 1 ? 'cambio' : 'cambios'} por enviar', null, pending)
                : (Icons.cloud_done_outlined, 'Todo sincronizado', null, 0);
    return IconButton(
      tooltip: tip,
      onPressed: () => Navigator.of(context).push(MaterialPageRoute<void>(builder: (_) => const SyncPage())),
      icon: Badge(
        isLabelVisible: badge > 0,
        label: Text('$badge'),
        backgroundColor: problems > 0 ? cs.error : cs.primary,
        child: s.syncing && problems == 0 ? const SizedBox(width: 20, height: 20, child: CircularProgressIndicator(strokeWidth: 2)) : Icon(icon, color: color),
      ),
    );
  }
}

/// Estado de la sincronización, conflictos por elegir y cambios rechazados.
class SyncPage extends ConsumerWidget {
  const SyncPage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final s = ref.watch(syncControllerProvider);
    final ops = ref.watch(outboxProvider).valueOrNull ?? const <OutboxOp>[];
    final conflicts = ops.where((o) => o.state == 'conflict').toList();
    final rejected = ops.where((o) => o.state == 'rejected').toList();
    final pending = ops.where((o) => o.state == 'pending' || o.state == 'sending').toList();
    final engine = ref.read(syncEngineProvider);
    final c = ref.read(syncControllerProvider.notifier);
    final last = s.lastSync;

    return Scaffold(
      appBar: AppBar(title: const Text('Sincronización')),
      body: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 720),
              child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                Panel(
                  child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                    Text(
                      s.online == false
                          ? 'Sin conexión con el servidor. Puedes seguir usando la app: los cambios se guardan aquí y se envían al volver.'
                          : last == null
                              ? 'Aún no se ha sincronizado en esta sesión.'
                              : 'Sincronizado a las ${last.hour}:${last.minute.toString().padLeft(2, '0')}.',
                    ),
                    if (s.error != null) ...[const SizedBox(height: 6), Text(s.error!, style: TextStyle(color: cs.error))],
                    const SizedBox(height: 6),
                    Text(
                      pending.isEmpty ? 'No hay cambios por enviar.' : '${pending.length} ${pending.length == 1 ? 'cambio espera' : 'cambios esperan'} a enviarse.',
                      style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                    ),
                    const SizedBox(height: 10),
                    Align(
                      alignment: Alignment.centerLeft,
                      child: FilledButton.tonalIcon(
                        onPressed: s.syncing ? null : c.syncNow,
                        icon: const Icon(Icons.sync),
                        label: const Text('Sincronizar ahora'),
                      ),
                    ),
                  ]),
                ),
                if (conflicts.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('Cambiado en dos sitios', style: t.textTheme.titleMedium),
                  Text('Esto se cambió aquí y en otro dispositivo a la vez. Elige qué versión se queda.',
                      style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                  for (final o in conflicts)
                    _ConflictCard(op: o, onMine: () => engine.keepMine(o).then((_) => c.syncNow()), onServer: () => engine.keepServer(o)),
                ],
                if (rejected.isNotEmpty) ...[
                  const SizedBox(height: 20),
                  Text('No se pudieron guardar', style: t.textTheme.titleMedium),
                  for (final o in rejected)
                    Padding(
                      padding: const EdgeInsets.only(top: 8),
                      child: Panel(
                        highlight: cs.error,
                        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                          Text(describe(o.entity, o.recordId, decode(o.data)), style: t.textTheme.titleSmall),
                          const SizedBox(height: 4),
                          Text(o.detail ?? 'El servidor no lo aceptó.'),
                          const SizedBox(height: 8),
                          Align(
                            alignment: Alignment.centerLeft,
                            child: TextButton(onPressed: () => engine.discard(o), child: const Text('Descartar mi cambio')),
                          ),
                        ]),
                      ),
                    ),
                ],
              ]),
            ),
          ),
        ],
      ),
    );
  }
}

class _ConflictCard extends StatelessWidget {
  const _ConflictCard({required this.op, required this.onMine, required this.onServer});
  final OutboxOp op;
  final VoidCallback onMine, onServer;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final mine = op.isDelete ? null : decode(op.data);
    final server = op.serverRecord == null ? null : RemoteRecord.fromJson(decode(op.serverRecord)!);
    final theirs = server == null || server.deleted ? null : server.data;
    // Las listas (ingredientes) se comparan por su contenido, no por ser el mismo objeto
    bool differs(String k) => '${mine?[k]}' != '${theirs?[k]}';
    final keys = {...?mine?.keys, ...?theirs?.keys}.where((k) => !_hidden.contains(k) && differs(k)).toList();

    Widget column(String title, Map<String, dynamic>? data, String deletedText) => Expanded(
          child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
            Text(title, style: t.textTheme.labelLarge?.copyWith(color: cs.primary)),
            const SizedBox(height: 4),
            if (data == null)
              Text(deletedText)
            else
              for (final k in keys) Text('${_fields[k] ?? k}: ${_value(data[k])}', style: t.textTheme.bodyMedium),
          ]),
        );

    return Padding(
      padding: const EdgeInsets.only(top: 8),
      child: Panel(
        child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text(describe(op.entity, op.recordId, mine ?? theirs), style: t.textTheme.titleSmall),
          const SizedBox(height: 8),
          Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
            column('Tu cambio', mine, 'Lo borraste'),
            const SizedBox(width: 12),
            column('En el servidor', theirs, 'Se borró en otro dispositivo'),
          ]),
          const SizedBox(height: 10),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton(onPressed: onMine, child: const Text('Quedarme con lo mío')),
            OutlinedButton(onPressed: onServer, child: const Text('Quedarme con lo del servidor')),
          ]),
        ]),
      ),
    );
  }
}
