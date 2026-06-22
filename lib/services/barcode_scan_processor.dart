import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/constants/app_colors.dart';
import '../core/di/injection.dart';
import '../core/utils/producto_pos_rules.dart';
import '../core/widgets/app_snackbar.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/periodo_provider.dart';
import '../providers/productos_provider.dart';
import '../providers/sync_provider.dart';
import '../screens/pos/asociar_codigo_sheet.dart';
import 'scan_audio_service.dart';

/// Procesa un código escaneado por pistola (hardware) y lo agrega al carrito.
class BarcodeScanProcessor {
  BarcodeScanProcessor._();

  static Future<void> processHardwareScan(
    BuildContext context,
    String rawCode,
  ) async {
    final code = rawCode.trim();
    if (code.isEmpty) return;

    if (!context.read<PeriodoProvider>().hasActivePeriodo) return;

    final productosProvider = context.read<ProductosProvider>();
    final isOnline = context.read<SyncProvider>().isOnline;
    final offlineMode = !isOnline;
    final producto = productosProvider.findProductByCodigo(code);

    if (producto == null) {
      final usuario = context.read<AuthProvider>().usuario;
      final canAssociate = usuario != null &&
          usuario.hasPermisoOrAdmin('operaciones.pos-venta.asociar_codigo');

      if (canAssociate) {
        final asociado = await AsociarCodigoSheet.show(
          context,
          scannedCode: code,
          productosRemote: injection.productosRemoteDataSource,
        );
        if (!context.mounted) return;
        if (asociado != null) {
          await ScanAudioService.instance.playSuccess();
          AppSnackBar.show(
            context,
            content: Text(
              'Código asociado a "${ProductoPosRules.nombreParaMostrar(asociado)}"',
            ),
            backgroundColor: AppColors.success,
          );
          await processHardwareScan(context, code);
        } else {
          await ScanAudioService.instance.playError();
        }
      } else {
        await ScanAudioService.instance.playError();
        AppSnackBar.show(
          context,
          content: const Text('Producto no encontrado para el código escaneado'),
          backgroundColor: AppColors.error,
        );
      }
      return;
    }

    final cart = context.read<CartProvider>().activeCart;
    final cantidadEnCarrito = cart?.items
            .where((i) => i.productoTiendaId == producto.id)
            .fold<double>(0, (s, i) => s + i.cantidad) ??
        0;
    final maxDisp = ProductoPosRules.getMaxQuantity(
      producto,
      productosProvider.allProductos,
      cantidadEnCarrito: cantidadEnCarrito,
      offlineMode: offlineMode,
    );

    if (isOnline && maxDisp <= 0) {
      await ScanAudioService.instance.playError();
      AppSnackBar.show(
        context,
        content: Text(
          '${ProductoPosRules.nombreParaMostrar(producto)}: sin existencias disponibles',
        ),
        backgroundColor: AppColors.warning,
      );
      return;
    }

    if (!isOnline && !ProductoPosRules.puedeAgregar(
          producto,
          productosProvider.allProductos,
          cantidadEnCarrito: cantidadEnCarrito,
          offlineMode: true,
        )) {
      await ScanAudioService.instance.playError();
      AppSnackBar.show(
        context,
        content: const Text('Cantidad supera el máximo permitido'),
        backgroundColor: AppColors.error,
      );
      return;
    }

    final qty = maxDisp >= 1 ? 1.0 : (producto.permiteDecimal ? 0.1 : 1.0);
    final ok = await context.read<CartProvider>().addToCart(
          producto,
          cantidad: qty,
          allProductos: productosProvider.allProductos,
          isOnline: isOnline,
        );

    if (!context.mounted) return;

    if (ok) {
      await ScanAudioService.instance.playSuccess();
      AppSnackBar.show(
        context,
        content: Text('${ProductoPosRules.nombreParaMostrar(producto)} agregado'),
        backgroundColor: AppColors.success,
        duration: const Duration(seconds: 1),
      );
      if (offlineMode &&
          !ProductoPosRules.tieneStockLocalEfectivo(
            producto,
            productosProvider.allProductos,
            cantidadEnCarrito: cantidadEnCarrito + qty,
          )) {
        AppSnackBar.show(
          context,
          content: const Text('Sin stock local — se validará al sincronizar'),
          backgroundColor: AppColors.warning,
          duration: const Duration(seconds: 2),
        );
      }
    } else {
      await ScanAudioService.instance.playError();
      AppSnackBar.show(
        context,
        content: const Text('Cantidad supera el máximo'),
        backgroundColor: AppColors.error,
      );
    }
  }
}
