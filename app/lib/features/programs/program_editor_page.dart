import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/theme.dart';
import '../figures/figure_view.dart';
import '../media/media_widgets.dart';
import '../workout/models.dart';
import '../workout/workout_repository.dart';
import 'models.dart';
import 'programs_repository.dart';

const _weekdayNames = ['Lunes', 'Martes', 'Miércoles', 'Jueves', 'Viernes', 'Sábado', 'Domingo'];

/// Editor de plan: semanas → días → huecos. programId == null → plan nuevo.
/// Las plantillas se abren en solo lectura con la opción de duplicarlas.
class ProgramEditorPage extends ConsumerStatefulWidget {
  const ProgramEditorPage({super.key, this.programId});
  final String? programId;

  @override
  ConsumerState<ProgramEditorPage> createState() => _ProgramEditorPageState();
}

class _ProgramEditorPageState extends ConsumerState<ProgramEditorPage> {
  PlanDraft? _plan;
  String? _loadError;
  int _week = 1;
  bool _dirty = false, _saving = false;
  String? _message;

  @override
  void initState() {
    super.initState();
    if (widget.programId == null) {
      _plan = PlanDraft()..addDay(1, 'Día 1');
    } else {
      _load(widget.programId!);
    }
  }

  Future<void> _load(String id) async {
    setState(() => _loadError = null);
    try {
      final p = await ref.read(programsRepositoryProvider).get(id);
      if (mounted) setState(() => _plan = p);
    } catch (e) {
      if (mounted) setState(() => _loadError = apiMessage(e));
    }
  }

  void _edit(VoidCallback change) => setState(() {
        change();
        _dirty = true;
        _message = null;
      });

  Future<bool> _confirm(String title, String text, String ok) async =>
      await showDialog<bool>(
        context: context,
        builder: (c) => AlertDialog(
          title: Text(title),
          content: Text(text),
          actions: [
            TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
            FilledButton(onPressed: () => Navigator.pop(c, true), child: Text(ok)),
          ],
        ),
      ) ==
      true;

  Future<void> _setWeeks(PlanDraft plan, int n) async {
    final lost = plan.daysLostWith(n);
    if (lost > 0 &&
        !await _confirm('¿Quitar semanas?', 'Se borrarán $lost día${lost == 1 ? '' : 's'} de las semanas que sobran.', 'Quitar')) {
      return;
    }
    _edit(() {
      plan.setWeeks(n);
      if (_week > n) _week = n;
    });
  }

  Future<void> _copyWeek(PlanDraft plan, int from) async {
    if (plan.daysOf(_week).isNotEmpty &&
        !await _confirm('¿Copiar la semana $from?', 'Los días de la semana $_week se sustituyen por los de la semana $from.', 'Copiar')) {
      return;
    }
    _edit(() => plan.copyWeek(from, _week));
  }

