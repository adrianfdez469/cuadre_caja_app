# Configuración de la Aplicación POS - Cuadre de Caja

## 📋 Requisitos Previos

- Flutter SDK 3.9.2 o superior
- Dart 3.x
- Conexión a internet para la sincronización inicial
- Backend API ejecutándose

## 🔧 Configuración Inicial

### 1. Configurar la URL del Backend

Edita el archivo `lib/core/constants/api_constants.dart`:

```dart
class ApiConstants {
  // Cambiar esta URL por la de tu backend
  static const String baseUrl = 'http://localhost:3000/api';
  // Para dispositivo físico, usa la IP de tu computadora:
  // static const String baseUrl = 'http://192.168.1.100:3000/api';
  
  // Para producción:
  // static const String baseUrl = 'https://tu-dominio.com/api';
  
  // ... resto del código
}
```

### 2. Instalar Dependencias

```bash
cd cuadre_caja_app
flutter pub get
```

### 3. Ejecutar la Aplicación

**En Chrome (Web):**
```bash
flutter run -d chrome
```

**En macOS (Desktop):**
```bash
flutter run -d macos
```

**En dispositivo Android:**
```bash
flutter run
```

**En simulador iOS:**
```bash
flutter run -d ios
```

## 🏗️ Estructura del Proyecto

```
lib/
├── core/
│   ├── constants/          # Constantes (API, colores, etc.)
│   ├── errors/             # Manejo de errores
│   ├── network/            # NetworkInfo, ApiClient, SecureStorage
│   ├── utils/              # Formatters, Validators
│   └── di/                 # Inyección de dependencias
├── data/
│   ├── datasources/
│   │   ├── local/          # SQLite DataSources
│   │   └── remote/         # API DataSources
│   └── models/             # Modelos de datos
├── providers/              # Gestión de estado con Provider
├── services/               # SyncService
└── screens/                # Pantallas de la aplicación
    ├── splash_screen.dart
    ├── login_screen.dart
    └── pos/                # Pantallas del POS
```

## 🔐 Flujo de Autenticación

1. La app intenta cargar una sesión guardada
2. Si existe → Navega al POS
3. Si no existe → Muestra Login

### Datos de Prueba

Según tu backend, utiliza las credenciales de prueba correspondientes.
Ejemplo:
- Usuario: `admin`
- Contraseña: `123456`

## 💾 Base de Datos Local

La aplicación utiliza SQLite para almacenar:
- Categorías
- Productos
- Ventas (pendientes y sincronizadas)
- Períodos
- Carritos de compra

**Ubicación de la BD:**
- Android: `/data/data/com.example.cuadre_caja_app/databases/`
- iOS: `Library/Application Support/`
- macOS: `~/Library/Containers/.../Data/Library/Application Support/`

## 🔄 Sincronización Offline

### Funcionamiento

1. **Al iniciar sesión:**
   - Descarga categorías y productos
   - Guarda todo en SQLite
   - Verifica período activo

2. **Al crear una venta:**
   - Si hay conexión: Intenta sincronizar inmediatamente
   - Si no hay conexión: Guarda localmente con estado `notSynced`

3. **Sincronización automática:**
   - Ventas pendientes: cada 30 segundos
   - Productos/categorías: cada 5 minutos

### Estados de Sincronización

- 🟢 **Synced**: Ya está en el servidor
- 🟡 **Syncing**: En proceso de subida
- ⚪ **NotSynced**: Pendiente de subir
- 🔴 **SyncError**: Error al sincronizar (después de 5 intentos)

## 📱 Funcionalidades Implementadas

### ✅ Autenticación
- Login con usuario y contraseña
- Almacenamiento seguro de tokens
- Persistencia de sesión
- Selección de local/tienda

### ✅ Punto de Venta
- Grid de categorías con colores personalizados
- Lista de productos por categoría
- Búsqueda de productos en tiempo real
- Carrito multi-cuenta
  - Crear múltiples carritos (cuentas)
  - Cambiar entre carritos
  - Renombrar carritos
  - Eliminar carritos
- Agregar productos al carrito
- Modificar cantidades
- Eliminar productos del carrito

### ✅ Proceso de Pago
- Modal de pago con 3 métodos:
  - Efectivo
  - Transferencia
  - Mixto (efectivo + transferencia)
- Cálculo automático de cambio
- Validación de montos
- Creación de venta

### ✅ Gestión Offline
- Funciona sin conexión después de la carga inicial
- Guarda ventas localmente
- Sincronización automática al recuperar conexión
- Indicador de estado de conexión (Online/Offline)

### ✅ Períodos
- Verificación de período activo
- Apertura de nuevo período
- No permite ventas sin período activo

### ✅ Sincronización
- Sincronización automática en background
- Retry automático de ventas fallidas
- Máximo 5 intentos por venta
- Notificaciones de sincronización

## 🎨 Personalización

### Cambiar Colores

Edita `lib/core/constants/app_colors.dart`:

```dart
class AppColors {
  static const Color primary = Color(0xFF1976D2); // Tu color principal
  static const Color success = Color(0xFF4CAF50);  // Color de éxito
  // ... otros colores
}
```

### Cambiar Intervalos de Sincronización

Edita `lib/core/constants/app_constants.dart`:

```dart
class AppConstants {
  // Cambiar intervalos de sincronización
  static const Duration syncInterval = Duration(seconds: 30);
  static const Duration productSyncInterval = Duration(minutes: 5);
  // ...
}
```

## 🐛 Troubleshooting

### Error: "No se puede conectar al servidor"

1. Verifica que el backend esté ejecutándose
2. Verifica la URL en `api_constants.dart`
3. Si usas dispositivo físico, usa la IP de tu computadora

### Error: "No hay período activo"

1. Asegúrate de que el backend esté retornando un período activo
2. O abre un nuevo período desde la app

### La sincronización no funciona

1. Verifica conexión a internet
2. Revisa los logs en la consola
3. Verifica que el token de autenticación sea válido

### Base de datos corrupta

Desinstala y reinstala la app para resetear la base de datos local.

## 📊 Logs y Debug

Para ver logs detallados, ejecuta:

```bash
flutter run --verbose
```

Los logs importantes tienen prefijos:
- `🚀` Inicialización
- `✅` Operación exitosa
- `❌` Error
- `⚠️` Advertencia
- `🔄` Sincronización
- `💾` Base de datos
- `🌐` Red

## 🚀 Compilación para Producción

### Android APK
```bash
flutter build apk --release
```

### Android App Bundle (para Play Store)
```bash
flutter build appbundle --release
```

### iOS
```bash
flutter build ios --release
```

### macOS
```bash
flutter build macos --release
```

### Web
```bash
flutter build web --release
```

## 📝 Notas Importantes

1. **Primera ejecución:** Requiere conexión a internet
2. **Tokens:** Se almacenan de forma segura en el keychain del dispositivo
3. **Ventas offline:** Se guardan localmente y se sincronizan automáticamente
4. **Límite de reintentos:** 5 intentos por venta, después se marca como error
5. **Cerrar sesión:** Limpia todos los datos locales

## 🔒 Seguridad

- Tokens almacenados en `flutter_secure_storage`
- Contraseñas nunca se guardan localmente
- Comunicación con backend vía HTTPS (en producción)
- Base de datos local no encriptada (SQLite)

## 📄 Licencia

Este proyecto es privado y no debe ser distribuido sin autorización.

