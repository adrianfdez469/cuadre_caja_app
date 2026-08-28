import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/theme/app_tokens.dart';
import '../../services/hardware_scanner_gate.dart';
import '../../data/datasources/remote/productos_remote_datasource.dart';
import '../../data/models/producto_model.dart';
import '../../providers/productos_provider.dart';

/// Normaliza un string para búsqueda: minúsculas, sin tildes ni diéresis.
String _normalize(String s) {
  const src = 'áéíóúüñÁÉÍÓÚÜÑàèìòùÀÈÌÒÙ';
  const dst = 'aeiouunaeioounaeiouaeiou';
  var r = s.toLowerCase();
  for (int i = 0; i < src.length; i++) {
    r = r.replaceAll(src[i], dst[i]);
  }
  return r;
}

/// Bottom sheet que permite asociar un código de barras desconocido
/// a un producto existente en la tienda.
class AsociarCodigoSheet extends StatefulWidget {
  const AsociarCodigoSheet({
    super.key,
    required this.scannedCode,
    required this.productosRemote,
  });

  final String scannedCode;
  final ProductosRemoteDataSource productosRemote;

  /// Abre el bottom sheet y devuelve el [ProductoModel] si la asociación fue
  /// exitosa, o `null` si el usuario canceló.
  static Future<ProductoModel?> show(
    BuildContext context, {
    required String scannedCode,
    required ProductosRemoteDataSource productosRemote,
  }) {
    HardwareScannerGate.instance.block('asociar');
    return showModalBottomSheet<ProductoModel>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AsociarCodigoSheet(
        scannedCode: scannedCode,
        productosRemote: productosRemote,
      ),
    ).whenComplete(
      () => HardwareScannerGate.instance.unblock('asociar'),
    );
  }

  @override
  State<AsociarCodigoSheet> createState() => _AsociarCodigoSheetState();
}

class _AsociarCodigoSheetState extends State<AsociarCodigoSheet> {
  final _searchController = TextEditingController();
  List<ProductoModel> _searchResults = [];
  ProductoModel? _selectedProduct;
  bool _isLoading = false;
  String? _errorMessage;

  @override
  void initState() {
    super.initState();
    _searchController.addListener(_onSearchChanged);
  }

