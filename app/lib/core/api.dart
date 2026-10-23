import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';

/// URL del backend. Cámbiala al compilar:
///   flutter run --dart-define=API_URL=http://10.0.2.2:8000   (emulador Android)
const apiUrl = String.fromEnvironment('API_URL', defaultValue: 'http://localhost:8000');

class TokenStore {
  // En macOS el llavero "data protection" exige firmar la app con un equipo de
  // desarrollo (error -34018); el llavero clásico funciona sin firma.
  TokenStore([FlutterSecureStorage? storage])
      : _s = storage ?? const FlutterSecureStorage(mOptions: MacOsOptions(useDataProtectionKeyChain: false));
  final FlutterSecureStorage _s;
  static const _key = 'access_token';
  String? _cache;

  Future<String?> read() async => _cache ??= await _s.read(key: _key);
  Future<void> write(String token) async {
    _cache = token;
    await _s.write(key: _key, value: token);
  }

  Future<void> clear() async {
    _cache = null;
    await _s.delete(key: _key);
  }
}

final tokenStoreProvider = Provider<TokenStore>((ref) => TokenStore());

/// Se dispara cuando el servidor responde 401: la sesión ha caducado.
final unauthorizedProvider = StateProvider<int>((ref) => 0);

final dioProvider = Provider<Dio>((ref) {
  final store = ref.watch(tokenStoreProvider);
  final dio = Dio(BaseOptions(baseUrl: apiUrl, connectTimeout: const Duration(seconds: 10), receiveTimeout: const Duration(seconds: 20)));
  dio.interceptors.add(InterceptorsWrapper(
    onRequest: (options, handler) async {
      final t = await store.read();
      if (t != null) options.headers['Authorization'] = 'Bearer $t';
      handler.next(options);
    },
    onError: (e, handler) {
      if (e.response?.statusCode == 401 && !e.requestOptions.path.startsWith('/auth/')) {
        ref.read(unauthorizedProvider.notifier).state++;
      }
      handler.next(e);
    },
  ));
  return dio;
});

/// Mensaje legible a partir de un error del backend.
String apiMessage(Object error) {
  if (error is DioException) {
    final detail = error.response?.data is Map ? (error.response!.data as Map)['detail'] : null;
    if (detail is String) return detail;
    if (detail is List && detail.isNotEmpty) {
      final first = detail.first;
      if (first is Map && first['msg'] != null) return 'Revisa los datos: ${first['msg']}';
    }
    return switch (error.type) {
      DioExceptionType.connectionTimeout || DioExceptionType.connectionError =>
        'No hay conexión con el servidor ($apiUrl). Comprueba que está encendido.',
      DioExceptionType.receiveTimeout => 'El servidor tarda demasiado en responder. Vuelve a intentarlo.',
      _ => 'Algo ha fallado (${error.response?.statusCode ?? 'sin respuesta'}). Vuelve a intentarlo.',
    };
  }
  return error.toString();
}
