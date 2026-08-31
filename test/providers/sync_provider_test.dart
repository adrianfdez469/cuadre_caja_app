// `SyncProvider.fullSync` se llama sin `await` en el arranque del POS: si un
// fullSync que lanza dejara `isSyncing` en true, la cabecera se quedaría girando
// para siempre y `_performSync` no volvería a dejar sincronizar.
import 'package:cuadre_caja_app/providers/sync_provider.dart';
import 'package:cuadre_caja_app/services/sync_service.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/sync_service_fakes.dart';

void main() {
  group('SyncProvider.fullSync', () {
    test('deja isSyncing en false tras un ciclo normal', () async {
      final h = SyncHarness(periodoServidor: periodoDe('p1'));
      await h.arrancar();
      final provider = SyncProvider(h.service);

      final futuro = provider.fullSync('t1', negocioId: 'n1');
      expect(provider.isSyncing, isTrue, reason: 'se marca antes de esperar');
      await futuro;

      expect(provider.isSyncing, isFalse);

      provider.dispose();
      h.parar();
    });

    test('un fullSync que lanza no deja isSyncing atascado en true', () async {
      final h = SyncHarness(periodoServidor: periodoDe('p1'));
      h.ventasLocal.errorAlListarPendientes = Exception('BD corrupta');
      await h.arrancar();
      final provider = SyncProvider(h.service);

      await expectLater(
        provider.fullSync('t1', negocioId: 'n1'),
        throwsA(isA<Exception>()),
      );

      expect(provider.isSyncing, isFalse);

      provider.dispose();
      h.parar();
    });

    test('publica el estado de conexión que reporta el servicio', () async {
      final h = SyncHarness();
      final provider = SyncProvider(h.service);
      // El provider se registra en los callbacks al construirse; `arrancar()`
      // los sobreescribe, así que aquí se arranca el servicio a mano.
      await h.service.startMonitoring();

      expect(provider.connectionStatus, ConnectionStatus.online);
      expect(provider.isOnline, isTrue);

      provider.dispose();
      h.parar();
    });
  });
}
