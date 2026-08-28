import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:provider/provider.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'core/di/injection.dart';
import 'core/theme/app_theme.dart';
import 'providers/auth_provider.dart';
import 'providers/productos_provider.dart';
import 'providers/cart_provider.dart';
import 'providers/ventas_provider.dart';
import 'providers/periodo_provider.dart';
import 'providers/monedas_provider.dart';
import 'providers/sync_provider.dart';
import 'providers/theme_mode_provider.dart';
import 'services/sync_service.dart';
import 'screens/splash_screen.dart';

void main() async {
  WidgetsFlutterBinding.ensureInitialized();

  // Necesario para DateFormat/NumberFormat con locale 'es' y 'es_CO'
  await initializeDateFormatting('es', null);
  await initializeDateFormatting('es_CO', null);

  if (kIsWeb) {
    // Importar sqflite_common_ffi_web solo si se necesita
    // Para web: databaseFactory = databaseFactoryFfiWeb;
  }

  await injection.init();

  runApp(const MyApp());
}

class MyApp extends StatelessWidget {
  const MyApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MultiProvider(
      providers: [
        // SyncService como Provider directo para acceso en screens
        Provider<SyncService>.value(value: injection.syncService),

        ChangeNotifierProvider(
          create: (_) => AuthProvider(
            authRemote: injection.authRemoteDataSource,
            storageService: injection.secureStorageService,
            apiClient: injection.apiClient,
          ),
        ),

        ChangeNotifierProvider(
          create: (_) => ProductosProvider(injection.syncService),
        ),

        ChangeNotifierProvider(
          create: (_) => CartProvider(injection.cartLocalDataSource),
        ),

        ChangeNotifierProvider(
          create: (_) => VentasProvider(injection.syncService),
        ),

        ChangeNotifierProvider(
          create: (_) => PeriodoProvider(injection.syncService),
        ),

        ChangeNotifierProvider(
          create: (_) => MonedasProvider(injection.syncService),
        ),

        ChangeNotifierProvider(
          create: (_) => SyncProvider(injection.syncService),
        ),

        ChangeNotifierProvider(create: (_) => ThemeModeProvider()),
      ],
      child: Consumer<ThemeModeProvider>(
        builder: (context, themeModeProvider, _) => MaterialApp(
          title: 'Cuadre de Caja',
          debugShowCheckedModeBanner: false,
          theme: appLightTheme,
          darkTheme: appDarkTheme,
          themeMode: themeModeProvider.themeMode,
          home: const SplashScreen(),
        ),
      ),
    );
  }
}
