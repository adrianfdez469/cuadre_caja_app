import 'package:cuadre_caja_app/core/utils/pos_startup.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('debeEsperarPrimerSync', () {
    test('con catálogo en cache el POS se pinta ya, sin esperar a la red', () {
      expect(
        debeEsperarPrimerSync(tieneCatalogoLocal: true, isOnline: true),
        isFalse,
      );
    });

    test('primera instalación con conexión: espera a tener catálogo', () {
      expect(
        debeEsperarPrimerSync(tieneCatalogoLocal: false, isOnline: true),
        isTrue,
      );
    });

    test('sin catálogo y sin conexión no se espera: no llegaría nada', () {
      expect(
        debeEsperarPrimerSync(tieneCatalogoLocal: false, isOnline: false),
        isFalse,
      );
    });

    test('con catálogo y sin conexión tampoco se espera', () {
      expect(
        debeEsperarPrimerSync(tieneCatalogoLocal: true, isOnline: false),
        isFalse,
      );
    });
  });
}
