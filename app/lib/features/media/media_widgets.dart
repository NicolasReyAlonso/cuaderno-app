import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:video_player/video_player.dart';

import '../../core/api.dart';
import '../figures/figure.dart' show kFigureH, kFigureW;
import '../workout/models.dart';
import '../workout/workout_repository.dart';
import 'media_repository.dart';

/// Miniatura cuadrada: la foto o el GIF, o un icono de vídeo (no generamos fotogramas).
class MediaThumb extends StatelessWidget {
  const MediaThumb({super.key, required this.item, this.size = 88});
  final MediaItem item;
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final placeholder = ColoredBox(
      color: cs.surfaceContainerHighest,
      child: Center(child: Icon(item.isVideo ? Icons.play_circle_outline : Icons.broken_image_outlined, color: cs.onSurfaceVariant)),
    );
    return ClipRRect(
      borderRadius: BorderRadius.circular(8),
      child: SizedBox.square(
        dimension: size,
        child: item.isVideo
            ? placeholder
            : Image.network(item.url, fit: BoxFit.cover, errorBuilder: (_, __, ___) => placeholder),
      ),
    );
  }
}

/// Primera foto del ejercicio (o un icono si es un vídeo); al tocarla se abren todas.
class MediaCover extends StatelessWidget {
  const MediaCover({super.key, required this.ex});
  final Exercise ex;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final first = ex.media.firstWhere((m) => !m.isVideo, orElse: () => ex.media.first);
    final n = ex.media.length;
    return Semantics(
      button: true,
      label: 'Ver cómo se hace ${ex.name}: $n ${n == 1 ? 'archivo' : 'archivos'}',
      child: InkWell(
        borderRadius: BorderRadius.circular(10),
        onTap: () => openMediaViewer(context, ex.name, ex.media, initial: ex.media.indexOf(first)),
        child: AspectRatio(
          aspectRatio: kFigureW / kFigureH,
          child: Stack(fit: StackFit.expand, children: [
            LayoutBuilder(builder: (_, c) => MediaThumb(item: first, size: c.maxWidth)),
            Positioned(
              right: 6,
              bottom: 6,
              child: DecoratedBox(
                decoration: BoxDecoration(color: cs.surface.withValues(alpha: 0.85), borderRadius: BorderRadius.circular(999)),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                  child: Row(mainAxisSize: MainAxisSize.min, children: [
                    Icon(ex.media.any((m) => m.isVideo) ? Icons.play_circle_outline : Icons.photo_outlined, size: 14, color: cs.onSurface),
                    const SizedBox(width: 4),
                    Text('$n', style: TextStyle(color: cs.onSurface, fontSize: 12)),
                  ]),
                ),
              ),
            ),
          ]),
        ),
      ),
    );
  }
}

/// Abre las fotos y vídeos a pantalla completa, empezando por [initial].
Future<void> openMediaViewer(BuildContext context, String title, List<MediaItem> items, {int initial = 0}) =>
    Navigator.of(context).push(MaterialPageRoute<void>(
      fullscreenDialog: true,
      builder: (_) => _MediaViewer(title: title, items: items, initial: initial),
    ));

class _MediaViewer extends StatefulWidget {
  const _MediaViewer({required this.title, required this.items, required this.initial});
  final String title;
  final List<MediaItem> items;
  final int initial;

  @override
  State<_MediaViewer> createState() => _MediaViewerState();
}

class _MediaViewerState extends State<_MediaViewer> {
  late final _pages = PageController(initialPage: widget.initial);
  late int _index = widget.initial;

  @override
  void dispose() {
    _pages.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final n = widget.items.length;
    return Scaffold(
      appBar: AppBar(title: Text(n > 1 ? '${widget.title} · ${_index + 1} de $n' : widget.title)),
      body: Stack(children: [
        PageView.builder(
          controller: _pages,
          itemCount: n,
          onPageChanged: (i) => setState(() => _index = i),
          itemBuilder: (_, i) {
            final item = widget.items[i];
            return item.isVideo
                ? _VideoView(key: ValueKey(item.id), url: item.url)
                : InteractiveViewer(
                    child: Center(
                      child: Image.network(item.url,
                          errorBuilder: (_, __, ___) =>
                              const Text('No se pudo cargar la foto. Comprueba la conexión con el servidor.', textAlign: TextAlign.center)),
                    ),
                  );
          },
        ),
        // Flechas para escritorio y web, donde no se desliza con el dedo
        if (n > 1) ...[
          if (_index > 0)
            Align(
              alignment: Alignment.centerLeft,
              child: IconButton.filledTonal(
                tooltip: 'Anterior',
                onPressed: () => _pages.previousPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut),
                icon: const Icon(Icons.chevron_left),
              ),
            ),
          if (_index < n - 1)
            Align(
              alignment: Alignment.centerRight,
              child: IconButton.filledTonal(
                tooltip: 'Siguiente',
                onPressed: () => _pages.nextPage(duration: const Duration(milliseconds: 200), curve: Curves.easeOut),
                icon: const Icon(Icons.chevron_right),
              ),
            ),
        ],
      ]),
    );
  }
}

