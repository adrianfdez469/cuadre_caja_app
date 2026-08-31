/// Normalización de texto para búsquedas.
///
/// Toda búsqueda de texto de la app pasa por aquí. Antes cada pantalla se hacía
/// su propio normalizador privado (con tablas de caracteres distintas entre sí)
/// y el buscador principal del POS no usaba ninguno: "azucar" no encontraba
/// "Azúcar".
class SearchText {
  const SearchText._();

  /// Diacríticos que se pliegan a su letra base. Solo minúsculas: [normalize]
  /// minusculiza antes de plegar, así que las mayúsculas acentuadas ya llegaron
  /// convertidas a su versión minúscula.
  static const _conAcento = 'áàäâãéèëêíìïîóòöôõúùüûñç';
  static const _sinAcento = 'aaaaaeeeeiiiiooooouuuunc';

  /// Minúsculas, sin diacríticos y con los espacios colapsados.
  ///
  /// El colapso de espacios importa para que "coca  cola" (dos espacios, un
  /// resbalón al teclear) se comporte igual que "coca cola".
  static String normalize(String s) {
    final buffer = StringBuffer();
    var espaciopendiente = false;

    for (final rune in s.toLowerCase().runes) {
      final char = String.fromCharCode(rune);

      if (char.trim().isEmpty) {
        // Los espacios de los extremos no se emiten nunca: se marca uno
        // pendiente y solo se escribe si después llega un carácter real.
        if (buffer.isNotEmpty) espaciopendiente = true;
        continue;
      }

      if (espaciopendiente) {
        buffer.write(' ');
        espaciopendiente = false;
      }

      final i = _conAcento.indexOf(char);
      buffer.write(i >= 0 ? _sinAcento[i] : char);
    }

    return buffer.toString();
  }

  /// Palabras normalizadas de una consulta, sin vacíos.
  ///
  /// Que la consulta se parta en palabras es lo que hace que "coca 2" encuentre
  /// "Coca Cola 2L": como cadena entera no es subcadena de nada.
  static List<String> tokens(String query) {
    final normalizado = normalize(query);
    if (normalizado.isEmpty) return const [];
    return normalizado.split(' ').where((t) => t.isNotEmpty).toList();
  }

  /// ¿Están **todos** los [tokens] en [haystack] (que ya debe venir
  /// normalizado)? El orden no importa: "cola coca" encuentra "Coca Cola".
  ///
  /// Sin tokens devuelve `true`: una consulta vacía no filtra nada.
  static bool matchesAll(String haystack, List<String> tokens) {
    for (final token in tokens) {
      if (!haystack.contains(token)) return false;
    }
    return true;
  }

  /// ¿Alguna **palabra** de [texto] (ya normalizado) empieza por [prefijo]?
  /// Se usa para ordenar por relevancia: pesa más "Coca Cola" que "Refresco
  /// sabor coca" cuando se teclea "coca".
  static bool algunaPalabraEmpiezaPor(String texto, String prefijo) {
    if (prefijo.isEmpty) return false;
    for (final palabra in texto.split(' ')) {
      if (palabra.startsWith(prefijo)) return true;
    }
    return false;
  }
}
