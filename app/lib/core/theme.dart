import 'package:flutter/material.dart';

/// Colores de los días: como los discos olímpicos (azul, rojo, amarillo, verde, gris).
const dayColors = {
  'blue': (Color(0xFF2160C4), Color(0xFF5B8FE8)),
  'red': (Color(0xFFC8332A), Color(0xFFE5594E)),
  'yellow': (Color(0xFFC99306), Color(0xFFE5B43A)),
  'green': (Color(0xFF2A8A4C), Color(0xFF4FB775)),
  'grey': (Color(0xFF7C8794), Color(0xFF9AA5B1)),
};

Color dayColor(BuildContext context, String key) {
  final pair = dayColors[key] ?? dayColors['grey']!;
  return Theme.of(context).brightness == Brightness.dark ? pair.$2 : pair.$1;
}

/// Colores de estado de las sugerencias: subir, repetir, mantener, nuevo.
({Color fg, Color bg}) hintColors(BuildContext context, String kind) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final cs = Theme.of(context).colorScheme;
  return switch (kind) {
    'up' => dark ? (fg: const Color(0xFF5FC585), bg: const Color(0xFF173323)) : (fg: const Color(0xFF23794A), bg: const Color(0xFFDDF0E4)),
    'rep' => (fg: cs.primary, bg: cs.primaryContainer),
    'hold' => dark ? (fg: const Color(0xFFE8A848), bg: const Color(0xFF382A12)) : (fg: const Color(0xFFA25F00), bg: const Color(0xFFF7E9CF)),
    _ => (fg: cs.onSurfaceVariant, bg: cs.surfaceContainerHighest),
  };
}

ThemeData buildTheme(Brightness b) {
  final scheme = ColorScheme.fromSeed(seedColor: const Color(0xFF1E5BC6), brightness: b);
  final base = ThemeData(colorScheme: scheme, useMaterial3: true, brightness: b);
  return base.copyWith(
    inputDecorationTheme: const InputDecorationTheme(border: OutlineInputBorder(), isDense: true),
  );
}

/// Recuadro con borde fino, para tarjetas de ejercicio y paneles.
class Panel extends StatelessWidget {
  const Panel({super.key, required this.child, this.highlight, this.padding = const EdgeInsets.all(12)});
  final Widget child;
  final Color? highlight;
  final EdgeInsets padding;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        color: cs.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: highlight ?? cs.outlineVariant, width: highlight == null ? 1 : 1.5),
      ),
      child: Padding(padding: padding, child: child),
    );
  }
}