  @override
  void dispose() {
    _searchController.removeListener(_onSearchChanged);
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged() {
    final query = _normalize(_searchController.text.trim());
    if (query.isEmpty) {
      setState(() {
        _searchResults = [];
        _selectedProduct = null;
      });
      return;
    }
    final allProductos = context.read<ProductosProvider>().allProductos;
    final results = allProductos
        .where((p) => _normalize(p.nombre).contains(query))
        .take(8)
        .toList();
    setState(() {
      _searchResults = results;
      if (_selectedProduct != null &&
          !results.any((p) => p.id == _selectedProduct!.id)) {
        _selectedProduct = null;
      }
    });
  }

  void _selectProduct(ProductoModel producto) {
    setState(() {
      _selectedProduct = producto;
      _errorMessage = null;
    });
  }

  Future<void> _asociar() async {
    final producto = _selectedProduct;
    if (producto == null || _isLoading) return;

    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      final nuevoCodigo = await widget.productosRemote.asociarCodigo(
        producto.productoId,
        widget.scannedCode,
      );
      if (!mounted) return;
      await context
          .read<ProductosProvider>()
          .addCodigoToProducto(producto.id, nuevoCodigo);
      if (!mounted) return;
      Navigator.of(context).pop(producto);
    } on DioException catch (e) {
      if (!mounted) return;
      final body = e.response?.data;
      final msg = (body is Map ? body['error'] : null) as String? ??
          'Error al asociar el código';
      setState(() {
        _isLoading = false;
        _errorMessage = msg;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _isLoading = false;
        _errorMessage = 'Error inesperado. Intenta de nuevo.';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final bottomInset = MediaQuery.of(context).viewInsets.bottom;

    return Container(
      margin: const EdgeInsets.only(top: 80),
      decoration: BoxDecoration(
        color: context.colors.raised,
        borderRadius:
            const BorderRadius.vertical(top: Radius.circular(AppRadius.lg)),
      ),
      child: SafeArea(
        top: false,
        child: Padding(
          padding: EdgeInsets.only(bottom: bottomInset),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              _buildHandle(),
              _buildHeader(),
              _buildDescription(),
              const SizedBox(height: 14),
              _buildSearchField(),
              const SizedBox(height: 6),
              _buildResultsList(),
              if (_selectedProduct != null) _buildConfirmationBadge(),
              if (_errorMessage != null) _buildErrorBadge(),
              _buildActions(),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildHandle() {
    return Center(
      child: Container(
        margin: const EdgeInsets.only(top: 10, bottom: 4),
        width: 40,
        height: 4,
        decoration: BoxDecoration(
          color: context.colors.border,
          borderRadius: BorderRadius.circular(2),
        ),
      ),
    );
  }

  Widget _buildHeader() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 8, 0),
      child: Row(
        children: [
          Container(
            padding: const EdgeInsets.all(8),
            decoration: BoxDecoration(
              color: context.colors.cautionWash,
              borderRadius: BorderRadius.circular(AppRadius.sm),
            ),
            child: Icon(
              Icons.link_off_rounded,
              color: context.colors.caution,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              'Código no reconocido',
              style: Theme.of(context).textTheme.headlineSmall,
            ),
          ),
          IconButton(
            icon: const Icon(Icons.close),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }

  Widget _buildDescription() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            'El código escaneado no está registrado. Puedes asociarlo a un producto existente para agilizar futuras ventas.',
            style: TextStyle(
              color: context.colors.textSecondary,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: context.colors.accentWash,
              borderRadius: BorderRadius.circular(AppRadius.pill),
              border: Border.all(
                color: context.colors.accent.withValues(alpha: 0.25),
              ),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.qr_code_2,
                  size: 14,
                  color: context.colors.accent,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.scannedCode,
                  style: TextStyle(
                    color: context.colors.accent,
                    fontWeight: FontWeight.w700,
                    fontSize: 15,
                    letterSpacing: 0.6,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSearchField() {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 20),
      child: TextField(
        controller: _searchController,
        autofocus: true,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: 'Buscar producto...',
          prefixIcon: const Icon(Icons.search, size: 20),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(AppRadius.md),
          ),
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(vertical: 10, horizontal: 12),
        ),
      ),
    );
  }

  Widget _buildResultsList() {
    if (_searchResults.isEmpty) {
      if (_searchController.text.isNotEmpty) {
        return Padding(
          padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 10),
          child: Text(
            'Sin resultados para "${_searchController.text}"',
            style: TextStyle(color: context.colors.textSecondary, fontSize: 13),
            textAlign: TextAlign.center,
          ),
        );
      }
      return const SizedBox.shrink();
    }

    return ConstrainedBox(
      constraints: const BoxConstraints(maxHeight: 260),
      child: ListView.separated(
        shrinkWrap: true,
        padding: const EdgeInsets.symmetric(horizontal: 12),
        itemCount: _searchResults.length,
        separatorBuilder: (_, __) =>
            Divider(height: 1, color: context.colors.border),
        itemBuilder: (_, i) {
          final p = _searchResults[i];
          return _buildProductTile(p, _selectedProduct?.id == p.id);
        },
      ),
    );
  }

  Widget _buildProductTile(ProductoModel producto, bool isSelected) {
    final sinStock = !producto.hasStock;
    final accent = context.colors.accent;
    final caution = context.colors.caution;
    return InkWell(
      onTap: () => _selectProduct(producto),
      borderRadius: BorderRadius.circular(AppRadius.sm),
      child: Container(
        color: isSelected ? context.colors.accentWash : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: isSelected
                  ? Icon(
                      Icons.check_circle,
                      color: accent,
                      size: 18,
                    )
                  : null,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    producto.nombre,
                    style: TextStyle(
                      fontWeight:
                          isSelected ? FontWeight.w700 : FontWeight.w500,
                      fontSize: 15,
                      color: isSelected ? accent : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '\$${producto.precio.toStringAsFixed(2)}',
                        style: TextStyle(
                          color: context.colors.positive,
                          fontSize: 11.5,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 11,
                        color: sinStock ? caution : context.colors.textSecondary,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        producto.existencia % 1 == 0
                            ? producto.existencia.toInt().toString()
                            : producto.existencia.toStringAsFixed(2),
                        style: TextStyle(
                          color: sinStock ? caution : context.colors.textSecondary,
                          fontSize: 11.5,
                          fontWeight: sinStock
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      if (sinStock) ...[
                        const SizedBox(width: 4),
                        Text(
                          '(sin stock)',
                          style: TextStyle(
                            color: caution,
                            fontSize: 11.5,
                          ),
                        ),
                      ],
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildConfirmationBadge() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 10, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: context.colors.positiveWash,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: context.colors.positive.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.check_circle_outline,
                color: context.colors.positive, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Se asociará "${widget.scannedCode}" a "${_selectedProduct!.nombre}"',
                style: TextStyle(
                  fontSize: 11.5,
                  color: context.colors.positive,
                  fontWeight: FontWeight.w500,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildErrorBadge() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 8, 20, 0),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        decoration: BoxDecoration(
          color: context.colors.negativeWash,
          borderRadius: BorderRadius.circular(AppRadius.sm),
          border: Border.all(
            color: context.colors.negative.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.error_outline, color: context.colors.negative, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _errorMessage!,
                style: TextStyle(fontSize: 11.5, color: context.colors.negative),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildActions() {
    return Padding(
      padding: const EdgeInsets.fromLTRB(20, 14, 20, 16),
      child: Row(
        children: [
          Expanded(
            child: OutlinedButton(
              onPressed:
                  _isLoading ? null : () => Navigator.of(context).pop(),
              child: const Text('Cancelar'),
            ),
          ),
          const SizedBox(width: 12),
          Expanded(
            flex: 2,
            child: ElevatedButton.icon(
              onPressed:
                  (_selectedProduct != null && !_isLoading) ? _asociar : null,
              icon: _isLoading
                  ? SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: context.colors.onAccent,
                      ),
                    )
                  : const Icon(Icons.add_link, size: 18),
              label: Text(_isLoading ? 'Asociando...' : 'Asociar código'),
              style: ElevatedButton.styleFrom(
                backgroundColor: context.colors.accent,
                foregroundColor: context.colors.onAccent,
                disabledBackgroundColor: context.colors.border,
                disabledForegroundColor: context.colors.textDisabled,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