  Future<void> _save(PlanDraft plan) async {
    final problem = plan.problem();
    if (problem != null) {
      setState(() => _message = problem);
      return;
    }
    setState(() => _saving = true);
    try {
      final saved = await ref.read(programsRepositoryProvider).save(plan);
      refreshAfterPlanChange(ref);
      if (!mounted) return;
      setState(() {
        _plan = saved;
        _dirty = false;
        _saving = false;
      });
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(content: Text('Plan guardado.')));
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _message = apiMessage(e);
        });
      }
    }
  }

  Future<void> _duplicate(PlanDraft plan) async {
    try {
      final copy = await ref.read(programsRepositoryProvider).duplicate(plan.id!);
      refreshAfterPlanChange(ref);
      if (mounted) {
        setState(() {
          _plan = copy;
          _dirty = false;
        });
      }
    } catch (e) {
      if (mounted) setState(() => _message = apiMessage(e));
    }
  }

  /// Elige un ejercicio del catálogo o crea uno propio. Devuelve su id.
  Future<String?> _pickExercise(Map<String, Exercise> exercises, Set<String> taken) => showModalBottomSheet<String>(
        context: context,
        isScrollControlled: true,
        showDragHandle: true,
        builder: (c) => _ExercisePicker(exercises: exercises, taken: taken, onCreate: () => _createExercise(c)),
      );

  Future<void> _createExercise(BuildContext sheet) async {
    final created = await showDialog<Exercise>(context: sheet, builder: (_) => const _NewExerciseDialog());
    if (created == null) return;
    ref.invalidate(catalogProvider);
    if (sheet.mounted) Navigator.pop(sheet, created.id);
    // Recién creado: se ofrece añadir fotos o vídeos de cómo se hace (se puede cerrar sin añadir)
    if (mounted) await showMediaManager(context, created);
  }

  @override
  Widget build(BuildContext context) {
    final plan = _plan;
    final title = widget.programId == null && plan?.id == null
        ? 'Nuevo plan'
        : (plan?.mine ?? true)
            ? 'Editar plan'
            : 'Plantilla';
    return PopScope(
      canPop: !_dirty,
      onPopInvokedWithResult: (didPop, _) async {
        if (didPop) return;
        if (await _confirm('¿Salir sin guardar?', 'Perderás los cambios de este plan.', 'Salir') && context.mounted) {
          setState(() => _dirty = false);
          Navigator.pop(context);
        }
      },
      child: Scaffold(
        appBar: AppBar(title: Text(title)),
        body: plan == null
            ? Center(
                child: _loadError == null
                    ? const CircularProgressIndicator()
                    : Column(mainAxisSize: MainAxisSize.min, children: [
                        Text(_loadError!, textAlign: TextAlign.center),
                        const SizedBox(height: 12),
                        FilledButton.tonal(onPressed: () => _load(widget.programId!), child: const Text('Reintentar')),
                      ]),
              )
            : ref.watch(catalogProvider).when(
                  loading: () => const Center(child: CircularProgressIndicator()),
                  error: (e, _) => Center(child: Text(apiMessage(e))),
                  data: (cat) => _body(context, plan, cat.exercises),
                ),
        bottomNavigationBar: plan == null ? null : _bottomBar(context, plan),
      ),
    );
  }

  Widget _body(BuildContext context, PlanDraft plan, Map<String, Exercise> exercises) {
    final t = Theme.of(context);
    final days = plan.daysOf(_week);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 820),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              if (!plan.mine) ...[
                Panel(
                  child: Text('Es una plantilla: no se cambia. Duplícala para tener tu propia copia y editarla.',
                      style: t.textTheme.bodyMedium),
                ),
                const SizedBox(height: 16),
              ],
              AbsorbPointer(
                absorbing: !plan.mine,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  TextFormField(
                    key: ValueKey('name-${plan.id}'),
                    initialValue: plan.name,
                    maxLength: 120,
                    decoration: const InputDecoration(labelText: 'Nombre del plan', counterText: ''),
                    onChanged: (v) => _edit(() => plan.name = v),
                  ),
                  const SizedBox(height: 16),
                  Text('Semanas que se repiten', style: t.textTheme.labelLarge),
                  const SizedBox(height: 6),
                  Align(
                    alignment: Alignment.centerLeft,
                    child: SegmentedButton<int>(
                      showSelectedIcon: false,
                      segments: [for (var w = 1; w <= maxWeeks; w++) ButtonSegment(value: w, label: Text('$w'))],
                      selected: {plan.weeks},
                      onSelectionChanged: (s) => _setWeeks(plan, s.first),
                    ),
                  ),
                ]),
              ),
              if (plan.weeks > 1) ...[
                const SizedBox(height: 20),
                Wrap(spacing: 12, runSpacing: 8, crossAxisAlignment: WrapCrossAlignment.center, children: [
                  SegmentedButton<int>(
                    showSelectedIcon: false,
                    segments: [for (var w = 1; w <= plan.weeks; w++) ButtonSegment(value: w, label: Text('Semana $w'))],
                    selected: {_week},
                    onSelectionChanged: (s) => setState(() => _week = s.first),
                  ),
                  if (plan.mine)
                    MenuAnchor(
                      builder: (context, c, _) => TextButton.icon(
                        onPressed: () => c.isOpen ? c.close() : c.open(),
                        icon: const Icon(Icons.copy_all, size: 18),
                        label: const Text('Copiar de otra semana'),
                      ),
                      menuChildren: [
                        for (var w = 1; w <= plan.weeks; w++)
                          if (w != _week) MenuItemButton(onPressed: () => _copyWeek(plan, w), child: Text('Semana $w')),
                      ],
                    ),
                ]),
              ],
              const SizedBox(height: 16),
              if (days.isEmpty)
                Padding(
                  padding: const EdgeInsets.symmetric(vertical: 24),
                  child: Text(plan.weeks > 1 ? 'La semana $_week no tiene días todavía.' : 'El plan no tiene días todavía.',
                      textAlign: TextAlign.center, style: t.textTheme.bodyMedium?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ),
              AbsorbPointer(
                absorbing: !plan.mine,
                child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
                  for (final d in days) ...[
                    _DayEditor(
                      key: ObjectKey(d),
                      day: d,
                      plan: plan,
                      exercises: exercises,
                      readOnly: !plan.mine,
                      onEdit: _edit,
                      onPickExercise: (taken) => _pickExercise(exercises, taken),
                      onDelete: () async {
                        if (await _confirm('¿Borrar «${d.name}»?', 'Se quita el día con sus ejercicios.', 'Borrar')) {
                          _edit(() => plan.days.remove(d));
                        }
                      },
                    ),
                    const SizedBox(height: 12),
                  ],
                  if (plan.mine)
                    OutlinedButton.icon(
                      onPressed: () => _edit(() => plan.addDay(_week, 'Día ${days.length + 1}')),
                      icon: const Icon(Icons.add),
                      label: const Text('Añadir día'),
                    ),
                ]),
              ),
            ]),
          ),
        ),
      ],
    );
  }

  Widget _bottomBar(BuildContext context, PlanDraft plan) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      elevation: 3,
      child: SafeArea(
        top: false,
        child: Padding(
          padding: const EdgeInsets.fromLTRB(16, 10, 16, 10),
          child: Row(children: [
            if (plan.mine)
              FilledButton(
                onPressed: _saving ? null : () => _save(plan),
                child: _saving
                    ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
                    : const Text('Guardar plan'),
              )
            else
              FilledButton.icon(onPressed: () => _duplicate(plan), icon: const Icon(Icons.copy), label: const Text('Duplicar')),
            const SizedBox(width: 12),
            Expanded(
              child: Text(
                _message ?? (_dirty ? 'Tienes cambios sin guardar.' : 'Los cambios valen para las próximas sesiones.'),
                style: TextStyle(color: _message != null ? cs.error : cs.onSurfaceVariant, fontSize: 13),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

class _DayEditor extends StatelessWidget {
  const _DayEditor({
    super.key,
    required this.day,
    required this.plan,
    required this.exercises,
    required this.readOnly,
    required this.onEdit,
    required this.onPickExercise,
    required this.onDelete,
  });
  final DayDraft day;
  final PlanDraft plan;
  final Map<String, Exercise> exercises;
  final bool readOnly;
  final void Function(VoidCallback) onEdit;
  final Future<String?> Function(Set<String> taken) onPickExercise;
  final VoidCallback onDelete;

  Future<void> _add() async {
    final id = await onPickExercise({for (final s in day.slots) s.exerciseId});
    if (id != null) onEdit(() => day.slots.add(SlotDraftData(exerciseId: id, rest: '2 min')));
  }

  Future<void> _change(SlotDraftData s) async {
    final id = await onPickExercise({
      for (final o in day.slots)
        if (o != s) o.exerciseId
    });
    if (id != null) onEdit(() => s.exerciseId = id);
  }

  void _move(int i, int by) => onEdit(() => day.slots.insert(i + by, day.slots.removeAt(i)));

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final accent = dayColor(context, day.color);
    final usedWeekdays = {
      for (final o in plan.daysOf(day.week))
        if (o != day && o.weekday != null) o.weekday!
    };
    return Panel(
      highlight: accent,
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: TextFormField(
              initialValue: day.name,
              maxLength: 80,
              decoration: const InputDecoration(labelText: 'Nombre del día', counterText: ''),
              onChanged: (v) => onEdit(() => day.name = v),
            ),
          ),
          const SizedBox(width: 8),
          SizedBox(
            width: 150,
            child: DropdownButtonFormField<int?>(
              // initialValue no existe en Flutter 3.27, el mínimo del pubspec
              // ignore: deprecated_member_use
              value: day.weekday,
              decoration: const InputDecoration(labelText: 'Día de la semana'),
              items: [
                const DropdownMenuItem(value: null, child: Text('Sin día fijo')),
                for (var w = 1; w <= 7; w++)
                  if (w == day.weekday || !usedWeekdays.contains(w)) DropdownMenuItem(value: w, child: Text(_weekdayNames[w - 1])),
              ],
              onChanged: (v) => onEdit(() => day.weekday = v),
            ),
          ),
          if (!readOnly) IconButton(tooltip: 'Borrar día', onPressed: onDelete, icon: const Icon(Icons.delete_outline)),
        ]),
        const SizedBox(height: 10),
        TextFormField(
          initialValue: day.focus,
          maxLength: 160,
          decoration: const InputDecoration(labelText: 'Enfoque (opcional)', counterText: ''),
          onChanged: (v) => onEdit(() => day.focus = v),
        ),
        const SizedBox(height: 10),
        Wrap(spacing: 6, children: [
          for (final c in dayColors.keys)
            ChoiceChip(
              selected: day.color == c,
              onSelected: (_) => onEdit(() => day.color = c),
              label: CircleAvatar(backgroundColor: dayColor(context, c), radius: 7),
              tooltip: c,
            ),
        ]),
        const SizedBox(height: 12),
        for (var i = 0; i < day.slots.length; i++)
          _SlotRow(
            key: ObjectKey(day.slots[i]),
            slot: day.slots[i],
            exercise: exercises[day.slots[i].exerciseId],
            readOnly: readOnly,
            onEdit: onEdit,
            onChange: () => _change(day.slots[i]),
            onUp: i > 0 ? () => _move(i, -1) : null,
            onDown: i < day.slots.length - 1 ? () => _move(i, 1) : null,
            onRemove: () => onEdit(() => day.slots.removeAt(i)),
          ),
        if (day.slots.isEmpty) Text('Sin ejercicios.', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
        if (!readOnly)
          Align(
            alignment: Alignment.centerLeft,
            child: TextButton.icon(onPressed: _add, icon: const Icon(Icons.add), label: const Text('Añadir ejercicio')),
          ),
      ]),
    );
  }
}

class _SlotRow extends StatelessWidget {
  const _SlotRow({
    super.key,
    required this.slot,
    required this.exercise,
    required this.readOnly,
    required this.onEdit,
    required this.onChange,
    required this.onUp,
    required this.onDown,
    required this.onRemove,
  });
  final SlotDraftData slot;
  final Exercise? exercise;
  final bool readOnly;
  final void Function(VoidCallback) onEdit;
  final VoidCallback onChange, onRemove;
  final VoidCallback? onUp, onDown;

  Widget _int(String label, int value, void Function(int) set) => SizedBox(
        width: 72,
        child: TextFormField(
          initialValue: value > 0 ? '$value' : '',
          keyboardType: TextInputType.number,
          inputFormatters: [FilteringTextInputFormatter.digitsOnly, LengthLimitingTextInputFormatter(3)],
          decoration: InputDecoration(labelText: label),
          onChanged: (v) => onEdit(() => set(int.tryParse(v) ?? 0)), // 0 = vacío: lo avisa PlanDraft.problem()
        ),
      );

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final unit = exercise?.isSeconds == true ? 'Seg.' : 'Reps';
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
        Row(children: [
          Expanded(
            child: InkWell(
              onTap: readOnly ? null : onChange,
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 6),
                child: Text.rich(TextSpan(children: [
                  TextSpan(text: exercise?.name ?? slot.exerciseId, style: t.textTheme.titleSmall),
                  if (exercise != null)
                    TextSpan(
                        text: '  ${exercise!.muscleGroup}', style: t.textTheme.bodySmall?.copyWith(color: t.colorScheme.onSurfaceVariant)),
                ])),
              ),
            ),
          ),
          if (exercise?.mine ?? false)
            IconButton(
              tooltip: exercise!.media.isEmpty ? 'Añadir fotos o vídeos' : 'Fotos y vídeos (${exercise!.media.length})',
              visualDensity: VisualDensity.compact,
              onPressed: () => showMediaManager(context, exercise!),
              icon: Badge(
                isLabelVisible: exercise!.media.isNotEmpty,
                label: Text('${exercise!.media.length}'),
                child: const Icon(Icons.photo_library_outlined, size: 18),
              ),
            ),
          if (!readOnly) ...[
            IconButton(
                tooltip: 'Subir', visualDensity: VisualDensity.compact, onPressed: onUp, icon: const Icon(Icons.arrow_upward, size: 18)),
            IconButton(
                tooltip: 'Bajar',
                visualDensity: VisualDensity.compact,
                onPressed: onDown,
                icon: const Icon(Icons.arrow_downward, size: 18)),
            IconButton(
                tooltip: 'Quitar', visualDensity: VisualDensity.compact, onPressed: onRemove, icon: const Icon(Icons.close, size: 18)),
          ],
        ]),
        Wrap(spacing: 8, runSpacing: 8, children: [
          _int('Series', slot.sets, (v) => slot.sets = v),
          _int('$unit mín.', slot.repMin, (v) => slot.repMin = v),
          _int('$unit máx.', slot.repMax, (v) => slot.repMax = v),
          SizedBox(
            width: 110,
            child: TextFormField(
              initialValue: slot.rest,
              maxLength: 20,
              decoration: const InputDecoration(labelText: 'Descanso', counterText: ''),
              onChanged: (v) => onEdit(() => slot.rest = v),
            ),
          ),
        ]),
      ]),
    );
  }
}

