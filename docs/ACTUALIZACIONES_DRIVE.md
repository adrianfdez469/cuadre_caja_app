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

## Credenciales para publicar (OAuth)

El pipeline (`scripts/release.py`) sube los archivos a Drive actuando **como tu cuenta de Google**.
Hace falta autorizar **una vez** en el navegador; después funciona sin intervención.

Las credenciales viven en `.env.local` **en la raíz del repo**, no en tu `$HOME`: son por-proyecto,
así que puedes usar cuentas de Google distintas en proyectos distintos sin que se pisen.

### Setup (una sola vez)

1. En [Google Cloud Console](https://console.cloud.google.com/), con la **Google Drive API**
   habilitada: *APIs & Services → Credentials → Create credentials → OAuth client ID*, de tipo
   **Desktop app**. Copia el client ID y el client secret.

2. Crea tu `.env.local` a partir de la plantilla y pega esos dos valores:

   ```bash
   cp .env.local.example .env.local
   ```

3. Autoriza tu cuenta (abre el navegador — hazlo tú, en una terminal interactiva):

   ```bash
   python3 scripts/release.py auth-login
   ```

   El script levanta un servidor en `127.0.0.1` con un puerto libre, te lleva a la pantalla de
   consentimiento de Google, valida un `state` aleatorio contra CSRF, captura el código y guarda
   `GDRIVE_REFRESH_TOKEN` y `GDRIVE_ACCOUNT_EMAIL` en `.env.local` con permisos 600.

   **Elige la cuenta correcta para este proyecto** — la que tiene permiso de edición sobre la
   carpeta de releases.

4. Comprueba que todo funciona antes de gastar tiempo en un release:

   ```bash
   python3 scripts/release.py auth-check
   ```

   Debe mostrar la cuenta activa y los 5 archivos (los 4 APK y `releases.json`) como `OK, editable`.
   Si la cuenta que responde no coincide con la guardada en `.env.local`, avisa.

### ⚠️ Publica la app OAuth o el token caducará cada 7 días

Mientras el cliente OAuth esté en estado **"Testing"**, Google **invalida el refresh token a los 7
días** y el release fallará con `invalid_grant`. Es exactamente lo que le pasó al token del binario
`gdrive`. Arréglalo en *OAuth consent screen → Publish app*.

### Renovar el token

Si el token muere (o quieres cambiar de cuenta), basta con repetir el paso 3: `auth-login`
reemplaza el `GDRIVE_REFRESH_TOKEN` viejo en su sitio. No hace falta rehacer nada más.

### Alcance de los permisos

Se pide el scope `https://www.googleapis.com/auth/drive`, que da acceso a todo tu Drive. Es el
mínimo que permite **modificar archivos que ya existían**: el scope acotado `drive.file` solo
alcanza a los archivos que la propia app creó, y los APK de la carpeta de releases son anteriores.

## Fallback

Si este proyecto no tiene credenciales OAuth configuradas, el script cae al binario `gdrive` (el
flujo histórico). Funciona, pero depende de un token de usuario que caduca y que solo se renueva
desde una terminal interactiva con `gdrive account add`.

## Nombres de los APK

Puedes nombrar los ficheros como prefieras; lo importante es que en `releases.json` el **valor** de cada clave de `apks` sea el **ID de archivo** de Drive (no el nombre del fichero). Ejemplo de nombres:

- `app-arm64-v8a-release_v0.0.3.apk`
- `app-armeabi-v7a-release_v0.0.3.apk`
- `app-release_v0.0.3.apk`
- `app-x86_64-release_v0.0.3.apk`

Para obtener el ID: sube el APK a la carpeta, ábrelo en Drive y en la URL verás `.../file/d/ID/view`.

## Flujo en la app

- Menú (⋮) → **Versión**. La comprobación es automática al abrir la pantalla (no hay botón de comprobar).
- Si la versión en Drive es mayor, se muestra la lista de mejoras (changelog) y **Actualizar aplicación**.
- Si hay ventas pendientes, se muestra un aviso antes de continuar con la actualización.
- Al actualizar, se descarga el APK adecuado a la arquitectura del dispositivo, se valida y se abre el instalador de Android.

### Reutilización del APK descargado

El APK se guarda con un nombre fijo por versión y arquitectura
(`update_<versión>_<variante>.apk`) en `<applicationSupport>/updates`, no en la caché.
Consecuencias:

- Si Android pide el permiso **instalar apps desconocidas**, el usuario lo concede en Ajustes
  y vuelve a la pantalla, **la instalación continúa sola con el APK ya descargado**: no se
  vuelve a bajar.
- Si cierra la app sin instalar, al volver a la pantalla de Versión el botón dice
  **Instalar ahora** en vez de descargar.
- Al descargar se limpian los APK de versiones anteriores, así que solo queda uno en disco.
- La descarga va a un `.part` que solo se renombra al terminar y validarse: una descarga
  cortada nunca se reutiliza.

Limitación: `releases.json` solo lleva el *versionName*, no el `+build`. Si republicas un APK
distinto con el mismo versionName, quien ya lo descargó se quedaría con el binario viejo; sube
también el versionName al republicar.

## Si falla la instalación ("No se instaló la app")

1. **versionCode menor** (causa más común): el APK en Drive se generó con un número después del `+` menor o igual al instalado. Regenera con `flutter build apk --release` tras subir el `+N` en `pubspec.yaml`.
2. **Firma distinta**: el APK nuevo debe firmarse con la misma clave que la app instalada (misma máquina / mismo keystore).
3. **Permiso de orígenes desconocidos**: en Android 8+, Ajustes → Instalar apps desconocidas → permitir para Cuadre de Caja.
4. **APK corrupto en Drive**: si el archivo pesa pocos KB, Drive devolvió HTML; vuelve a subir el APK y actualiza el ID en `releases.json`.
