import 'dart:async';

import 'package:dio/dio.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import '../../core/local/sync_controller.dart';

/// true = hay sesión iniciada. login() y register() lanzan el error si fallan;
/// la pantalla de login lo muestra con apiMessage().
class AuthController extends AsyncNotifier<bool> {
  @override
  Future<bool> build() async {
    // Si el servidor rechaza el token, volvemos al login
    ref.listen(unauthorizedProvider, (_, __) => logout());
    return (await ref.read(tokenStoreProvider).read()) != null;
  }

  Future<void> login(String email, String password) async {
    final r = await ref.read(dioProvider).post<Map<String, dynamic>>(
          '/auth/login',
          data: {'username': email.trim(), 'password': password},
          options: Options(contentType: Headers.formUrlEncodedContentType),
        );
    await _signedIn(r.data!['access_token'] as String);
  }

  Future<void> register(String email, String password, String name) async {
    final r = await ref.read(dioProvider).post<Map<String, dynamic>>(
          '/auth/register',
          data: {'email': email.trim(), 'password': password, 'name': name.trim()},
        );
    await _signedIn(r.data!['access_token'] as String);
  }

  Future<void> logout() async {
    await ref.read(tokenStoreProvider).clear();
    state = const AsyncData(false);
  }

  /// Borra la cuenta en el servidor (pide la contraseña; si falla, lanza el error) y deja el dispositivo limpio.
  Future<void> deleteAccount(String password) async {
    await ref.read(dioProvider).delete<void>('/me', data: {'password': password});
    // Primero el token, para que ninguna sincronización en marcha vuelva a llenar la base
    await ref.read(tokenStoreProvider).clear();
    await ref.read(localDbProvider).wipe();
    state = const AsyncData(false);
  }

  Future<void> _signedIn(String token) async {
    await ref.read(tokenStoreProvider).write(token);
    state = const AsyncData(true);
    // Primera descarga (y base local vacía si antes la usaba otra cuenta)
    unawaited(ref.read(syncControllerProvider.notifier).onLogin());
  }
}

final authProvider = AsyncNotifierProvider<AuthController, bool>(AuthController.new);
