import 'package:flutter_test/flutter_test.dart';
import 'package:cuadre_caja_app/core/utils/search_text.dart';

void main() {
  group('SearchText.normalize', () {
    test('pliega los acentos del español', () {
      expect(SearchText.normalize('Azúcar'), 'azucar');
      expect(SearchText.normalize('Café'), 'cafe');
      expect(SearchText.normalize('Niño'), 'nino');
      expect(SearchText.normalize('Piña'), 'pina');
    });

    test('pliega diéresis, graves y circunflejas', () {
      expect(SearchText.normalize('Pingüino'), 'pinguino');
      expect(SearchText.normalize('Crème'), 'creme');
      expect(SearchText.normalize('Pâté'), 'pate');
    });

    test('pliega la cedilla', () {
      expect(SearchText.normalize('Açaí'), 'acai');
    });

    test('colapsa espacios y recorta los extremos', () {
      expect(SearchText.normalize('  coca   cola  '), 'coca cola');
      expect(SearchText.normalize('\tcoca\ncola'), 'coca cola');
    });

    test('una cadena en blanco queda vacía', () {
      expect(SearchText.normalize('   '), '');
      expect(SearchText.normalize(''), '');
    });

    test('no toca dígitos ni signos', () {
      expect(SearchText.normalize('Coca Cola 2L'), 'coca cola 2l');
      expect(SearchText.normalize('7501234'), '7501234');
    });
  });

  group('SearchText.tokens', () {
    test('parte la consulta en palabras normalizadas', () {
      expect(SearchText.tokens('Coca  Cola 2L'), ['coca', 'cola', '2l']);
    });

    test('una consulta vacía no da tokens', () {
      expect(SearchText.tokens('   '), isEmpty);
      expect(SearchText.tokens(''), isEmpty);
    });
  });

  group('SearchText.matchesAll', () {
    const haystack = 'coca cola 2l distr sur';

    test('exige todos los tokens', () {
      expect(SearchText.matchesAll(haystack, ['coca', '2l']), isTrue);
      expect(SearchText.matchesAll(haystack, ['coca', 'fanta']), isFalse);
    });

    test('el orden de las palabras da igual', () {
      expect(SearchText.matchesAll(haystack, ['cola', 'coca']), isTrue);
    });

    test('un token puede caer en medio de una palabra', () {
      expect(SearchText.matchesAll(haystack, ['ol']), isTrue);
    });

    test('sin tokens no filtra', () {
      expect(SearchText.matchesAll(haystack, const []), isTrue);
    });
  });

  group('SearchText.algunaPalabraEmpiezaPor', () {
    test('distingue el inicio de palabra del medio', () {
      expect(SearchText.algunaPalabraEmpiezaPor('coca cola', 'col'), isTrue);
      expect(
        SearchText.algunaPalabraEmpiezaPor('refresco sabor coca', 'ref'),
        isTrue,
      );
      expect(SearchText.algunaPalabraEmpiezaPor('refresco', 'esc'), isFalse);
    });

    test('un prefijo vacío no cuenta', () {
      expect(SearchText.algunaPalabraEmpiezaPor('coca', ''), isFalse);
    });
  });
}