class _ExercisePicker extends StatefulWidget {
  const _ExercisePicker({required this.exercises, required this.taken, required this.onCreate});
  final Map<String, Exercise> exercises;
  final Set<String> taken;
  final VoidCallback onCreate;

  @override
  State<_ExercisePicker> createState() => _ExercisePickerState();
}

class _ExercisePickerState extends State<_ExercisePicker> {
  String _q = '';
  String? _open; // ejercicio con la vista previa desplegada

  @override
  Widget build(BuildContext context) {
    final q = _q.trim().toLowerCase();
    final list = widget.exercises.values
        .where((e) => !widget.taken.contains(e.id))
        .where((e) => q.isEmpty || e.name.toLowerCase().contains(q) || e.muscleGroup.toLowerCase().contains(q))
        .toList()
      ..sort((a, b) => a.mine != b.mine ? (a.mine ? -1 : 1) : a.name.compareTo(b.name));
    return Padding(
      padding: EdgeInsets.only(bottom: MediaQuery.viewInsetsOf(context).bottom), // sube sobre el teclado
      child: SafeArea(
        child: SizedBox(
          height: MediaQuery.sizeOf(context).height * 0.75,
          child: Column(children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
              child: TextField(
                autofocus: true,
                decoration: const InputDecoration(prefixIcon: Icon(Icons.search), hintText: 'Buscar por nombre o músculo'),
                onChanged: (v) => setState(() => _q = v),
              ),
            ),
            ListTile(leading: const Icon(Icons.add), title: const Text('Crear ejercicio propio'), onTap: widget.onCreate),
            const Divider(height: 1),
            Expanded(
              child: list.isEmpty
                  ? const Center(child: Text('Ningún ejercicio coincide. Prueba con otra palabra o crea uno propio.'))
                  : ListView.builder(
                      itemCount: list.length,
                      itemBuilder: (_, i) => _PickerRow(
                        key: ValueKey(list[i].id),
                        exercise: list[i],
                        open: _open == list[i].id,
                        onToggle: () => setState(() => _open = _open == list[i].id ? null : list[i].id),
                        onPick: () => Navigator.pop(context, list[i].id),
                      ),
                    ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Fila del selector: miniatura quieta; al tocarla, vista previa con la figura animada
/// (o las fotos y vídeos propios) y la técnica. El «+» elige sin abrir nada.
class _PickerRow extends StatelessWidget {
  const _PickerRow({super.key, required this.exercise, required this.open, required this.onToggle, required this.onPick});
  final Exercise exercise;
  final bool open;
  final VoidCallback onToggle, onPick;

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final e = exercise;
    final hasMedia = e.media.isNotEmpty;
    final thumb = ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox(
        width: 64,
        child: hasMedia
            ? AspectRatio(aspectRatio: 64 / 54, child: LayoutBuilder(builder: (_, c) => MediaThumb(item: e.media.first, size: c.maxWidth)))
            : ColoredBox(color: cs.surfaceContainerHighest, child: StillFigure(spec: e.figure)),
      ),
    );
    final tags = [
      e.isSeconds ? 'Segundos' : 'Repeticiones',
      e.isExtraLoad ? 'Peso corporal o lastre' : 'Con carga',
      e.isCompound ? 'Básico' : 'Aislamiento',
    ];
    return Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
      ListTile(
        leading: thumb,
        title: Text(e.name),
        subtitle: Text(e.mine ? '${e.muscleGroup} · propio' : e.muscleGroup),
        selected: open,
        onTap: onToggle,
        trailing: IconButton(tooltip: 'Elegir ${e.name}', onPressed: onPick, icon: const Icon(Icons.add_circle_outline)),
      ),
      if (open)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
          child: LayoutBuilder(builder: (context, c) {
            final visual = SizedBox(
              width: c.maxWidth < 420 ? 200 : 220,
              child: hasMedia
                  ? MediaCover(ex: e)
                  : DecoratedBox(
                      decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(10)),
                      child: ClipRRect(borderRadius: BorderRadius.circular(10), child: AnimatedFigure(spec: e.figure)),
                    ),
            );
            final info = Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              Wrap(spacing: 6, runSpacing: 6, children: [
                for (final tag in tags)
                  DecoratedBox(
                    decoration: BoxDecoration(color: cs.surfaceContainerHighest, borderRadius: BorderRadius.circular(999)),
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                      child: Text(tag, style: t.textTheme.labelSmall?.copyWith(color: cs.onSurfaceVariant)),
                    ),
                  ),
              ]),
              const SizedBox(height: 8),
              Text(e.cue.isEmpty ? 'Sin indicaciones de técnica.' : e.cue,
                  style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
              const SizedBox(height: 10),
              FilledButton.icon(onPressed: onPick, icon: const Icon(Icons.add), label: const Text('Elegir')),
            ]);
            return c.maxWidth < 420
                ? Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [Center(child: visual), const SizedBox(height: 10), info])
                : Row(crossAxisAlignment: CrossAxisAlignment.start, children: [visual, const SizedBox(width: 14), Expanded(child: info)]);
          }),
        ),
    ]);
  }
}