/// Vídeo en bucle y sin sonido. Con «reducir movimiento» no arranca solo.
class _VideoView extends StatefulWidget {
  const _VideoView({super.key, required this.url});
  final String url;

  @override
  State<_VideoView> createState() => _VideoViewState();
}

class _VideoViewState extends State<_VideoView> {
  late final VideoPlayerController _c = VideoPlayerController.networkUrl(Uri.parse(widget.url));
  bool _ready = false, _failed = false;

  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<void> _init() async {
    try {
      await _c.initialize();
      await _c.setLooping(true);
      await _c.setVolume(0);
      if (!mounted) return;
      if (!(MediaQuery.maybeDisableAnimationsOf(context) ?? false)) await _c.play();
      setState(() => _ready = true);
    } catch (_) {
      if (mounted) setState(() => _failed = true);
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (_failed) {
      return const Center(
        child: Padding(
          padding: EdgeInsets.all(24),
          child: Text('No se pudo reproducir el vídeo. En web, los MOV del iPhone a veces no van: prueba con MP4.',
              textAlign: TextAlign.center),
        ),
      );
    }
    if (!_ready) return const Center(child: CircularProgressIndicator());
    return Column(children: [
      Expanded(
        child: Center(
          child: AspectRatio(
            aspectRatio: _c.value.aspectRatio,
            child: GestureDetector(
              onTap: () => setState(() => _c.value.isPlaying ? _c.pause() : _c.play()),
              child: VideoPlayer(_c),
            ),
          ),
        ),
      ),
      VideoProgressIndicator(_c, allowScrubbing: true, padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8)),
      Row(mainAxisAlignment: MainAxisAlignment.center, children: [
        IconButton(
          tooltip: _c.value.isPlaying ? 'Pausar' : 'Reproducir',
          onPressed: () => setState(() => _c.value.isPlaying ? _c.pause() : _c.play()),
          icon: Icon(_c.value.isPlaying ? Icons.pause : Icons.play_arrow),
        ),
        IconButton(
          tooltip: _c.value.volume == 0 ? 'Activar sonido' : 'Silenciar',
          onPressed: () => setState(() => _c.setVolume(_c.value.volume == 0 ? 1 : 0)),
          icon: Icon(_c.value.volume == 0 ? Icons.volume_off : Icons.volume_up),
        ),
      ]),
    ]);
  }
}

/// Hoja para ver, añadir y borrar las fotos y vídeos de un ejercicio propio.
Future<void> showMediaManager(BuildContext context, Exercise exercise) => showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      showDragHandle: true,
      builder: (_) => _MediaManager(exercise: exercise),
    );

class _MediaManager extends ConsumerStatefulWidget {
  const _MediaManager({required this.exercise});
  final Exercise exercise;

  @override
  ConsumerState<_MediaManager> createState() => _MediaManagerState();
}

class _MediaManagerState extends ConsumerState<_MediaManager> {
  final _picker = ImagePicker();
  late final List<MediaItem> _items = [...widget.exercise.media];
  String? _uploading;
  double? _progress;
  final List<String> _errors = [];

  int get _left => maxMediaPerExercise - _items.length;

  Future<void> _pick(Future<List<XFile>> Function() pick) async {
    setState(_errors.clear);
    final List<XFile> files;
    try {
      files = await pick();
    } catch (e) {
      setState(() => _errors.add('No se pudo abrir el selector: $e'));
      return;
    }
    if (files.length > _left) {
      _errors.add('Solo caben $_left más. Se suben las primeras.');
    }
    for (final f in files.take(_left)) {
      final problem = tooBig(f, await f.length());
      if (problem != null) {
        setState(() => _errors.add(problem));
        continue;
      }
      setState(() {
        _uploading = f.name;
        _progress = null;
      });
      try {
        final item = await ref.read(mediaRepositoryProvider).upload(widget.exercise.id, f,
            onProgress: (p) {
          if (mounted) setState(() => _progress = p);
        });
        _items.add(item);
        ref.invalidate(catalogProvider);
      } catch (e) {
        _errors.add('«${f.name}»: ${apiMessage(e)}');
      }
      if (!mounted) return;
    }
    setState(() => _uploading = null);
  }

