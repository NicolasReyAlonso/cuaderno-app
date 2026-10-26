import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../workout/exercise_card.dart' show fmtNum, shortDate;
import 'health_models.dart';
import 'health_repository.dart';

/// Conectar con Health Connect / Salud, sincronizar y desconectar.
class HealthPanel extends ConsumerWidget {
  const HealthPanel({super.key});

  Future<void> _disconnect(BuildContext context, WidgetRef ref) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('¿Desconectar la pulsera?'),
        content: const Text('Se borran del servidor los pasos, el sueño, el pulso, las actividades y los pesos de la báscula. '
            'Lo que apuntaste a mano se queda.'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Desconectar y borrar')),
        ],
      ),
    );
    if (ok == true) await ref.read(healthProvider.notifier).disconnect();
  }

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final muted = t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant);
    final async = ref.watch(healthProvider);
    final s = async.valueOrNull;
    // En Mac y web no se muestra: allí solo se ven los datos ya sincronizados (semanas y actividades)
    if (s == null || !s.supported) return const SizedBox.shrink();
    final c = ref.read(healthProvider.notifier);
    final store = Theme.of(context).platform == TargetPlatform.android ? 'Health Connect' : 'Salud';

    return Panel(
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Icon(Icons.watch_outlined, color: cs.primary),
          const SizedBox(width: 8),
          Expanded(child: Text('Pulsera y báscula', style: t.textTheme.titleMedium)),
          if (s.connected)
            PopupMenuButton<String>(
              tooltip: 'Opciones',
              onSelected: (_) => _disconnect(context, ref),
              itemBuilder: (_) => const [PopupMenuItem(value: 'off', child: Text('Desconectar y borrar datos de salud'))],
            ),
        ]),
        const SizedBox(height: 6),
        if (s.problem != null) ...[
          Text(s.problem!),
          const SizedBox(height: 8),
          Wrap(spacing: 8, children: [
            if (Theme.of(context).platform == TargetPlatform.android)
              FilledButton.tonal(onPressed: c.install, child: const Text('Abrir Google Play')),
            TextButton(onPressed: () => ref.invalidate(healthProvider), child: const Text('Ya está, comprobar de nuevo')),
          ]),
        ] else if (!s.connected) ...[
          Text('Lee de $store los pasos, kcal activas, sueño, pulso en reposo, variabilidad, actividades y el peso de tu báscula. '
              'Tu pulsera tiene que sincronizar con $store (en Zepp o Mi Fitness: Perfil → Apps conectadas).', style: muted),
          const SizedBox(height: 10),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.icon(onPressed: c.connect, icon: const Icon(Icons.link), label: Text('Conectar con $store')),
          ),
        ] else ...[
          Text(
            s.lastSync == null
                ? 'Conectado. Se sincroniza al abrir la app.'
                : 'Última sincronización a las ${s.lastSync!.hour}:${s.lastSync!.minute.toString().padLeft(2, '0')}. Se leen los últimos 30 días.',
            style: muted,
          ),
          const SizedBox(height: 8),
          Align(
            alignment: Alignment.centerLeft,
            child: FilledButton.tonalIcon(
              onPressed: s.syncing ? null : () => c.sync(),
              icon: s.syncing ? const SizedBox(width: 16, height: 16, child: CircularProgressIndicator(strokeWidth: 2)) : const Icon(Icons.sync),
              label: const Text('Sincronizar'),
            ),
          ),
        ],
        if (s.message != null) ...[
          const SizedBox(height: 8),
          Text(s.message!, style: TextStyle(color: s.messageIsError ? cs.error : cs.onSurfaceVariant, fontSize: 13)),
        ],
      ]),
    );
  }
}

/// Actividades de los últimos 30 días que registró la pulsera.
class ActivitiesPanel extends ConsumerWidget {
  const ActivitiesPanel({super.key});

  static String _duration(Duration d) => d.inHours > 0 ? '${d.inHours} h ${(d.inMinutes % 60).toString().padLeft(2, '0')}' : '${d.inMinutes} min';

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return ref.watch(healthActivitiesProvider).when(
          loading: () => const SizedBox.shrink(),
          error: (e, _) => Padding(
            padding: const EdgeInsets.only(bottom: 16),
            child: Text('Actividades: ${apiMessage(e)}', style: TextStyle(color: cs.error)),
          ),
          data: (acts) => acts.isEmpty
              ? const SizedBox.shrink()
              : Padding(
                  padding: const EdgeInsets.only(bottom: 16),
                  child: Panel(
                    padding: const EdgeInsets.fromLTRB(12, 12, 12, 4),
                    child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                      Text('Actividades de la pulsera', style: t.textTheme.titleMedium),
                      Text('Últimos 30 días', style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      const SizedBox(height: 6),
                      for (final a in acts)
                        Padding(
                          padding: const EdgeInsets.symmetric(vertical: 6),
                          child: Row(crossAxisAlignment: CrossAxisAlignment.start, children: [
                            SizedBox(width: 64, child: Text(shortDate(a.start), style: t.textTheme.bodySmall)),
                            Expanded(
                              child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
                                Text(activityLabel(a.kind), style: t.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600)),
                                Text(
                                  [
                                    '${a.start.hour}:${a.start.minute.toString().padLeft(2, '0')}',
                                    _duration(a.duration),
                                    if (a.distanceM != null) '${fmtNum((a.distanceM! / 100).round() / 10)} km',
                                    if (a.kcal != null) '${a.kcal} kcal',
                                    if (a.source.isNotEmpty) a.source,
                                  ].join(' · '),
                                  style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                                ),
                              ]),
                            ),
                          ]),
                        ),
                    ]),
                  ),
                ),
        );
  }
}
