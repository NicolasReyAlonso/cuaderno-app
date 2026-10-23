import 'package:cuaderno/core/api.dart' show apiUrl;
import 'package:cuaderno/features/media/media_repository.dart';
import 'package:cuaderno/features/workout/models.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image_picker/image_picker.dart';

Map<String, dynamic> _exercise({List<Map<String, dynamic>>? media}) => {
      'id': 'u:abc',
      'name': 'Remo en máquina',
      'muscle_group': 'Espalda',
      'cue': '',
      'unit': 'reps',
      'load_mode': 'kg',
      'is_compound': false,
      'mine': true,
      'figure': {
        'a': {'hip': [100, 84], 't': 90, 'hand': [86, 90], 'foot': [93, 156]},
        'b': {'hip': [100, 84], 't': 90, 'hand': [44, 42], 'foot': [93, 156]},
      },
      if (media != null) 'media': media,
    };

void main() {
  test('las URL de la API se vuelven absolutas y conservan la firma', () {
    final e = Exercise.fromJson(_exercise(media: [
      {'id': 'm1', 'kind': 'video', 'content_type': 'video/mp4', 'size_bytes': 1200, 'url': '/media/m1?sig=abc'},
    ]));
    expect(e.mine, isTrue);
    expect(e.media.single.url, '$apiUrl/media/m1?sig=abc');
    expect(e.media.single.isVideo, isTrue);
  });

  test('un ejercicio del catálogo (sin campo media) no tiene fotos', () {
    expect(Exercise.fromJson(_exercise()).media, isEmpty);
  });

  test('tooBig avisa con los mismos límites que el servidor', () {
    XFile f(String name) => XFile(name); // como las del selector: con ruta, no se lee el archivo
    expect(tooBig(f('foto.jpg'), maxImageBytes), isNull);
    expect(tooBig(f('foto.jpg'), maxImageBytes + 1), contains('10 MB'));
    expect(tooBig(f('IMG_0001.MOV'), 30 * 1024 * 1024), isNull);
    expect(tooBig(f('clip.mp4'), maxVideoBytes + 1), contains('50 MB'));
  });
}
