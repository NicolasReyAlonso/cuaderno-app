import 'package:flutter/material.dart';
import 'package:flutter_riverpod/flutter_riverpod.dart';

import '../../core/api.dart';
import 'auth_controller.dart';

/// Pide la contraseña y borra la cuenta con todos sus datos. Al terminar, la app vuelve al inicio de sesión.
Future<void> showDeleteAccountDialog(BuildContext context) => showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) => const _DeleteAccountDialog(),
    );

class _DeleteAccountDialog extends ConsumerStatefulWidget {
  const _DeleteAccountDialog();

  @override
  ConsumerState<_DeleteAccountDialog> createState() => _DeleteAccountDialogState();
}

class _DeleteAccountDialogState extends ConsumerState<_DeleteAccountDialog> {
  final _password = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _password.dispose();
    super.dispose();
  }

  Future<void> _delete() async {
    if (_password.text.isEmpty) {
      setState(() => _error = 'Escribe tu contraseña para borrar la cuenta.');
      return;
    }
    setState(() {
      _busy = true;
      _error = null;
    });
    try {
      await ref.read(authProvider.notifier).deleteAccount(_password.text);
      if (mounted) Navigator.pop(context);
    } catch (e) {
      if (mounted) {
        setState(() {
          _busy = false;
          _error = apiMessage(e);
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AlertDialog(
      title: const Text('Borrar la cuenta'),
      content: SingleChildScrollView(
        child: Column(mainAxisSize: MainAxisSize.min, crossAxisAlignment: CrossAxisAlignment.start, children: [
          const Text('Se borrarán para siempre tus entrenos, planes, comidas, peso, datos de la pulsera y las fotos y vídeos '
              'de tus ejercicios, en el servidor y en este dispositivo. No se puede deshacer. Necesitas conexión.'),
          const SizedBox(height: 16),
          TextField(
            controller: _password,
            obscureText: true,
            enabled: !_busy,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Contraseña'),
            onSubmitted: (_) => _delete(),
          ),
          if (_error != null) ...[
            const SizedBox(height: 8),
            Text(_error!, style: TextStyle(color: cs.error)),
          ],
        ]),
      ),
      actions: [
        TextButton(onPressed: _busy ? null : () => Navigator.pop(context), child: const Text('Cancelar')),
        FilledButton(
          style: FilledButton.styleFrom(backgroundColor: cs.error, foregroundColor: cs.onError),
          onPressed: _busy ? null : _delete,
          child: _busy
              ? const SizedBox(width: 18, height: 18, child: CircularProgressIndicator(strokeWidth: 2))
              : const Text('Borrar cuenta'),
        ),
      ],
    );
  }
}
