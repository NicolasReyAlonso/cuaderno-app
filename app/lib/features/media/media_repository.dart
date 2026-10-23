import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:image_picker/image_picker.dart';

import '../../core/api.dart';
import '../workout/models.dart';

/// Mismos límites que el backend (services/media.py): así se avisa antes de subir.
const maxMediaPerExercise = 6;
const maxImageBytes = 10 * 1024 * 1024;
const maxVideoBytes = 50 * 1024 * 1024;

class MediaRepository {
  MediaRepository(this._dio);
  final Dio _dio;

  /// Sube un archivo elegido con image_picker. [onProgress] va de 0 a 1.
  Future<MediaItem> upload(String exerciseId, XFile file, {void Function(double)? onProgress}) async {
    // Bytes y no ruta: en web no hay ruta de archivo
    final form = FormData.fromMap({'file': MultipartFile.fromBytes(await file.readAsBytes(), filename: file.name)});
    final r = await _dio.post<Map<String, dynamic>>(
      '/exercises/$exerciseId/media',
      data: form,
      options: Options(sendTimeout: const Duration(minutes: 5), receiveTimeout: const Duration(minutes: 1)),
      onSendProgress: onProgress == null ? null : (sent, total) => total > 0 ? onProgress(sent / total) : null,
    );
    return MediaItem.fromJson(r.data!);
  }

  Future<void> delete(String mediaId) => _dio.delete<void>('/media/$mediaId');
}

final mediaRepositoryProvider = Provider<MediaRepository>((ref) => MediaRepository(ref.watch(dioProvider)));

/// Aviso antes de subir si el archivo ya se pasa del límite; null si vale.
String? tooBig(XFile file, int bytes) {
  final video = isVideoName(file.name) || (file.mimeType?.startsWith('video/') ?? false);
  if (video && bytes > maxVideoBytes) return '«${file.name}» pasa de 50 MB. Recórtalo o grábalo con menos calidad.';
  if (!video && bytes > maxImageBytes) return '«${file.name}» pasa de 10 MB. Prueba con una foto más pequeña.';
  return null;
}

bool isVideoName(String name) {
  final n = name.toLowerCase();
  return n.endsWith('.mp4') || n.endsWith('.mov') || n.endsWith('.m4v');
}
