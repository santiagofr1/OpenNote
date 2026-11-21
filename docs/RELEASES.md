# Releases de OpenNote

Cada push a `main` compila, prueba y publica automáticamente un APK firmado en GitHub Releases.
Los pushes que solo tocan documentación (`**.md`, `docs/**` o `.github/ISSUE_TEMPLATE/**`) no
disparan una release. También se puede lanzar a mano desde **Actions → Release → Run workflow**.

## Cómo funciona

El workflow `.github/workflows/release.yml`:

1. Ejecuta `flutter pub get`, `flutter analyze --no-fatal-infos` y `flutter test`.
2. Calcula la versión con el número de ejecución de GitHub Actions:
   - `versionName`: `1.0.<run_number>` (por ejemplo, `1.0.42`).
   - `versionCode`: `<run_number> + 100` (por ejemplo, `142`), siempre mayor que el `1` local.
3. Firma el APK con la clave de release guardada en los secretos del repositorio.
4. Publica el APK como `OpenNote-v1.0.<run_number>.apk` en un GitHub Release con el tag
   `v1.0.<run_number>`, usando como notas los asuntos de los commits desde el tag `v*` anterior.
5. Marca esa release como la última (`make_latest`).

Si falta el secreto del keystore, el job falla a propósito. Nunca se publica una release firmada con
la clave de debug.

## Limpieza de releases viejos

Al final del job, el paso "Podar releases viejos" corre `tool/podar_releases.sh`, que deja solo los
últimos 5 releases (`KEEP=5` en el paso) y borra el resto con `gh release delete <tag> --cleanup-tag --yes`
(borra también el tag). Reglas:

- Solo toca tags `^v1\.0\.[0-9]+$`; ignora drafts, prereleases y cualquier otro tag.
- Ordena por fecha de creación y nunca borra el marcado Latest ni el recién publicado (`CURRENT_TAG`).
- Corre solo si la publicación salió bien. Si un borrado falla, avisa con un warning y sigue con el resto;
  el paso es `continue-on-error`, así que no tumba el workflow.
- Usa `GH_TOKEN` (`github.token`) y el permiso `contents: write` que el workflow ya tiene.
- La app solo consulta el último release, así que el aviso de actualización no se ve afectado.

Para probar la selección sin borrar nada:
`gh release list --json tagName,createdAt,isLatest,isDraft,isPrerelease --limit 200 | DRY_RUN=1 tool/podar_releases.sh`

## Secretos del repositorio

Hay que configurar estos cuatro secretos en **Settings → Secrets and variables → Actions → New
repository secret**:

| Secreto | Contenido |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | El archivo `release.jks` codificado en base64. |
| `ANDROID_KEYSTORE_PASSWORD` | La contraseña del keystore. |
| `ANDROID_KEY_ALIAS` | El alias de la clave (por ejemplo, `opennote`). |
| `ANDROID_KEY_PASSWORD` | La contraseña de la clave. |

### 1. Crear el keystore (solo la primera vez)

Con el JDK 21:

```bash
~/Android/jdk21/bin/keytool -genkey -v \
  -keystore release.jks \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -alias opennote
```

`keytool` pide la contraseña del keystore, los datos del certificado y la contraseña de la clave.
Se puede usar la misma contraseña para ambas, pero conviene guardar las dos.

### 2. Codificar el keystore en base64

```bash
base64 -w0 release.jks > release.jks.base64
```

El archivo resultante es una sola línea larga. Ese es el valor de `ANDROID_KEYSTORE_BASE64`.

### 3. Cargar los secretos con GitHub CLI

```bash
gh secret set ANDROID_KEYSTORE_BASE64 < release.jks.base64
gh secret set ANDROID_KEYSTORE_PASSWORD
gh secret set ANDROID_KEY_ALIAS
gh secret set ANDROID_KEY_PASSWORD
```

Los tres últimos comandos piden el valor de forma interactiva, así no queda en el historial del
shell. También se pueden cargar desde la web de GitHub.

## Backup del keystore

**Guardá una copia privada y segura de `release.jks`, su alias y sus contraseñas.** Si se pierde la
clave:

- No se puede publicar una actualización que Android acepte sobre la app ya instalada.
- Habría que publicar una app nueva con otro `applicationId`, y los usuarios perderían la
  continuidad de las actualizaciones.

No subas el keystore ni `android/key.properties` al repositorio: ya están en `.gitignore`. El secreto
de GitHub es la copia que usa CI; el backup privado es la copia de recuperación.

## Primera instalación de una release firmada

La app de release se instala sobre una instalación anterior **solo si ambas están firmadas con la
misma clave**. Si en la tablet hay una versión firmada con debug (por ejemplo, instalada con
`./build_install.sh`), Android rechaza la primera release firmada con la clave nueva.

Antes de instalar esa primera release:

1. Hacé un backup de los cuadernos desde la app.
2. Desinstalá OpenNote en la tablet.
3. Instalá el APK de la release.

La desinstalación borra los datos locales de la app; por eso el backup es obligatorio. Después de
esta única migración, las siguientes releases se actualizan normalmente sin desinstalar.

## Probar la firma localmente

Para compilar una release local con la clave real, creá `android/key.properties` (no se versiona):

```properties
storeFile=/ruta/absoluta/a/release.jks
storePassword=...
keyAlias=opennote
keyPassword=...
```

Si el archivo no existe, `android/app/build.gradle.kts` usa la firma de debug para que
`./build_install.sh` y `flutter run --release` sigan funcionando en desarrollo.
