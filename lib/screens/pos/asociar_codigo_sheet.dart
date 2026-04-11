import 'package:dio/dio.dart';
import 'package:flutter/material.dart';
import 'package:provider/provider.dart';
import '../../core/constants/app_colors.dart';
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
    return showModalBottomSheet<ProductoModel>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Colors.transparent,
      builder: (_) => AsociarCodigoSheet(
        scannedCode: scannedCode,
        productosRemote: productosRemote,
      ),
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
      context
          .read<ProductosProvider>()
          .addCodigoToProducto(producto.id, nuevoCodigo);
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
      decoration: const BoxDecoration(
        color: Colors.white,
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
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
          color: Colors.grey.shade300,
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
              color: AppColors.warning.withOpacity(0.15),
              borderRadius: BorderRadius.circular(10),
            ),
            child: const Icon(
              Icons.link_off_rounded,
              color: AppColors.warning,
              size: 22,
            ),
          ),
          const SizedBox(width: 12),
          const Expanded(
            child: Text(
              'Código no reconocido',
              style: TextStyle(
                fontSize: 17,
                fontWeight: FontWeight.bold,
              ),
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
              color: Colors.grey.shade700,
              fontSize: 13,
              height: 1.4,
            ),
          ),
          const SizedBox(height: 10),
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
            decoration: BoxDecoration(
              color: AppColors.primary.withOpacity(0.08),
              borderRadius: BorderRadius.circular(20),
              border:
                  Border.all(color: AppColors.primary.withOpacity(0.25)),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                const Icon(
                  Icons.qr_code_2,
                  size: 14,
                  color: AppColors.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  widget.scannedCode,
                  style: const TextStyle(
                    color: AppColors.primary,
                    fontWeight: FontWeight.w700,
                    fontSize: 14,
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
            borderRadius: BorderRadius.circular(12),
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
            style: TextStyle(color: Colors.grey.shade600, fontSize: 13),
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
            Divider(height: 1, color: Colors.grey.shade200),
        itemBuilder: (_, i) {
          final p = _searchResults[i];
          return _buildProductTile(p, _selectedProduct?.id == p.id);
        },
      ),
    );
  }

  Widget _buildProductTile(ProductoModel producto, bool isSelected) {
    final sinStock = !producto.hasStock;
    return InkWell(
      onTap: () => _selectProduct(producto),
      borderRadius: BorderRadius.circular(8),
      child: Container(
        color: isSelected ? AppColors.primary.withOpacity(0.07) : null,
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
        child: Row(
          children: [
            SizedBox(
              width: 24,
              child: isSelected
                  ? const Icon(
                      Icons.check_circle,
                      color: AppColors.primary,
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
                      fontSize: 14,
                      color: isSelected ? AppColors.primary : null,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Text(
                        '\$${producto.precio.toStringAsFixed(2)}',
                        style: const TextStyle(
                          color: AppColors.success,
                          fontSize: 12,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(width: 10),
                      Icon(
                        Icons.inventory_2_outlined,
                        size: 11,
                        color: sinStock ? AppColors.warning : Colors.grey,
                      ),
                      const SizedBox(width: 3),
                      Text(
                        producto.existencia % 1 == 0
                            ? producto.existencia.toInt().toString()
                            : producto.existencia.toStringAsFixed(2),
                        style: TextStyle(
                          color: sinStock
                              ? AppColors.warning
                              : Colors.grey.shade600,
                          fontSize: 12,
                          fontWeight: sinStock
                              ? FontWeight.w600
                              : FontWeight.normal,
                        ),
                      ),
                      if (sinStock) ...[
                        const SizedBox(width: 4),
                        const Text(
                          '(sin stock)',
                          style: TextStyle(
                            color: AppColors.warning,
                            fontSize: 11,
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
          color: AppColors.success.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.success.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.check_circle_outline,
                color: AppColors.success, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                'Se asociará "${widget.scannedCode}" a "${_selectedProduct!.nombre}"',
                style: const TextStyle(
                  fontSize: 12,
                  color: AppColors.success,
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
          color: AppColors.error.withOpacity(0.08),
          borderRadius: BorderRadius.circular(10),
          border: Border.all(color: AppColors.error.withOpacity(0.35)),
        ),
        child: Row(
          children: [
            const Icon(Icons.error_outline, color: AppColors.error, size: 16),
            const SizedBox(width: 8),
            Expanded(
              child: Text(
                _errorMessage!,
                style: const TextStyle(fontSize: 12, color: AppColors.error),
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
                  ? const SizedBox(
                      width: 16,
                      height: 16,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: Colors.white,
                      ),
                    )
                  : const Icon(Icons.add_link, size: 18),
              label: Text(_isLoading ? 'Asociando...' : 'Asociar código'),
              style: ElevatedButton.styleFrom(
                backgroundColor: AppColors.primary,
                foregroundColor: Colors.white,
                disabledBackgroundColor: Colors.grey.shade300,
                disabledForegroundColor: Colors.grey.shade500,
                padding: const EdgeInsets.symmetric(vertical: 12),
              ),
            ),
          ),
        ],
      ),
    );
  }
}
