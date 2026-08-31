import 'package:flutter/material.dart';

import '../core/theme/app_tokens.dart';

/// Alineación de una columna. Los números van a la derecha **siempre**: es la
/// única forma de que las unidades queden bajo las unidades y una columna se
/// pueda comparar de un vistazo. Con `tabularNums` pero alineados a la
/// izquierda, las cifras siguen sin comparar.
enum TableAlign { start, end }

/// Una columna de [DataTableCard]. O tiene [width] fija, o reparte el sobrante
/// con [flex].
class TableColumn {
  final String label;
  final double? width;
  final int flex;
  final TableAlign align;

  const TableColumn(
    this.label, {
    this.width,
    this.flex = 1,
    this.align = TableAlign.start,
  });
}

const double _kGap = 8;
const EdgeInsets _kCellPadding = EdgeInsets.symmetric(
  horizontal: 12,
  vertical: 10,
);

List<Widget> _layout(List<TableColumn> columns, List<Widget> cells) {
  final out = <Widget>[];
  for (var i = 0; i < columns.length; i++) {
    final col = columns[i];
    final child = Align(
      alignment: col.align == TableAlign.end
          ? Alignment.centerRight
          : Alignment.centerLeft,
      child: cells[i],
    );
    out.add(
      col.width != null
          ? SizedBox(width: col.width, child: child)
          : Expanded(flex: col.flex, child: child),
    );
    if (i != columns.length - 1) out.add(const SizedBox(width: _kGap));
  }
  return out;
}

/// Cabecera de una tabla. Se usa suelta cuando las filas van en un `SliverList`
/// —una tabla de cientos de filas no puede construirse entera— y dentro de
/// [DataTableCard] cuando la tabla es corta.
class DataTableHeader extends StatelessWidget {
  final List<TableColumn> columns;

  const DataTableHeader({super.key, required this.columns});

  @override
  Widget build(BuildContext context) {
    final colors = context.colors;
    final style = Theme.of(
      context,
    ).textTheme.labelMedium!.copyWith(color: colors.accent);

    return Container(
      color: colors.accentWash,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      child: Row(
        children: _layout(columns, [
          for (final c in columns)
            Text(
              c.label,
              style: style,
              textAlign: c.align == TableAlign.end
                  ? TextAlign.right
                  : TextAlign.left,
            ),
        ]),
      ),
    );
  }
}

/// Una fila de tabla: una celda por columna, con líneas opcionales a todo el
/// ancho encima ([title]) y debajo ([footer]).
///
/// El [title] existe por el ancho de un teléfono: el nombre de un producto no
/// cabe como columna sin dejar las cifras sin sitio, así que ocupa su propia
/// línea y las columnas describen sólo la fila numérica.
///
/// [semanticsLabel] agrupa la fila entera en un solo nodo: sin él el lector de
/// pantalla lee cuatro cifras sueltas sin decir de qué producto son.
class DataTableRow extends StatelessWidget {
  final List<TableColumn> columns;
  final List<Widget> cells;
  final Widget? title;
  final Widget? footer;
  final String? semanticsLabel;
  final VoidCallback? onTap;

  const DataTableRow({
    super.key,
    required this.columns,
    required this.cells,
    this.title,
    this.footer,
    this.semanticsLabel,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    Widget row = Padding(
      padding: _kCellPadding,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        mainAxisSize: MainAxisSize.min,
        children: [
          if (title != null) ...[title!, const SizedBox(height: 6)],
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: _layout(columns, cells),
          ),
          if (footer != null) ...[const SizedBox(height: 6), footer!],
        ],
      ),
    );

    if (onTap != null) {
      row = InkWell(onTap: onTap, child: row);
    }
    if (semanticsLabel != null) {
      row = Semantics(
        label: semanticsLabel,
        button: onTap != null,
        container: true,
        excludeSemantics: true,
        child: row,
      );
    }
    return row;
  }
}

/// Tabla corta y completa dentro de una `Card`.
///
/// El [ClipRRect] no es decorativo: la cabecera es un rectángulo de color y sin
/// recortarla asomaba por las esquinas redondeadas de la tarjeta.
class DataTableCard extends StatelessWidget {
  final List<TableColumn> columns;
  final List<DataTableRow> rows;

  const DataTableCard({super.key, required this.columns, required this.rows});

  @override
  Widget build(BuildContext context) {
    return Card(
      clipBehavior: Clip.antiAlias,
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          DataTableHeader(columns: columns),
          for (var i = 0; i < rows.length; i++) ...[
            if (i != 0) const Divider(height: 1),
            rows[i],
          ],
        ],
      ),
    );
  }
}
