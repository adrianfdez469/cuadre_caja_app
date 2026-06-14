# Actualizaciones desde Google Drive

La app puede comprobar si hay una versión nueva en una carpeta de Google Drive y permitir al usuario descargar e instalar el APK.

## Configuración

1. **Versión de la app**: La versión que ve el usuario es la de `pubspec.yaml` (ej. `version: 1.0.10+10`).
   - La parte **antes del +** (`1.0.10`) es `versionName` (visible al usuario).
   - La parte **después del +** (`10`) es `versionCode` (número interno de Android).
   - **CRÍTICO:** cada APK nuevo debe tener un `versionCode` **mayor** que el anterior. Si bajas ese número, Android muestra *"No se instaló la app"* aunque la descarga funcione.
   - Ejemplo de historial: `1.0.7+7` → `1.0.10+10` ✅ · `1.0.9+1` ❌ (regresión, no instala sobre `+7`).

2. **Carpeta de Drive**:  
   Carpeta actual: https://drive.google.com/drive/folders/16LfxLzdav-PUsn97EcSnTdcNZcZnYukd  
   Configurada en `lib/core/constants/app_constants.dart` → `driveFolderUrl`.

3. **Archivo `releases.json`** (obligatorio):  
   - Crea un archivo JSON en esa carpeta con la versión publicada y los IDs de los APK.
   - Comparte el archivo con “Cualquiera con el enlace”.
   - Abre el archivo en Drive y copia el ID de la URL:  
     `https://drive.google.com/file/d/ **ESTE_ES_EL_ID** /view`
   - Pega ese ID en `app_constants.dart` → `driveReleasesJsonFileId`.

   Formato de `releases.json`:

   ```json
   {
     "version": "0.0.3",
     "apks": {
       "arm64-v8a": "ID_DEL_APK_arm64",
       "armeabi-v7a": "ID_DEL_APK_armeabi",
       "x86_64": "ID_DEL_APK_x86_64",
       "universal": "ID_DEL_APK_universal"
     },
     "changelog": {
       "v0.0.3": [
         {"arreglo": "Descripción del arreglo"},
         {"caracteristica": "Nueva funcionalidad"},
         {"mejora": "Descripción de la mejora"}
       ]
     }
   }
   ```

   - `version`: versión que quieres ofrecer (ej. `"0.0.3"`).
   - `apks`: al menos uno de `arm64-v8a`, `armeabi-v7a`, `x86_64`, `universal`. La app elige según la arquitectura del dispositivo.
   - `changelog`: opcional; si no lo pones aquí, puedes usar `roadmap.json`.

4. **Archivo `roadmap.json`** (opcional):  
   - Si prefieres tener el changelog en un archivo aparte, créalo en la misma carpeta.
   - Compártelo con “Cualquiera con el enlace” y pon su ID en `driveRoadmapJsonFileId`.

   Formato (mismo que el `changelog` de `releases.json`):

   ```json
   {
     "v0.0.1": [
       {"arreglo": "bla bla"},
       {"caracteristica": "bla bla"}
     ],
     "v0.0.2": [],
     "v0.0.3": [
       {"mejora": "bla bla"}
     ]
   }
   ```

## Nombres de los APK

Puedes nombrar los ficheros como prefieras; lo importante es que en `releases.json` el **valor** de cada clave de `apks` sea el **ID de archivo** de Drive (no el nombre del fichero). Ejemplo de nombres:

- `app-arm64-v8a-release_v0.0.3.apk`
- `app-armeabi-v7a-release_v0.0.3.apk`
- `app-release_v0.0.3.apk`
- `app-x86_64-release_v0.0.3.apk`

Para obtener el ID: sube el APK a la carpeta, ábrelo en Drive y en la URL verás `.../file/d/ID/view`.

## Flujo en la app

- Menú (⋮) → **Versión**.
- Se muestra la versión actual y hay un botón **Comprobar actualizaciones**.
- Si la versión en Drive es mayor, se muestra la lista de mejoras (changelog) y **Actualizar aplicación**.
- Si hay ventas pendientes, se muestra un aviso antes de continuar con la actualización.
- Al actualizar, se descarga el APK adecuado a la arquitectura del dispositivo, se valida y se abre el instalador de Android.

## Si falla la instalación ("No se instaló la app")

1. **versionCode menor** (causa más común): el APK en Drive se generó con un número después del `+` menor o igual al instalado. Regenera con `flutter build apk --release` tras subir el `+N` en `pubspec.yaml`.
2. **Firma distinta**: el APK nuevo debe firmarse con la misma clave que la app instalada (misma máquina / mismo keystore).
3. **Permiso de orígenes desconocidos**: en Android 8+, Ajustes → Instalar apps desconocidas → permitir para Cuadre de Caja.
4. **APK corrupto en Drive**: si el archivo pesa pocos KB, Drive devolvió HTML; vuelve a subir el APK y actualiza el ID en `releases.json`.