class _NewExerciseDialog extends ConsumerStatefulWidget {
  const _NewExerciseDialog();

  @override
  ConsumerState<_NewExerciseDialog> createState() => _NewExerciseDialogState();
}

class _NewExerciseDialogState extends ConsumerState<_NewExerciseDialog> {
  final _name = TextEditingController(), _muscle = TextEditingController();
  String _unit = 'reps', _load = 'kg';
  bool _compound = false, _saving = false;
  String? _error;

  @override
  void dispose() {
    _name.dispose();
    _muscle.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    if (_name.text.trim().isEmpty || _muscle.text.trim().isEmpty) {
      setState(() => _error = 'Pon el nombre y el grupo muscular.');
      return;
    }
    setState(() => _saving = true);
    try {
      final e = await ref
          .read(programsRepositoryProvider)
          .createExercise(name: _name.text, muscleGroup: _muscle.text, unit: _unit, loadMode: _load, isCompound: _compound);
      if (mounted) Navigator.pop(context, e);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = apiMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) => AlertDialog(
        title: const Text('Ejercicio propio'),
        content: SingleChildScrollView(
          child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            TextField(
                controller: _name,
                autofocus: true,
                maxLength: 160,
                decoration: const InputDecoration(labelText: 'Nombre', counterText: '')),
            const SizedBox(height: 12),
            TextField(
                controller: _muscle,
                maxLength: 80,
                decoration: const InputDecoration(labelText: 'Grupo muscular', hintText: 'Espalda', counterText: '')),
            const SizedBox(height: 12),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'reps', label: Text('Repeticiones')),
                ButtonSegment(value: 'seconds', label: Text('Segundos'))
              ],
              selected: {_unit},
              onSelectionChanged: (s) => setState(() => _unit = s.first),
            ),
            const SizedBox(height: 8),
            SegmentedButton<String>(
              showSelectedIcon: false,
              segments: const [
                ButtonSegment(value: 'kg', label: Text('Con carga')),
                ButtonSegment(value: 'extra', label: Text('Peso corporal'))
              ],
              selected: {_load},
              onSelectionChanged: (s) => setState(() => _load = s.first),
            ),
            SwitchListTile(
              contentPadding: EdgeInsets.zero,
              title: const Text('Ejercicio básico'),
              subtitle: const Text('Sube de 2,5 kg en 2,5 kg'),
              value: _compound,
              onChanged: (v) => setState(() => _compound = v),
            ),
            if (_error != null) Text(_error!, style: TextStyle(color: Theme.of(context).colorScheme.error)),
          ]),
        ),
        actions: [
          TextButton(onPressed: () => Navigator.pop(context), child: const Text('Cancelar')),
          FilledButton(onPressed: _saving ? null : _create, child: const Text('Crear')),
        ],
      );
}
