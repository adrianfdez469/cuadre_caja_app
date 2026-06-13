# cuadre_caja_app

A new Flutter project.

## Getting Started

This project is a starting point for a Flutter application.

A few resources to get you started if this is your first Flutter project:

- [Lab: Write your first Flutter app](https://docs.flutter.dev/get-started/codelab)
- [Cookbook: Useful Flutter samples](https://docs.flutter.dev/cookbook)

For help getting started with Flutter development, view the
[online documentation](https://docs.flutter.dev/), which offers tutorials,
samples, guidance on mobile development, and a full API reference.

## Compilación de APK (Android)

Antes de compilar, asegúrate de tener las dependencias instaladas:

```bash
flutter pub get
```

### Variantes por arquitectura

Genera un APK optimizado para cada arquitectura:

```bash
# arm64-v8a (dispositivos Android modernos de 64 bits)
flutter build apk --release --target-platform android-arm64

# armeabi-v7a (dispositivos Android de 32 bits)
flutter build apk --release --target-platform android-arm

# x86_64 (emuladores y dispositivos x86 de 64 bits)
flutter build apk --release --target-platform android-x64
```

### APK universal (full)

Incluye todas las arquitecturas en un solo archivo (mayor tamaño):

```bash
flutter build apk --release
```

### Todas las variantes a la vez

Genera los tres APK por arquitectura en una sola ejecución:

```bash
flutter build apk --release --split-per-abi
```

### Salida de los artefactos

Los APK se generan en `build/app/outputs/flutter-apk/`:

| Variante | Archivo |
|----------|---------|
| arm64-v8a | `app-arm64-v8a-release.apk` |
| armeabi-v7a | `app-armeabi-v7a-release.apk` |
| x86_64 | `app-x86_64-release.apk` |
| universal (full) | `app-release.apk` |

> **Nota:** La versión de la app se toma de `pubspec.yaml` (`version: x.y.z+n`). Para publicar actualizaciones en Drive, consulta `docs/ACTUALIZACIONES_DRIVE.md`.
