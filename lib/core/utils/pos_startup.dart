/// Reglas de arranque del POS, aisladas de la pantalla para poder probarlas.
library;

/// ¿Debe el POS esperar a la primera sincronización antes de mostrarse?
///
/// Con catálogo en la base local hay algo que pintar y el cajero puede empezar
/// a trabajar mientras la red responde; el resultado del sync llega después por
/// `onDataRefreshed`. Sin catálogo (primera instalación) no hay nada que
/// mostrar, así que se espera — pero solo si hay conexión: sin ella, esperar no
/// traería nada y dejaría el POS en blanco indefinidamente.
bool debeEsperarPrimerSync({
  required bool tieneCatalogoLocal,
  required bool isOnline,
}) =>
    isOnline && !tieneCatalogoLocal;