  // Calidad 85 y 2000 px: el iPhone convierte las HEIC a JPG y las fotos pesan menos
  Future<List<XFile>> _gallery() async => _left == 1
      ? [if (await _picker.pickMedia(maxWidth: 2000, imageQuality: 85) case final f?) f]
      : _picker.pickMultipleMedia(maxWidth: 2000, imageQuality: 85, limit: _left);

  Future<List<XFile>> _photo() async =>
      [if (await _picker.pickImage(source: ImageSource.camera, maxWidth: 2000, imageQuality: 85) case final f?) f];

  Future<List<XFile>> _video() async =>
      [if (await _picker.pickVideo(source: ImageSource.camera, maxDuration: const Duration(seconds: 60)) case final f?) f];

  Future<void> _delete(MediaItem item) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: Text(item.isVideo ? '¿Borrar este vídeo?' : '¿Borrar esta foto?'),
        actions: [
          TextButton(onPressed: () => Navigator.pop(c, false), child: const Text('Cancelar')),
          FilledButton(onPressed: () => Navigator.pop(c, true), child: const Text('Borrar')),
        ],
      ),
    );
    if (ok != true) return;
    try {
      await ref.read(mediaRepositoryProvider).delete(item.id);
      ref.invalidate(catalogProvider);
      if (mounted) setState(() => _items.remove(item));
    } catch (e) {
      if (mounted) setState(() => _errors.add(apiMessage(e)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final t = Theme.of(context);
    final cs = t.colorScheme;
    final busy = _uploading != null;
    final camera = _picker.supportsImageSource(ImageSource.camera);
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 0, 16, 16),
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.stretch, children: [
          Text('Cómo se hace: ${widget.exercise.name}', style: t.textTheme.titleMedium),
          const SizedBox(height: 4),
          Text('Hasta $maxMediaPerExercise fotos, GIF o vídeos. Fotos hasta 10 MB y vídeos hasta 50 MB.',
              style: t.textTheme.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
          const SizedBox(height: 12),
          if (_items.isEmpty && !busy)
            Text('Todavía no hay ninguna.', style: t.textTheme.bodyMedium?.copyWith(color: cs.onSurfaceVariant)),
          Wrap(spacing: 8, runSpacing: 8, children: [
            for (final (i, item) in _items.indexed)
              Stack(children: [
                InkWell(
                  onTap: () => openMediaViewer(context, widget.exercise.name, _items, initial: i),
                  child: MediaThumb(item: item),
                ),
                Positioned(
                  top: 0,
                  right: 0,
                  child: IconButton.filledTonal(
                    tooltip: 'Borrar',
                    visualDensity: VisualDensity.compact,
                    iconSize: 16,
                    onPressed: busy ? null : () => _delete(item),
                    icon: const Icon(Icons.close),
                  ),
                ),
              ]),
          ]),
          if (busy) ...[
            const SizedBox(height: 12),
            Text('Subiendo «$_uploading»…', style: t.textTheme.bodySmall),
            const SizedBox(height: 4),
            LinearProgressIndicator(value: _progress),
          ],
          for (final e in _errors)
            Padding(padding: const EdgeInsets.only(top: 8), child: Text(e, style: TextStyle(color: cs.error))),
          const SizedBox(height: 12),
          Wrap(spacing: 8, runSpacing: 8, children: [
            FilledButton.tonalIcon(
              onPressed: busy || _left <= 0 ? null : () => _pick(_gallery),
              icon: const Icon(Icons.photo_library_outlined),
              label: const Text('Elegir fotos o vídeos'),
            ),
            if (camera) ...[
              OutlinedButton.icon(
                onPressed: busy || _left <= 0 ? null : () => _pick(_photo),
                icon: const Icon(Icons.photo_camera_outlined),
                label: const Text('Hacer foto'),
              ),
              OutlinedButton.icon(
                onPressed: busy || _left <= 0 ? null : () => _pick(_video),
                icon: const Icon(Icons.videocam_outlined),
                label: const Text('Grabar vídeo'),
              ),
            ],
          ]),
          if (_left <= 0)
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text('Ya tiene $maxMediaPerExercise. Borra alguna para añadir otra.', style: t.textTheme.bodySmall),
            ),
        ]),
      ),
    );
  }
}
