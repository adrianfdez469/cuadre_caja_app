---
name: app-release
description: Automates deploying a new release of this Flutter app — bumping version numbers, committing/pushing to git, building release APKs, uploading them to the app's public Google Drive folder, and updating releases.json (the file the app itself polls to check for and download updates). Use this skill whenever the user asks to "deploy", "release", "publish a new version", "ship an update", "cut a release", or gives you a changelog and wants it turned into a new app version. Also use it if the user just says something like "bump the version and release" or pastes a list of fixes/improvements and wants them shipped.
---

# Flutter App Release

Todo lo mecánico del release vive en **`scripts/release.py`** (versiones, commit/push, build,
subida a Drive, merge y validación de `releases.json`). Ese script tiene los asserts que impiden
romper la actualización en producción — **no repliques sus pasos a mano ni edites `releases.json`,
`pubspec.yaml` o `app_constants.dart` tú mismo**.

Tu trabajo es lo que requiere criterio: **redactar el changelog**, **pedir confirmación**, y
**escribir el anuncio de WhatsApp**. Corre siempre desde la raíz del proyecto; nunca preguntes la ruta.

Los IDs de Drive y las rutas de los APK están en `scripts/release_config.json`.

## 0 — Comprobar el acceso a Drive

```bash
python3 scripts/release.py auth-check
```

Hazlo antes de empezar: si las credenciales están rotas, mejor saberlo ahora que tras compilar.
Si sale con código 2, dile al usuario cómo arreglarlo según el backend que reporte
(`docs/ACTUALIZACIONES_DRIVE.md`) y pregúntale si quiere seguir igual — el release se hará local y
quedará listo para publicar después con `retry-upload`.

**`auth-login` lo corre siempre el usuario, nunca tú**: abre un navegador y requiere una persona
delante. Si hace falta, dile que lo lance con `! python3 scripts/release.py auth-login`.

## 1 — Planificar

```bash
python3 scripts/release.py plan            # o --bump minor|major, o --version X.Y.Z
```

Devuelve JSON con la versión actual y la siguiente, la rama, y los commits desde el último bump
(con su `--stat`). Si `commitCount` es 0, amplía con `--since <ref>`.

## 2 — Redactar el changelog

Si el usuario no dio changelog, derívalo de esos commits. Los mensajes de este repo suelen ser
escuetos, así que lee los diffs reales (`git show <sha>`) en vez de fiarte del subject.

Convierte los cambios en frases **en español, de cara al usuario** (dueños de tienda y cajeros, no
desarrolladores). Una frase por ítem — no combines varios cambios en uno. Categorías exactas:
`Mejoras`, `Arreglos`, `Caracteristicas`.

Guárdalo en `build/changelog.json`:

```json
[
  {"Arreglos": "Se arregla un error al sincronizar ventas offline"},
  {"Mejoras": "Se agrega soporte para impresoras térmicas Bluetooth"}
]
```

## 3 — Gate de confirmación (antes de tocar nada)

Muestra al usuario la **versión nueva con build number** (ej. `1.1.14+25`) y el **changelog tal cual
quedará**. Pídele que lo edite o lo confirme. **No ejecutes el paso 4 hasta que apruebe.** Aplica sus
correcciones y vuelve a mostrarlo si el cambio fue grande.

(Los tamaños de los APK no existen todavía — se reportan tras el build, informativamente, sin un
segundo gate.)

## 4 — Ejecutar

```bash
python3 scripts/release.py bump    --version 1.1.14
python3 scripts/release.py commit  --message "<resumen en español>"
python3 scripts/release.py build
python3 scripts/release.py upload
python3 scripts/release.py publish --changelog build/changelog.json
python3 scripts/release.py report
```

- El mensaje de commit es **texto descriptivo en español**, no conventional commits.
  Estilo: `Sube la version a 1.1.14: se arregla la sincronizacion offline y se mejora el escaner`.
