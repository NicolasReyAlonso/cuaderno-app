import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/theme.dart';
import '../body/body_repository.dart';
import '../body/models.dart';
import '../workout/exercise_card.dart' show fmtNum, shortDate;

String _kg(double v) => fmtNum((v * 10).round() / 10);

/// Frases de la guía que dependen de tus datos. Sin datos, la frase genérica.
class GuideNumbers {
  final String? pace; // «unos 0,5–0,9 kg ahora mismo»
  final String? goal25; // «unos 91,5 kg»
  final String? start; // «19 oct 2026: 99 kg y 30,7 % de grasa. Unos 30,4 kg de grasa y 68,6 kg de masa magra.»
  const GuideNumbers({this.pace, this.goal25, this.start});

  factory GuideNumbers.from(Profile? p, BodySummary? s) {
    final current = s?.currentWeight ?? p?.startWeightKg;
    final w = p?.startWeightKg, bf = p?.startBodyFatPct, d = p?.startDate;
    return GuideNumbers(
      pace: current == null ? null : 'unos ${_kg(current * 0.005)}–${_kg(current * 0.01)} kg ahora mismo',
      goal25: s?.goal25Weight == null ? null : 'unos ${_kg(s!.goal25Weight!)} kg',
      start: w == null || bf == null
          ? null
          : '${d == null ? '' : '${shortDate(d)} ${d.year}: '}${_kg(w)} kg y ${fmtNum(bf)} % de grasa. '
              'Unos ${_kg(w * bf / 100)} kg de grasa y ${_kg(w * (1 - bf / 100))} kg de masa magra.',
    );
  }
}

class GuidePage extends ConsumerWidget {
  const GuidePage({super.key});

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final n = GuideNumbers.from(ref.watch(profileProvider).valueOrNull, ref.watch(bodySummaryProvider).valueOrNull);
    return ListView(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
      children: [
        Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 720),
            child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
              const _Section(title: 'Cómo progresar', children: [
                _P.rich('Doble progresión. ', 'Cada ejercicio tiene un rango, por ejemplo 6–8. Con el mismo peso, suma repeticiones sesión a sesión. '
                    'Cuando hagas el máximo del rango en todas las series, sube el peso.'),
                _P.rich('Cuánto subir: ', '2,5 kg en los básicos (press, sentadilla, peso muerto, remos), 1–2 kg en aislamiento.'),
                _P.rich('Esfuerzo: ', 'termina cada serie a 1–2 repeticiones del fallo.'),
                _P.rich('Descansos: ', '2–3 min en los básicos, 60–90 s en el resto.'),
                _P('En déficit, mantener los pesos ya es ganar. Si en un ejercicio no puedes con el peso de la última vez, '
                    'no lo bajes de golpe: repite el mismo peso la próxima sesión.'),
              ]),
              _Section(title: 'Cuándo ajustar calorías', children: [
                _P.rich('Ritmo ideal: ', 'bajar entre un 0,5 % y un 1 % del peso por semana${n.pace == null ? '' : ' (${n.pace})'}.'),
                const _P.rich('Dos semanas seguidas sin bajar la media: ', 'quita 100–150 kcal o suma 2.000 pasos al día.'),
                const _P.rich('Más de un 1 % semanal varias semanas y la fuerza cae: ', 'sube 100–150 kcal.'),
                _P('Al llegar al 25 %${n.goal25 == null ? '' : ' (${n.goal25})'}, haz 1–2 semanas a mantenimiento (unas 2.500 kcal) '
                    'antes de seguir hacia el 20 %.'),
                const _P('Tu trabajo y las clases son sentado: apunta a 7.000–8.000 pasos diarios.'),
              ]),
              const _Section(title: 'Si una máquina está ocupada', children: [
                _P('En la pestaña Entreno, pulsa ⇄ Cambiar en el ejercicio y elige una alternativa. Se guarda con su propio historial, '
                    'y la próxima vez te propone la misma. Otras opciones de tu tabla:'),
                _P.rich('Pecho: ', 'fondos de pecho, press declinado, aperturas en banco, flexiones con apoyo cerrado.'),
                _P.rich('Espalda: ', 'remo con mancuerna en banco, remo con barra, dominadas asistidas, jalón a una mano, pullover en polea.'),
                _P.rich('Pierna: ', 'sentadilla en rack, sentadilla sumo, patada de glúteo, aductor en polea.'),
                _P.rich('Hombro: ', 'press militar en multipower, elevación lateral en polea, elevaciones frontales.'),
                _P.rich('Brazos: ', 'curl con barra, curl en polea, curl en banco inclinado, tríceps en polea con barra, patada de tríceps, '
                    'tras nuca en polea.'),
                _P.rich('Core: ', 'crunch, oblicuos en banco lumbar, giro ruso, bird dog, plancha tocando hombros, hiperextensiones.'),
              ]),
              _Section(title: 'Punto de partida', children: [
                _P(n.start ?? 'Pon tu peso y tu grasa del inicio en Peso → Punto de partida y objetivos, y aquí verás tu grasa y tu masa magra.'),
                const _P('La grasa estimada de este cuaderno supone que mantienes esa masa magra. Si te mides con báscula de bioimpedancia, '
                    'hazlo siempre en las mismas condiciones y fíate más de la tendencia del peso y la cintura.'),
                const _P.rich('Normas de la sala: ', 'toalla propia, limpiar la máquina tras usarla, nada de entrenar descalzo y dejar el material en su sitio.'),
              ]),
            ]),
          ),
        ),
      ],
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children});
  final String title;
  final List<Widget> children;

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.only(bottom: 16),
        child: Panel(
          padding: const EdgeInsets.fromLTRB(16, 14, 16, 6),
          child: Column(crossAxisAlignment: CrossAxisAlignment.stretch, children: [
            Semantics(header: true, child: Text(title, style: Theme.of(context).textTheme.titleMedium?.copyWith(fontWeight: FontWeight.w700))),
            const SizedBox(height: 8),
            ...children,
          ]),
        ),
      );
}

/// Un párrafo; con [lead] en negrita delante («Esfuerzo: termina…»).
class _P extends StatelessWidget {
  const _P(this.text) : lead = null;
  const _P.rich(this.lead, this.text);
  final String? lead;
  final String text;

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodyMedium?.copyWith(height: 1.45);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Text.rich(TextSpan(style: style, children: [
        if (lead != null) TextSpan(text: lead, style: const TextStyle(fontWeight: FontWeight.w700)),
        TextSpan(text: text),
      ])),
    );
  }
}
