import 'dart:typed_data';

import 'package:cuaderno/core/api.dart';
import 'package:cuaderno/core/local/local_db.dart';
import 'package:cuaderno/core/local/sync_controller.dart';
import 'package:cuaderno/features/auth/auth_controller.dart';
import 'package:dio/dio.dart';
import 'package:drift/drift.dart' show driftRuntimeOptions;
import 'package:drift/native.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';
import 'package:flutter_test/flutter_test.dart';

class _MemoryTokens extends TokenStore {
  _MemoryTokens(this.token);
  String? token;

  @override
  Future<String?> read() async => token;
  @override
  Future<void> write(String t) async => token = t;
  @override
  Future<void> clear() async => token = null;
}

/// Servidor de mentira: DELETE /me con la contraseña buena responde 204; con otra, 403.
class _Adapter implements HttpClientAdapter {
  final requests = <RequestOptions>[];

  @override
  Future<ResponseBody> fetch(RequestOptions options, Stream<Uint8List>? requestStream, Future<void>? cancelFuture) async {
    requests.add(options);
    final ok = (options.data as Map)['password'] == 'contraseña-larga';
    if (ok) return ResponseBody.fromString('', 204);
    return ResponseBody.fromString('{"detail":"La contraseña no es correcta."}', 403, headers: {
      Headers.contentTypeHeader: [Headers.jsonContentType],
    });
  }

  @override
  void close({bool force = false}) {}
}

void main() {
  driftRuntimeOptions.dontWarnAboutMultipleDatabases = true;
  late LocalDb db;
  late _MemoryTokens tokens;
  late _Adapter adapter;
  late ProviderContainer container;

  setUp(() async {
    db = LocalDb(NativeDatabase.memory());
    await db.setMeta('user_id', 'abc');
    await db.setMeta('cursor', '7');
    tokens = _MemoryTokens('token');
    adapter = _Adapter();
    container = ProviderContainer(overrides: [
      localDbProvider.overrideWithValue(db),
      tokenStoreProvider.overrideWithValue(tokens),
      dioProvider.overrideWith((ref) => Dio(BaseOptions(baseUrl: 'http://test'))..httpClientAdapter = adapter),
    ]);
    addTearDown(container.dispose);
    await container.read(authProvider.future);
  });

  test('wrong password: error, and the session and local data stay', () async {
    expect(container.read(authProvider).value, isTrue);
    await expectLater(container.read(authProvider.notifier).deleteAccount('otra'), throwsA(isA<DioException>()));
    expect(tokens.token, 'token');
    expect(container.read(authProvider).value, isTrue);
    expect(await db.readMeta('user_id'), 'abc');
  });

  test('deleting the account sends the password, clears the token and empties the local database', () async {
    await container.read(authProvider.notifier).deleteAccount('contraseña-larga');
    expect(adapter.requests.single.method, 'DELETE');
    expect(adapter.requests.single.path, '/me');
    expect(tokens.token, isNull);
    expect(container.read(authProvider).value, isFalse);
    expect(await db.readMeta('user_id'), isNull);
    expect(await db.readMeta('cursor'), isNull);
  });
}