- `build` es el **único paso que aborta el release** si falla — surface el error y para.
- Los fallos de Drive **nunca abortan**: se anotan y el flujo continúa hasta el final.

Códigos de salida: `0` todo bien · `1` fallo duro (para y reporta) · `2` release local completo pero
**Drive degradado** (sigue al paso 5 y emite el warning).

Añade `--dry-run` a cualquier paso para ensayarlo sin efectos.

## 5 — Resumen

Resume a partir de `report`: versión + build, qué se commiteó, los 4 APKs con su tamaño, y que los
archivos de Drive se actualizaron **in-place** (fileIds preservados).

### Si `report` salió con código 2 — warning obligatorio

Incluye un bloque destacado en español, imposible de pasar por alto, con:

1. **⚠️ Qué NO se subió**: los archivos exactos y el mensaje de error tal cual.
2. **Consecuencia**: la versión **no está publicada** — la app seguirá viendo la anterior. El bump,
   el commit/push y los APKs locales **sí** están hechos.
3. **Cómo restablecer el acceso**: `python3 scripts/release.py auth-check` da el diagnóstico y dice
   qué cuenta de Google está activa. Si el token caducó, se renueva con `auth-login` — **lo corre el
   usuario**, con `!` en el prompt. Si caduca cada semana, el cliente OAuth sigue en modo "Testing"
   en Google Cloud Console y hay que publicarlo (`docs/ACTUALIZACIONES_DRIVE.md`).
4. **Cómo reintentar sin rehacer el release**: `python3 scripts/release.py retry-upload` — sube solo
   lo que faltó, reusando los APKs ya construidos y el `releases.json` ya validado en
   `build/releases.json`.
5. **Pregúntale si quiere que reintentes** una vez restablecido el acceso. No reintentes por tu cuenta.

## 6 — Anuncio de WhatsApp

Lo último que emites: un anuncio en español **listo para pegar en el grupo de WhatsApp**, en su
propio bloque de código y sin nada más dentro.

- Formato WhatsApp: `*negrita*` con un solo asterisco, emojis con gusto. Nada de `**`, `#` ni
  encabezados Markdown — no renderizan.
- Tono alegre y de cara al usuario. Traduce el changelog a beneficios, no a jerga técnica.
- Estructura: apertura con la versión, highlights agrupados en viñetas con emoji (✨ mejoras,
  🐛 arreglos, 🚀 nuevo), y cierre diciendo que la actualización se instala sola al abrir la app.
- Conciso: unas pocas viñetas, no el changelog crudo. Fusiona lo trivial.

```
🎉 *¡Nueva actualización disponible!* 🎉
Versión *1.1.14* ya está lista 📲

✨ *Novedades:*
• Ahora puedes cobrar en varias monedas
• Ventas más rápidas en el punto de venta

🐛 *Arreglos:*
• Corregimos un error al sincronizar ventas sin internet

La actualización se instala sola al abrir la app 🙌 ¡Gracias por usar Cuadre Caja!
```

Si Drive falló (código 2), genera el anuncio igual pero **advierte al usuario que no lo envíe** hasta
que los archivos estén realmente subidos.

## Reglas que el script ya hace cumplir (no las duplicues a mano)

- El build number siempre sube en 1; `appVersion` y `pubspec.yaml` quedan sincronizados.
- Los archivos de Drive se actualizan in-place — **nunca** borrar y volver a subir (cambiaría el
  fileId y rompería la auto-actualización).
- Las entradas viejas del changelog nunca se tocan; la app muestra todas las versiones intermedias.
- El push va a la **rama actual**, no a `main` a ciegas.
- Un fallo de Drive por permisos/autenticación no se reintenta ni se soluciona por vías alternativas.
- Las credenciales de Drive son **OAuth por proyecto**, en el `.env.local` de este repo (o el binario
  `gdrive` como fallback). **Nunca imprimas ni pidas el contenido de `.env.local`**, y nunca lo
  añadas a git. `auth-login` lo corre siempre el usuario, nunca tú.
