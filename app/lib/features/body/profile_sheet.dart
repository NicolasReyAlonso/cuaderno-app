import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../workout/exercise_card.dart' show fmtNum, shortDate;
import 'body_repository.dart';
import 'models.dart';

/// Punto de partida (fecha, peso y % de grasa) y objetivos diarios de kcal y proteína.
Future<bool?> showProfileSheet(BuildContext context, Profile profile) => showModalBottomSheet<bool>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _ProfileSheet(profile: profile),
    );

class _ProfileSheet extends ConsumerStatefulWidget {
  const _ProfileSheet({required this.profile});
  final Profile profile;

  @override
  ConsumerState<_ProfileSheet> createState() => _ProfileSheetState();
}

class _ProfileSheetState extends ConsumerState<_ProfileSheet> {
  late DateTime? _start = widget.profile.startDate;
  late final _weight = TextEditingController(text: _fmt(widget.profile.startWeightKg));
  late final _fat = TextEditingController(text: _fmt(widget.profile.startBodyFatPct));
  late final _kcal = TextEditingController(text: '${widget.profile.kcalTarget}');
  late final _protein = TextEditingController(text: '${widget.profile.proteinTargetG}');
  bool _saving = false;
  String? _error;

  static String _fmt(double? v) => v == null ? '' : fmtNum(v);

  @override
  void dispose() {
    for (final c in [_weight, _fat, _kcal, _protein]) {
      c.dispose();
    }
    super.dispose();
  }

  Future<void> _pickStart() async {
    final now = DateTime.now();
    final d = await showDatePicker(context: context, initialDate: _start ?? now, firstDate: DateTime(2024), lastDate: now);
    if (d != null) setState(() => _start = d);
  }

  Future<void> _save() async {
    final input = profileInput(
        startDate: _start, startWeight: _weight.text, startBodyFat: _fat.text, kcalTarget: _kcal.text, proteinTarget: _protein.text);
    if (input.error != null) {
      setState(() => _error = input.error);
      return;
    }
    setState(() => _saving = true);
    try {
      await ref.read(bodyRepositoryProvider).saveProfile(input.json!);
      if (mounted) Navigator.pop(context, true);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = apiMessage(e);
        });
      }
    }
  }

  Widget _num(TextEditingController c, String label, String suffix, {bool decimal = true}) => TextField(
        controller: c,
        keyboardType: TextInputType.numberWithOptions(decimal: decimal),
        decoration: InputDecoration(labelText: label, suffixText: suffix),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom),
      child: SafeArea(
        child: SingleChildScrollView(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Text('Punto de partida', style: t.textTheme.titleMedium),
            const SizedBox(height: 4),
            Text('Con el peso y la grasa del inicio se calcula tu masa magra, la grasa estimada y el peso para cada objetivo.',
                style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
            const SizedBox(height: 12),
            Align(
              alignment: Alignment.centerLeft,
              child: OutlinedButton.icon(
                onPressed: _pickStart,
                icon: const Icon(Icons.calendar_today, size: 16),
                label: Text(_start == null ? 'Fecha de inicio' : 'Inicio: ${shortDate(_start!)} ${_start!.year}'),
              ),
            ),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _num(_weight, 'Peso inicial', 'kg')),
              const SizedBox(width: 8),
              Expanded(child: _num(_fat, 'Grasa inicial', '%')),
            ]),
            const SizedBox(height: 20),
            Text('Objetivos diarios', style: t.textTheme.titleMedium),
            const SizedBox(height: 12),
            Row(children: [
              Expanded(child: _num(_kcal, 'Calorías', 'kcal', decimal: false)),
              const SizedBox(width: 8),
              Expanded(child: _num(_protein, 'Proteína', 'g', decimal: false)),
            ]),
            if (_error != null) ...[
              const SizedBox(height: 8),
              Text(_error!, style: TextStyle(color: cs.error)),
            ],
            const SizedBox(height: 16),
            FilledButton(
              onPressed: _saving ? null : _save,
              child: _saving
                  ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                  : const Text('Guardar'),
            ),
          ]),
        ),
      ),
    );
  }
}
