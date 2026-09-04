import 'package:flutter_test/flutter_test.dart';

import 'package:cuadre_caja_app/data/models/moneda_model.dart';
import 'package:cuadre_caja_app/data/models/tasa_model.dart';

/// `GET /tasas-cambio` cambió de forma entre contratos: el viejo devolvía
/// `vigentes` **sin la moneda base** más un `tasasCup` completo; el v2.0.1
/// devuelve solo `vigentes`, ya completo. La app se despliega antes que el
/// backend, así que tiene que salir con el mapa completo en los dos casos: sin
/// la tasa de la propia base, `cupTasa(monedaBase)` cae a 1 y toda conversión
/// hacia la base queda inflada por el factor de la base.
void main() {
  group('TasasVigentesResponse.fromJson', () {
    test('contrato v2.0.1: solo vigentes, ya completo', () {
      final r = TasasVigentesResponse.fromJson(const {
        'monedaBase': 'USD',
        'vigentes': {'USD': 680, 'EUR': 775},
        'actualizadoEn': '2026-09-02T16:50:31.817Z',
      });

      expect(r.monedaBase, 'USD');
      expect(r.tasas, const {'USD': 680.0, 'EUR': 775.0});
      expect(r.actualizadoEn, DateTime.parse('2026-09-02T16:50:31.817Z'));
    });

    test('contrato anterior: vigentes recortado + tasasCup completo', () {
      final r = TasasVigentesResponse.fromJson(const {
        'monedaBase': 'USD',
        'vigentes': {'EUR': 775},
        'tasasCup': {'USD': 680, 'EUR': 775},
      });

      expect(
        r.tasas['USD'],
        680.0,
        reason: 'sin la tasa de la base toda conversión se resuelve a tasa 1',
      );
      expect(r.tasas['EUR'], 775.0);
    });

    test('descarta CUP y las tasas no positivas', () {
      final r = TasasVigentesResponse.fromJson(const {
        'monedaBase': 'CUP',
        'vigentes': {'USD': 400, 'MLC': 0},
        'tasasCup': {'CUP': 1, 'ZWL': -5},
      });

      expect(r.tasas, const {'USD': 400.0});
    });

    test('respuesta vacía o sin tasas no revienta', () {
      expect(TasasVigentesResponse.fromJson(const {}).tasas, isEmpty);
      expect(TasasVigentesResponse.fromJson(const {}).monedaBase, 'CUP');
    });
  });

  group('MultimonedaConfig.fromCacheJson', () {
    test('lee la caché nueva', () {
      final c = MultimonedaConfig.fromCacheJson(const {
        'negocioId': 'neg-1',
        'monedaBase': 'USD',
        'tasas': {'USD': 680, 'EUR': 775},
      });

      expect(c.tasas, const {'USD': 680.0, 'EUR': 775.0});
    });

    test('une las dos claves de la caché escrita por versiones anteriores', () {
      // Actualizar la app no puede dejar al cajero sin tasas hasta el próximo
      // sync: la caché vieja guardaba `tasasConversion` (completo) junto a
      // `tasasVigentes` (sin la base).
      final c = MultimonedaConfig.fromCacheJson(const {
        'negocioId': 'neg-1',
        'monedaBase': 'USD',
        'tasasVigentes': {'EUR': 775},
        'tasasConversion': {'USD': 680, 'EUR': 775},
      });

      expect(c.tasas['USD'], 680.0);
      expect(c.tasas['EUR'], 775.0);
    });
  });
}
