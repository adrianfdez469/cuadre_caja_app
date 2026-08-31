import 'package:flutter/material.dart';
import 'package:provider/provider.dart';

import '../core/di/injection.dart';
import '../core/theme/app_tokens.dart';
import '../core/utils/producto_pos_rules.dart';
import '../core/widgets/app_snackbar.dart';
import '../providers/auth_provider.dart';
import '../providers/cart_provider.dart';
import '../providers/periodo_provider.dart';
import '../providers/productos_provider.dart';
import '../core/utils/venta_sin_stock_policy.dart';
import '../screens/pos/asociar_codigo_sheet.dart';
import 'scan_feedback_service.dart';

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
    final permitirSinStock = VentaSinStockPolicy.of(context, listen: false);
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
          await ScanFeedbackService.instance.playSuccess();
          AppSnackBar.show(
            context,
            content: Text(
              'Código asociado a "${ProductoPosRules.nombreParaMostrar(asociado)}"',
            ),
            backgroundColor: context.colors.positive,
          );
          await processHardwareScan(context, code);
        } else {
          await ScanFeedbackService.instance.playError();
        }
      } else {
        await ScanFeedbackService.instance.playError();
        AppSnackBar.show(
          context,
          content: const Text('Producto no encontrado para el código escaneado'),
          backgroundColor: context.colors.negative,
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
      permitirSinStock: permitirSinStock,
    );

    if (!permitirSinStock && maxDisp <= 0) {
      await ScanFeedbackService.instance.playError();
      AppSnackBar.show(
        context,
        content: Text(
          '${ProductoPosRules.nombreParaMostrar(producto)}: sin existencias disponibles',
        ),
        backgroundColor: context.colors.caution,
      );
      return;
    }

    if (permitirSinStock && !ProductoPosRules.puedeAgregar(
          producto,
          productosProvider.allProductos,
          cantidadEnCarrito: cantidadEnCarrito,
          permitirSinStock: true,
        )) {
      await ScanFeedbackService.instance.playError();
      AppSnackBar.show(
        context,
        content: const Text('Cantidad supera el máximo permitido'),
        backgroundColor: context.colors.negative,
      );
      return;
    }

    final qty = maxDisp >= 1 ? 1.0 : (producto.permiteDecimal ? 0.1 : 1.0);
    final ok = await context.read<CartProvider>().addToCart(
          producto,
          cantidad: qty,
          allProductos: productosProvider.allProductos,
          permitirSinStock: permitirSinStock,
          moverAlInicio: true,
        );

    if (!context.mounted) return;

    if (ok) {
      await ScanFeedbackService.instance.playSuccess();
      // Un único mensaje por escaneo: AppSnackBar reemplaza al anterior, así que
      // dos seguidos harían desaparecer el primero al instante.
      final sinStockLocal = permitirSinStock &&
          !ProductoPosRules.tieneStockLocalEfectivo(
            producto,
            productosProvider.allProductos,
            cantidadEnCarrito: cantidadEnCarrito + qty,
          );
      final nombre = ProductoPosRules.nombreParaMostrar(producto);
      AppSnackBar.show(
        context,
        content: Text(
          sinStockLocal
              ? '$nombre agregado — sin stock, se validará al sincronizar'
              : '$nombre agregado',
        ),
        backgroundColor:
            sinStockLocal ? context.colors.caution : context.colors.positive,
        duration: Duration(seconds: sinStockLocal ? 2 : 1),
      );
    } else {
      await ScanFeedbackService.instance.playError();
      AppSnackBar.show(
        context,
        content: const Text('Cantidad supera el máximo'),
        backgroundColor: context.colors.negative,
      );
    }
  }
}
