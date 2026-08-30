import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'package:cuadre_caja_app/core/constants/storage_keys.dart';
import 'package:cuadre_caja_app/core/theme/app_theme.dart';
import 'package:cuadre_caja_app/providers/theme_mode_provider.dart';
import 'package:cuadre_caja_app/providers/venta_sin_stock_provider.dart';
import 'package:cuadre_caja_app/screens/pos/widgets/user_menu_sheet.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<void> abrirHoja(WidgetTester tester) async {
    await tester.pumpWidget(
      MultiProvider(
        providers: [
          ChangeNotifierProvider(create: (_) => ThemeModeProvider()),
          ChangeNotifierProvider(create: (_) => VentaSinStockProvider()),
        ],
        child: MaterialApp(
          theme: appLightTheme,
          home: Scaffold(
            body: Builder(
              builder: (context) => ElevatedButton(
                onPressed: () => UserMenuSheet.show(context, onLogout: () {}),
                child: const Text('abrir'),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.tap(find.text('abrir'));
    await tester.pumpAndSettle();
  }

  testWidgets('el ajuste arranca desactivado y aclara que rige sin conexión',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await abrirHoja(tester);

    expect(find.text('Vender sin existencias'), findsOneWidget);
    expect(find.text('Solo sin conexión'), findsOneWidget);
  });

  testWidgets('activarlo lo persiste y avisa del rechazo del servidor',
      (tester) async {
    SharedPreferences.setMockInitialValues({});
    await abrirHoja(tester);

    await tester.tap(find.text('Vender sin existencias'));
    await tester.pumpAndSettle();

    expect(
      find.text('Activado — el servidor puede rechazar la venta'),
      findsOneWidget,
    );
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getBool(StorageKeys.ventaSinStockEnabled), isTrue);
  });

  testWidgets('el interruptor refleja lo guardado en la sesión anterior',
      (tester) async {
    SharedPreferences.setMockInitialValues(
      {StorageKeys.ventaSinStockEnabled: true},
    );
    await abrirHoja(tester);

    final sw = tester.widget<Switch>(
      find.descendant(
        of: find.ancestor(
          of: find.text('Vender sin existencias'),
          matching: find.byType(InkWell),
        ).first,
        matching: find.byType(Switch),
      ),
    );
    expect(sw.value, isTrue);
  });
}
