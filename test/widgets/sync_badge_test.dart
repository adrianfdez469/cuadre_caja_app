import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/core/theme/app_tokens.dart';
import 'package:cuadre_caja_app/widgets/sync_badge.dart';

void main() {
  Future<void> montar(WidgetTester tester, Widget child) {
    return tester.pumpWidget(
      MaterialApp(
        theme: appLightTheme,
        home: Scaffold(body: Center(child: child)),
      ),
    );
  }

  /// Color de fondo del contenedor pintado por el badge.
  Color fondoDe(WidgetTester tester, Finder texto) {
    final container = tester.widget<Container>(
      find.ancestor(of: texto, matching: find.byType(Container)).first,
    );
    return (container.decoration as BoxDecoration).color!;
  }

  group('CountBadge', () {
    testWidgets('con cero no ocupa sitio: quien lo usa no tiene que envolverlo',
        (tester) async {
      await montar(tester, const CountBadge(count: 0, tone: BadgeTone.error));

      expect(find.byType(Container), findsNothing);
      expect(find.text('0'), findsNothing);
    });

    testWidgets('pinta el número con el lavado del tono', (tester) async {
      await montar(tester, const CountBadge(count: 3, tone: BadgeTone.error));

      expect(find.text('3'), findsOneWidget);
      expect(
        fondoDe(tester, find.text('3')),
        AppSemanticColors.light.negativeWash,
      );
    });

    testWidgets('anuncia al lector de pantalla qué está contando',
        (tester) async {
      await montar(
        tester,
        const CountBadge(
          count: 2,
          tone: BadgeTone.error,
          semanticsLabel: '2 ventas con error',
        ),
      );

      expect(find.bySemanticsLabel('2 ventas con error'), findsOneWidget);
    });
  });

  group('BadgedIcon', () {
    testWidgets('sin nada que avisar devuelve el hijo intacto', (tester) async {
      await montar(
        tester,
        const BadgedIcon(child: Icon(Icons.more_horiz)),
      );

      expect(find.byIcon(Icons.more_horiz), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(BadgedIcon),
          matching: find.byType(Stack),
        ),
        findsNothing,
      );
    });

    testWidgets('lo rechazado por el servidor manda sobre lo que sólo espera',
        (tester) async {
      await montar(
        tester,
        const BadgedIcon(
          errorCount: 2,
          pendingCount: 5,
          child: Icon(Icons.more_horiz),
        ),
      );

      expect(find.text('2'), findsOneWidget);
      expect(find.text('5'), findsNothing);
      expect(fondoDe(tester, find.text('2')), AppSemanticColors.light.negative);
    });

    testWidgets('sin errores avisa en ámbar de lo que falta por subir',
        (tester) async {
      await montar(
        tester,
        const BadgedIcon(pendingCount: 5, child: Icon(Icons.more_horiz)),
      );

      expect(fondoDe(tester, find.text('5')), AppSemanticColors.light.caution);
    });

    testWidgets('un conteo enorme no ensancha el botón', (tester) async {
      await montar(
        tester,
        const BadgedIcon(errorCount: 250, child: Icon(Icons.more_horiz)),
      );

      expect(find.text('99+'), findsOneWidget);
    });
  });
}
