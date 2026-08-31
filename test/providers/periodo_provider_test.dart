import 'package:cuadre_caja_app/providers/periodo_provider.dart';
import 'package:flutter_test/flutter_test.dart';

import '../fakes/sync_service_fakes.dart';
import '../fakes/test_fakes.dart';

void main() {
  group('PeriodoProvider.loadFromCache', () {
    test('toma el período que hay en la base local', () async {
      final provider = PeriodoProvider(
        FakeSyncService(periodoAbierto: periodoDe('p1')),
      );

      await provider.loadFromCache('t1');

      expect(provider.periodoId, 'p1');
      expect(provider.hasActivePeriodo, isTrue);
    });

    test('sin fila en cache no hay período activo', () async {
      // El cache es espejo del servidor: que no haya fila significa que el
      // servidor dijo que no hay período abierto, no que falte información.
      final provider = PeriodoProvider(FakeSyncService());

      await provider.loadFromCache('t1');

      expect(provider.periodo, isNull);
      expect(provider.hasActivePeriodo, isFalse);
    });

    test('un período cerrado en cache no habilita la venta', () async {
      final provider = PeriodoProvider(
        FakeSyncService(periodoAbierto: periodoDe('p1', abierto: false)),
      );

      await provider.loadFromCache('t1');

      expect(provider.hasActivePeriodo, isFalse);
    });

    test('no toca isLoading', () async {
      // Corre tras cada sincronización: si moviera isLoading, el botón
      // "Abrir Período" parpadearía deshabilitado en cada ciclo.
      final provider = PeriodoProvider(
        FakeSyncService(periodoAbierto: periodoDe('p1')),
      );

      await provider.loadFromCache('t1');

      expect(provider.isLoading, isFalse);
    });

    test('notifica a los oyentes', () async {
      final provider = PeriodoProvider(
        FakeSyncService(periodoAbierto: periodoDe('p1')),
      );
      var notificaciones = 0;
      provider.addListener(() => notificaciones++);

      await provider.loadFromCache('t1');

      expect(notificaciones, 1);
    });

    test('lee de disco, no del servidor', () async {
      // Con el período de red y el de disco distintos se ve cuál se usó: si
      // `loadFromCache` fuera a la red, saldría 'del-servidor'.
      final sync = FakeSyncService(
        periodoAbierto: periodoDe('del-servidor'),
        periodoEnCacheLocal: periodoDe('del-disco'),
      );
      final provider = PeriodoProvider(sync);

      await provider.loadFromCache('t1');

      expect(provider.periodoId, 'del-disco');
      expect(sync.loadPeriodoActualCalls, 0, reason: 'cero GET /periodo');
      expect(sync.getPeriodoLocalCalls, 1);
    });

    test('un cierre desde la web vacía el período del POS', () async {
      // El cache es espejo del servidor: `loadPeriodoActual` borró la fila, así
      // que el siguiente repintado tiene que dejar el POS sin período, no
      // conservar el que ya tenía en memoria.
      final sync = FakeSyncService(periodoAbierto: periodoDe('p1'));
      final provider = PeriodoProvider(sync);
      await provider.loadFromCache('t1');
      expect(provider.hasActivePeriodo, isTrue);

      final vacio = PeriodoProvider(FakeSyncService());
      await vacio.loadFromCache('t1');

      expect(vacio.periodo, isNull);
      expect(vacio.hasActivePeriodo, isFalse);
    });

    test('no borra el error previo ni lo inventa', () async {
      final provider = PeriodoProvider(FakeSyncService());

      await provider.loadFromCache('t1');

      expect(provider.error, isNull);
    });
  });

  group('PeriodoProvider.loadPeriodo (network-first)', () {
    test('un fallo del servicio deja el error y apaga isLoading', () async {
      // `FakeSyncService.loadPeriodoActual` lanza cuando no hay período.
      final provider = PeriodoProvider(FakeSyncService());

      await provider.loadPeriodo('t1');

      expect(provider.isLoading, isFalse);
      expect(provider.error, isNotNull);
      expect(provider.hasActivePeriodo, isFalse);
    });
  });
}
