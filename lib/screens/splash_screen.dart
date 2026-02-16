import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../core/constants/app_colors.dart';
import '../core/di/injection.dart';
import '../providers/auth_provider.dart';
import 'login_screen.dart';
import 'pos/pos_home_screen.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen> {
  @override
  void initState() {
    super.initState();
    _init();
  }

  Future<bool> _hasConnection() async {
    final result = await injection.connectivity.checkConnectivity();
    if (result is List) {
      return (result as List).any((r) => r != ConnectivityResult.none);
    }
    return result != ConnectivityResult.none;
  }

  Future<void> _init() async {
    await Future.delayed(const Duration(milliseconds: 500));

    if (!mounted) return;

    final auth = context.read<AuthProvider>();
    final restored = await auth.tryRestoreSession();

    if (!mounted) return;

    if (restored) {
      // Si hay conexión, refrescar token y luego ir al POS (después se sincronizarán los datos)
      if (await _hasConnection()) {
        await auth.refreshToken();
      }
      if (!mounted) return;
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const POSHomeScreen()),
      );
    } else {
      Navigator.of(context).pushReplacement(
        MaterialPageRoute(builder: (_) => const LoginScreen()),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.point_of_sale,
              size: 80,
              color: AppColors.primary,
            ),
            const SizedBox(height: 24),
            Text(
              'Cuadre de Caja',
              style: TextStyle(
                fontSize: 24,
                fontWeight: FontWeight.bold,
                color: AppColors.primary,
              ),
            ),
            const SizedBox(height: 32),
            CircularProgressIndicator(color: AppColors.primary),
          ],
        ),
      ),
    );
  }
}
