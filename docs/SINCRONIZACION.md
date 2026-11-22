# App de PC y sincronización

Investigación para el punto 17 de [PENDIENTES.md](../PENDIENTES.md). La decisión tomada (Google Drive) y su diseño están en
"Decisión: Google Drive", antes de las fuentes; lo demás es la investigación previa.
Fecha de la investigación: 2026-11-20.

Las fuentes están listadas al final (sección 6) con números entre corchetes, por ejemplo `[2]`.
Lo que no pude confirmar con una fuente leída está marcado **(sin confirmar)**.

## Punto de partida: cómo se guarda hoy

Lo que hay en el código (`lib/data/storage.dart`, `lib/data/sheet_codec.dart`) y que condiciona todo lo demás:

- **Un cuaderno es una carpeta.** Adentro hay `notebook.json` (orden de hojas, `rev`, `updated`, marcador,
  fondo, papel, espaciado) y `sheets/<hoja>.sheet` (binario, un archivo por hoja). Las imágenes y audios van en
  `media/`, compartidos por todos los cuadernos. Hay que sincronizar `media/` también, no solo las hojas.
- **`rev` y `updated` son locales.** `rev` sube en cada guardado de ese dispositivo (`_saveNow`) y `updated`
  es la hora del reloj de ese dispositivo. Dos tablets pueden tener la misma hoja con `rev` 5 y contenidos
  distintos. Solos no sirven para detectar un conflicto: falta saber sobre qué versión editó cada lado.
- **Ya hay hash por hoja.** `Storage` guarda el md5 de cada `.sheet` como se escribió por última vez
  (`_DiskState`). Sirve para saber qué cambió de este lado sin releer todo.
- **Los trazos tienen `id`** (prefijo `s` + 12 hex al azar, `values.dart`). La goma quita trazos enteros
  (`page_editor.dart`, `_eraseAt`): no los parte. Eso simplifica mucho el borrado entre dispositivos.
- **La escritura es atómica** (archivo temporal + rename) y solo se escriben las hojas que cambiaron.
- **En PC la carpeta base es `Documentos/apuntes`.** `_defaultBase()` usa `getExternalStorageDirectory` solo en
  Android; en el resto cae en `getApplicationDocumentsDirectory()`. La ruta exacta por sistema operativo no la
  confirmé con la doc de `path_provider` [14].
- **El repo tiene solo las carpetas `android/` y `linux/`.** No hay `windows/` ni `macos/`: habría que
  agregarlas (`flutter create --platforms=...`, sin confirmar el comando exacto contra la doc).

---

## 1. App de PC con Flutter desktop

### 1.1 Entrada: lápiz, mouse y tabletas

El punto crítico para OpenNote es que el lápiz de una tableta Wacom/Huion en PC llegue como
`PointerDeviceKind.stylus` y con presión. Hoy en Android funciona porque `ink.dart` lo decide por ese tipo.

**Linux (mejoró mucho en 2026).**
- El issue #63209 de Flutter pedía presión y `PointerDeviceKind` para el lápiz en Linux desde 2020. Se cerró el
  28/08/2026 citando el PR #186831, "Improve stylus support on linux", que entró en el roll-up del 1/07/2026. El
  PR agrega presión, inclinación, rotación y botones del lápiz en Linux [1][2].
- Lo probó su autor con un Wacom en Fedora/KDE sobre Wayland [2]. **(sin confirmar)**: X11, GNOME, tabletas
  Huion y si esa versión ya está en el canal que usa el proyecto (revisar `flutter --version`).
- Antes, Saber (app Flutter) reportó en Linux que el lápiz se detectaba como dedo y que no había presión. Se
  cerró como "not planned" en 2022 [3]. Es historia, pero muestra por qué hay que probar en cada máquina.

**Windows (sin solución confirmada).**
- No encontré un cambio en el engine. Una consulta de abril de 2024 en `dart-windows/win32` dice que el soporte
  oficial de Flutter en Windows no incluye tabletas. No tuvo respuestas [4].
- Stylet (paquete de terceros) saca la presión en Windows del driver Wintab, no de los eventos de puntero [6].
- Conclusión: en Windows hay que probar el lápiz real antes de decidir. Puede llegar como mouse o sin presión
  **(sin confirmar)**. Si no llega, la opción es un plugin de terceros o código nativo.

**macOS (sin solución confirmada).**
- Saber #1218 (macOS Sonoma, Wacom Intuos BT): la presión no funciona y el lápiz se comporta como clic izquierdo.
  Se cerró como "not planned" en junio de 2024 [5].
- Stylet dice que la presión sale de AppKit [6]. No encontré un issue de Flutter sobre macOS **(sin confirmar)**.

**Android (para comparar, no es la PC).** El issue #196867 (noviembre de 2026) reporta que en Android se pierden
muestras históricas del trazo y la curva se ve recta. El PR de arreglo seguía abierto en la fecha del issue [7].
Es un tema de la tablet que conviene seguir porque afecta la calidad del trazo.

**Mouse.** El botón derecho ya borra (`TECNICO.md`, "Tablets y lápices"). Con mouse la presión vale 1
**(sin confirmar)**.

**Recomendación de entrada:** Linux primero. Para Windows y macOS, probar con un lápiz real y decidir después
entre un plugin (Stylet es nuevo: publicado hace 43 días, 0 likes [6]) o código nativo.

### 1.2 Atajos de teclado

- Ya existen Ctrl+B/I/U y Tab/Shift+Tab en el texto (`TECNICO.md`).
- Falta relevar cuáles existen para deshacer/rehacer, guardar, borrar la selección, copiar y pegar. No lo hice.
- Flutter resuelve atajos con `Shortcuts` y `Actions` **(sin confirmar: no leí la doc)**.

### 1.3 Rutas de datos

- `path_provider` declara soporte en Linux (cualquier versión), Windows 10+ y macOS 10.15+ [14].
- Lo que cambia para el usuario: en Android los datos están en el almacenamiento externo de la app (se
  respaldan por USB). En PC quedan en Documentos. Eso es bueno: una carpeta visible que Syncthing, Drive o
  Nextcloud pueden sincronizar sin tocar la app.
- Las rutas concretas por sistema (por ejemplo `~/Documents` en Linux) **(sin confirmar)**: hay que imprimirlas
  en una prueba.

### 1.4 Plugins de `pubspec.yaml` en desktop

Estado según la página de cada paquete en pub.dev [14]. "Sin confirmar" significa que no lo revisé.

| Paquete (pubspec) | Linux | Windows | macOS | Notas |
|---|---|---|---|---|
| `material_ui` ^1.1.0 | sí | sí | sí | Oficial de Flutter. |
| `path_provider` ^2.1.6 | sí | sí | sí | Rutas: ver 1.3. |
| `file_picker` ^13.4.0 | sí | sí | sí | Carpeta: no en web. |
| `image_picker` ^1.2.4 | parcial | parcial | parcial | Desktop va por `image_picker_linux/windows/macos` (0.2.x). Sin ancho/alto máximo en desktop. |
| `printing` ^5.15.1 | sí | sí | sí | PDF. |
| `share_plus` ^13.3.1 | parcial | parcial | sí | Linux: solo texto y URL, **no archivos**. Windows: URL como texto. |
| `record` ^7.2.0 | parcial | parcial | parcial | Linux necesita `parecord`, `pactl` y `ffmpeg` instalados. Windows y macOS por paquetes aparte; macOS sin confirmar. |
| `audioplayers` ^6.8.1 | sí | sí | sí | |
| `dynamic_color` ^2.1.0 | sí | sí | sí | En Linux toma el color del portal XDG o del tema GTK. |
| `package_info_plus` ^10.2.2 | sin confirmar | sin confirmar | sin confirmar | No lo revisé. |
| `pdf`, `crypto`, `material_symbols_icons`, `cupertino_icons` | sin confirmar | sin confirmar | sin confirmar | No los revisé. `pdf` y `crypto` deberían ser Dart puro (sin confirmar). |

Lo que bloquea o cambia algo: `share_plus` en Linux (no se puede compartir un archivo) y `record` en Linux (hay
que pedir `ffmpeg`). Ninguno de los dos impide la versión para PC; hay que avisar o desactivar la función.

### 1.5 Empaquetado

**Linux.**
- La doc de Flutter describe el empaquetado con Snap (`snapcraft`) [15]. AppImage, deb y rpm aparecen solo como
  herramientas de terceros (fastforge) y Flatpak como otra herramienta (flatpak-flutter) [15].
- Sugerencia: AppImage primero (un archivo, sin tienda ni permisos de sistema). Después Flathub, si se quiere.
  **(sin confirmar)**: el mejor formato para esta app; no revisé `linux/` por dentro (ID de la app, etc.).

**Windows.**
- La doc de Flutter describe MSIX (con el paquete `msix`, configurado con `msix_config` en `pubspec.yaml`) y
  publicación en Microsoft Store con la CLI `msstore` [16].
- Instalador clásico (MSI o Inno Setup): no está en la doc **(sin confirmar)**.
- La doc no menciona firma de código [16]. Sin firma, Windows muestra advertencias al instalar **(sin confirmar)**.

**macOS.**
- La doc de Flutter cubre firma con Xcode y App Store, pero no notarización ni DMG [17].
- Apple documenta la notarización con `notarytool` y `stapler` para software fuera de la App Store, firmado con
  Developer ID [18]. Esto lo leí por resumen de búsqueda, no la página completa **(sin confirmar detalles)**.
- Requiere cuenta de Apple Developer **(sin confirmar costo)**.

**GitHub Actions.**
- Runners disponibles: `ubuntu-latest`, `windows-latest` y `macos-latest` (arm64) [19].
- Hoy el workflow de releases solo hace Android (`docs/RELEASES.md`). Se pueden agregar jobs por sistema con
  `flutter build linux --release`, `flutter build windows` y `flutter build macos`.
- Firma de Windows y macOS: los certificados van como secretos del repo **(sin confirmar detalles)**.

### 1.6 Esfuerzo estimado

- **Linux: medio.** Build de release, prueba del lápiz con la versión de Flutter del proyecto, AppImage, job de CI.
- **Windows: grande.** Agregar la carpeta `windows/`, resolver el lápiz (probablemente con un plugin), MSIX y firma.
- **macOS: grande.** Cuenta de Apple, firma Developer ID, notarización, prueba del lápiz (dudosa) y un Mac
  para probar **(sin confirmar qué Mac hay disponible)**.

---

## 2. Sincronización en la LAN (red de casa) segura

Requisito: nadie más en la misma red puede ver el contenido ni conectarse. Un dispositivo no emparejado no
puede ni establecer la conexión.

### 2.1 Cómo lo resuelven otros

**KDE Connect.**
- Cada dispositivo tiene un certificado autofirmado. La identidad es la clave pública y la firma del certificado,
  no el nombre. Desde la versión 1.0 usa *trust on first use* (TOFU), como SSH [7].
- El emparejamiento depende de que el usuario compare las huellas en los dos equipos. Esa comparación no está
  forzada por la app [7].
- CVE-2020-26164: el nombre del dispositivo se anuncia en UDP sin cifrar. Un atacante en la LAN puede hacerse pasar
  por un equipo conocido y pedir emparejamiento. La corrección muestra el SHA-256 de las dos claves públicas
  juntas: primero 8 caracteres hex y el resto detrás de "ver clave" [8].
- Lección: el primer emparejamiento es el punto débil. No confiar en el nombre ni en el descubrimiento.
- Un paquete Go de terceros dice que los certificados son RSA 2048 con 10 años de validez y CN igual al ID del
  dispositivo [9]. Es una implementación de terceros; no lo confirmé contra el código oficial.

**Syncthing.**
- El Device ID es el SHA-256 del certificado TLS. Cada conexión compara ese ID contra una lista fija de equipos
  aceptados; si no está, corta [10].
- El descubrimiento local manda cada 30 s el ID y el puerto por broadcast/multicast. Un atacante en la LAN ve qué
  equipos corren Syncthing y sus IDs, pero no puede conectarse sin estar en la lista [10].
- Quien tenga las claves TLS y el archivo de configuración puede hacerse pasar por el equipo. Por eso recomiendan
  proteger la carpeta de configuración [10].

**LocalSend.**
- En modo HTTPS, la huella es el SHA-256 del certificado [11].
- El descubrimiento va por UDP multicast al grupo `224.0.0.167`, puerto `53317` [11].
- La especificación marca el fingerprint como "ignorado" en `/register` y `/prepare-upload` en HTTPS, y no
  describe que el receptor verifique la huella [11]. Es decir: cifra, pero no ata la identidad.
- Lección: la verificación de la huella tiene que hacerse en los dos lados. Hay un PIN opcional para las
  transferencias [11].

### 2.2 Diseño propuesto para OpenNote

**Identidad (una vez por instalación).**
- Se genera un certificado X.509 autofirmado con `basic_utils`, que genera certificados autofirmados RSA y EC en
  Dart puro [20]. EC P-256 es lo más liviano **(sin confirmar que dart:io lo acepte en todas las plataformas)**.
- El certificado y su clave quedan en la carpeta privada de la app. En Android no evalué el almacén seguro
  (Keystore) **(sin confirmar)**.
- El ID del dispositivo es el SHA-256 del certificado, igual que Syncthing y LocalSend.
- Vencimiento largo: la implementación de terceros de [9] usa 10 años. Recomendación de vencimiento **(sin confirmar)**.

**Emparejamiento (una sola vez por par de dispositivos).**
1. En el dispositivo A, "Emparejar otro dispositivo" muestra un QR con: versión, nombre, huella SHA-256 del
   certificado de A, un secreto de un solo uso de 128 bits, y IP:puerto de A. Vence a los 2 minutos.
2. El dispositivo B escanea el QR. **Quien escanea tiene que ser Android, iOS o macOS**, porque `mobile_scanner`
   no soporta Linux ni Windows [21]. Si B es una PC, es A (la tablet) la que escanea el QR que muestra la PC.
   Si las dos son PC, hace falta otro camino (pegar un texto o un código de 8 dígitos). No está diseñado todavía.
3. B abre TLS hacia A y compara el certificado de A con la huella del QR. Si no coincide, corta. Esto evita el
   intermediario.
4. B manda su certificado y un HMAC-SHA256 del secreto sobre las dos huellas. A verifica el HMAC y, si es válido,
   guarda la huella de B. A responde con su propio HMAC y B guarda la de A **(diseño, sin confirmar contra un
   protocolo existente)**. El paquete `crypto`, que ya está en `pubspec.yaml`, trae HMAC y SHA-256 **(sin
   confirmar la API exacta)**.
5. El secreto se quema al usarlo o al vencer. Un atacante en la LAN ve solo el tráfico TLS: no puede hacerse
   pasar por A (huella distinta) ni completar el HMAC (no conoce el secreto).
6. Riesgo que queda: quien fotografía el QR puede emparejarse durante los 2 minutos. Mitigación: el QR se muestra
   solo cuando el usuario entra a "Emparejar", y A pide confirmar "¿Aceptar a <nombre>?" antes de guardar.

**Conexión diaria (TLS mutuo con certificados fijados).**
- Servidor: `HttpServer.bindSecure` con `requestClientCertificate: true` [12]. El `SecurityContext` lleva el
  certificado propio y los certificados de todos los emparejados como raíces de confianza
  (`setTrustedCertificatesBytes`) [13].
  **(sin confirmar)**: que dart:io verifique el certificado del cliente contra esa lista. Hay que probarlo con
  dos equipos.
- Cliente: `HttpClient` con el certificado propio (`useCertificateChainBytes` y `usePrivateKeyBytes` [13]) y
  `badCertificateCallback`. Ese callback se llama cuando el certificado del servidor no se puede validar contra
  las raíces de confianza, y devuelve `true` para aceptar la conexión [13]. Ahí se compara la huella del servidor
  con la guardada.
- Para ver la huella del cliente después del handshake del lado servidor hace falta `HttpRequest.certificate`
  **(sin confirmar)**.
- Un equipo no emparejado no está en la lista: el handshake falla.

**Descubrimiento (mDNS / DNS-SD).**
- `bonsoir` anuncia y busca servicios (Android, iOS, Linux, macOS y Windows) [22].
- El anuncio lleva un nombre aleatorio por emparejamiento, nunca la huella.
- El descubrimiento da IP y puerto, nunca confianza. Si mDNS no funciona, el QR ya trae IP:puerto.
- En Android el Wi-Fi filtra los paquetes multicast por defecto. Para recibirlos hace falta un `MulticastLock`
  [23]. No revisé si `bonsoir` lo hace solo **(sin confirmar)**.

**Revocar (desde ajustes).**
- Ajustes > Dispositivos: se borra la huella de la lista, se reconstruye el `SecurityContext` y se cortan las
  conexiones activas.
- Si se pierde una tablet, se revoca desde la otra. Eso no alcanza para la clave de la nube (sección 3): hay que
  rotarla.
- "Restablecer identidad" rompe todos los emparejamientos: hay que volver a emparejar.

### 2.3 Riesgos

- **Android en segundo plano.** Según el resumen de la doc de energía de Android, las apps en primer plano no
  tienen límites de ejecución; en segundo plano aplican Doze y App Standby [24]. La sincronización va al abrir la app, al volver a
  primer plano, poco después de cada guardado y cada 45 s con la app visible (ver "Cuándo sincroniza"). Para sincronizar en continuo haría falta un servicio en primer plano con notificación
  **(sin confirmar cómo lo trata el sistema en la práctica)**.
- **Redes que bloquean multicast.** Wi-Fi de invitados, puntos de acceso con aislamiento de clientes
  **(sin confirmar: no lo busqué)**. Fallback: IP:puerto en el QR o escribir la IP a mano.
- **Robo de la clave.** La carpeta privada de la app es el único lugar con la identidad. En PC, el archivo debe
  tener permisos solo del usuario **(sin confirmar en Windows)**.
- **Certificado nuevo rompe el emparejamiento.** Si se regenera, hay que emparejar de nuevo. Por eso el
  vencimiento tiene que ser largo y la app debe avisar antes.

### 2.4 Paquetes Dart/Flutter para cada pieza (estado)

| Pieza | Paquete | Plataformas | Estado (según pub.dev) |
|---|---|---|---|
| Descubrimiento | `bonsoir` 7.1.6 | Android, iOS, Linux, macOS, Windows [22] | Publicado hace 26 días, 150 puntos. |
| Descubrimiento | `nsd` 5.0.1 | Android, iOS, macOS, Windows. **Sin Linux** [25] | Publicado hace 7 meses. |
| Descubrimiento | `multicast_dns` 0.3.3+1 | Android, iOS, Linux, macOS, Windows [26] | Publicado hace 5 meses, publisher verificado (flutter.dev). Si registra servicios: **(sin confirmar)**. |
| TLS | `dart:io` (SDK) | Todas | No es paquete: `SecurityContext`, `bindSecure`, `badCertificateCallback` [12][13]. |
| Certificados | `basic_utils` 5.8.2 | Dart puro [20] | Publicado hace 21 meses. Genera certificados autofirmados RSA y EC. |
| Criptografía | `pointycastle` 4.0.0 | Android, iOS, Linux, macOS, web, Windows [27] | Publicado hace unos 21 meses, publisher verificado (bouncycastle.org). HKDF, Argon2, ECDSA. |
| Criptografía | `cryptography` 2.9.0 | Nativo en Android, iOS, macOS y web; Dart puro como respaldo [28] | Publicado hace unos 12 meses, publisher verificado (dint.dev). Argon2id, XChaCha20-Poly1305, Ed25519, X25519, HKDF. Revisar si hay 3.x. |
| HMAC / SHA-256 | `crypto` 3.0.8 (ya en `pubspec.yaml`) | **(sin confirmar)** | Para huellas y el HMAC del emparejamiento. |
| Escanear QR | `mobile_scanner` 7.5.0 | Android, iOS, macOS, web. **Sin Linux ni Windows** [21] | Publicado hace 19 días, publisher verificado. |
| Mostrar QR | `qr_flutter` 4.1.0 | Android, iOS, Linux, macOS, web, Windows [29] | Publicado hace 3 años. Estable, pero sin releases recientes. |

---

## 3. Fuera de casa

Hay tres caminos. Syncthing ya es un camino seguro de dispositivo a dispositivo (sección 2). Google Drive y
WebDAV son nubes, y en ellas hace falta cifrado de extremo a extremo.

### 3.1 Opciones

**Google Drive.**
- `googleapis` 19.0.0 trae Drive v3 y está publicado hace 8 días [30].
- `google_sign_in` soporta Android, iOS, macOS y web. Linux y Windows no figuran en su página [31]. En PC hay
  que hacer el login por navegador: cliente de tipo "Desktop app", PKCE y redirección a un loopback
  (`http://127.0.0.1:puerto`). Google rechaza los webviews embebidos [32]. Eso son dos caminos de login.
- `appDataFolder`: carpeta oculta, solo para la app que la creó; el usuario no la ve en Drive y otras apps no la
  leen. Usa el scope `drive.appdata`, que no es sensible [33].
- Google igual puede leer lo que se sube sin cifrado propio: hace falta la capa E2E.
- Pros: cuenta que muchos ya tienen, sin servidor propio. Contras: dependencia de Google, dos caminos
  de login, y la verificación del cliente OAuth **(sin confirmar)**.

**WebDAV (Nextcloud).**
- Endpoint: `https://<servidor>/remote.php/dav/files/<usuario>/`. Recomiendan contraseña de aplicación y HTTPS
  [34].
- `webdav_client` 1.2.2 soporta Android, iOS, Linux, macOS y Windows [35]. Su última versión es de hace unos 2 años
  y el publisher no está verificado: riesgo de mantenimiento. Podría ser más simple hacer las llamadas WebDAV
  directo con `dio` o `http` **(sin confirmar)**.
- Pros: el servidor es del usuario, no hay OAuth. Contras: hay que tener servidor. Sin E2E, el servidor ve el
  contenido.

**Syncthing instalado aparte.**
- OpenNote solo usa una carpeta; Syncthing sincroniza entre equipos con TLS y lista de IDs [10].
- No hay nube de por medio, así que no hace falta E2E. Syncthing tiene un modo de dispositivos "no confiables"
  con cifrado **(sin confirmar: no lo leí)**.
- Contras: hay que configurarlo en cada equipo. En Android corre como app aparte **(sin confirmar cómo se
  comporta en segundo plano)**. La carpeta privada de OpenNote en Android puede no ser accesible desde otra app
  **(sin confirmar: hay que probarlo con la ruta actual)**.
- Conflictos: Syncthing, cuando dos equipos cambian el mismo archivo, guarda una copia con nombre
  `*.sync-conflict-*` **(sin confirmar: no leí la doc de conflictos)**. OpenNote tendría que ignorarlos o
  tratarlos (sección 4).

### 3.2 Cifrado de extremo a extremo para Drive y WebDAV

Esquema propuesto:

- **Frase de paso** que elige el usuario, y de ahí una **clave maestra de 32 bytes** con **Argon2id**. RFC 9106
  recomienda Argon2id si no sabés cuál usar, y da dos opciones: `t=1, m=2 GiB, p=4` (muy pesada para una tablet) y
  `t=3, m=64 MiB, p=4` para equipos con poca memoria [36]. Para la tablet, la segunda. Hay que medirla en la
  Galaxy Tab S6 Lite antes de fijarla **(sin confirmar la RAM de esa tablet)**.
- **Sal** aleatoria de 16 bytes, guardada en un archivo público `vault.json` en la nube. La sal no es secreta.
- **Por cada archivo:** XChaCha20-Poly1305 con nonce aleatorio de 24 bytes. libsodium dice que los 192 bits del
  nonce permiten nonces aleatorios sin riesgo práctico de repetición [37]. `cryptography` trae ese algoritmo
  [28].
- **Datos asociados (AAD):** ID del archivo y número de versión. Así un archivo cifrado no sirve en otro lugar
  **(diseño, sin confirmar contra una implementación)**.
- **Nombres:** los archivos se llaman por ID aleatorio. El índice (nombres de cuadernos, orden) va cifrado en un
  archivo propio.
- **Lo que la nube ve igual:** cantidad de archivos, tamaños y fechas.
- **Lo que la nube no puede leer:** el contenido ni los nombres.
- **Limitación:** la nube puede devolver una versión vieja que sigue siendo válida (rollback). Mitigación posible:
  número de versión en el AAD y un manifiesto firmado. **Sin resolver.**
- **Pérdida de la frase = pérdida de los datos en la nube.** No hay recuperación. Esto hay que decirlo en la
  pantalla de configuración.
- **Encaja con lo que ya existe:** solo se suben las hojas que cambiaron (el guardado ya lo calcula). Cada
  `.sheet` se cifra entero, así que una hoja cambiada se sube completa.

### 3.3 Cómo se comparte la clave entre dispositivos

Respuesta corta: **el QR no debe llevar la clave maestra en claro.**

Opciones:

- **(a) Dentro de la LAN:** el emparejamiento ya tiene un canal TLS verificado (sección 2). La clave maestra viaja
  por ese canal, una vez. **Recomendada para la LAN.**
- **(b) Fuera de la LAN o sin emparejar:** el dispositivo nuevo escribe la frase de paso, deriva la clave con
  Argon2id y lee la sal de `vault.json`. **Recomendada para la nube.**
- **(c) QR con la clave envuelta:** el QR lleva la clave cifrada con una clave derivada de la frase. Sola, una
  foto del QR no alcanza. Pero no suma nada frente a (b): si el dispositivo nuevo ya tiene la frase, puede derivar
  la clave sin QR. **No recomendada.**

---

## 4. Conflictos

### 4.1 Qué pasa hoy si se edita la misma hoja en los dos lados

Con el formato actual no hay forma confiable de saber si los dos lados editaron sobre la misma versión. `rev` y
`updated` son locales (sección "Punto de partida"). Una sincronización de carpeta simple dejaría que el último
archivo que llega pise al otro, sin avisar.

Para detectarlo hace falta guardar, por hoja, **la última versión que se sincronizó** (su hash, o el `rev` del
otro equipo). Eso es un campo nuevo y opcional en `notebook.json`, como ya se hizo con `z` y `spacing`.

### 4.2 Opciones

**(a) Guardar las dos versiones (copia de conflicto).**
- Si los dos lados cambiaron respecto a la última versión sincronizada, la versión que llega del otro se guarda
  como hoja nueva "(conflicto)". La local queda donde estaba.
- Pro: no se pierde nada. Simple. Se resuelve con la UI que ya existe (una hoja más).
- Contra: hojas duplicadas que el usuario limpia a mano. Dos cambios en partes distintas de la misma hoja también
  se toman como conflicto.

**(b) Última escritura gana (por `updated`).**
- Pro: no hay que hacer nada.
- Contra: se pierden trazos en silencio. Depende de los relojes de cada tablet, que pueden estar desfasados. **No
  recomendada.**

**(c) Fusionar por id de trazo, con lápidas.**
- Se unen los trazos de los dos lados. Los borrados se guardan como una lista de ids borrados (lápidas). Como la
  goma borra trazos enteros, la lápida es solo el id.
- Contra: hay varios problemas que resolver antes:
  - El orden de capas (`z`) es la posición 0..n-1 y se renumera en cada guardado (`encodeSheet`). No es estable
    entre dispositivos; hay que pasarlo a un orden estable **(diseño pendiente)**.
  - Un texto con formato (`TextBlock`) es un objeto entero. Dos ediciones del mismo bloque son un conflicto a nivel
    bloque.
  - El fondo, el papel, el espaciado, el marcador y el título viven en `notebook.json`: harían falta reglas por
    campo.
  - Una hoja borrada en un lado y editada en el otro.
  - El deshacer no se sincroniza.
  - Los medios (`media/`) tienen nombres con id único, así que no chocan. Pero hay que sincronizarlos también.

### 4.3 Recomendación

- **Para empezar: (a).** No pierde datos, es simple y la UI ya sabe mostrar hojas.
- **A futuro: (c) para los trazos**, cuando estén resueltos el orden estable de capas y el criterio para textos y
  hojas. Los ids de trazo son únicos (prefijo + 12 hex) y el borrado es de trazo entero, así que la parte de
  trazos es la más barata.

Esfuerzo de (a): campo de base por hoja en `notebook.json`, detección al cargar y al guardar, hoja "(conflicto)",
y el manejo de los `*.sync-conflict-*` de Syncthing **(sin confirmar)**.

---

## 5. Tabla comparativa

| Opción | Seguridad | Comodidad | Esfuerzo | Dependencias y riesgos |
|---|---|---|---|---|
| **Carpeta + Syncthing** (instalado aparte) | Alta: TLS y lista de IDs [10]. Se ve que el equipo corre Syncthing. | Media: parear una vez en Syncthing, sin cuentas. Fuera de casa, depende de que los equipos se encuentren **(sin confirmar)**. | Chico a medio (OpenNote: elegir carpeta y conflictos). | Syncthing en todos los equipos. Carpeta accesible desde Android **(sin confirmar)**. |
| **LAN propia** (QR + TLS mutuo + mDNS) | Alta si se hace bien. El punto débil es el primer emparejamiento (CVE-2020-26164 [8]). | Alta: QR una vez, sin cuentas. Solo en la misma red y con la app abierta. | Grande. | `bonsoir`, `basic_utils`, `crypto` o `cryptography`, `dart:io`, `mobile_scanner` (no escanea en PC), `qr_flutter`. |
| **Google Drive + E2E** | Google no lee el contenido; sí ve metadatos. | Alta: sin servidor, login con Google. | Grande. | `googleapis`; login propio en PC; `cryptography`. |
| **WebDAV (Nextcloud) + E2E** | Igual que Drive, pero el servidor es propio. | Media: hay que tener un servidor. | Grande. | `webdav_client` (poco mantenido) o HTTP directo. |
| **Exportar/importar `.opennote`** (ya en PENDIENTES) | Alta: archivo local, sin red. | Baja: manual. | Medio. | ZIP. Complementa a las demás, no las reemplaza. |

---

## 6. Recomendación

Pasos chicos, cada uno entregable por separado.

1. **Paso 1: app de PC para Linux (esfuerzo medio).** Build de release, prueba del lápiz con la versión de
   Flutter del proyecto (que tenga el PR #186831), AppImage y un job de GitHub Actions. Criterio: se dibuja con
   presión en una tableta Wacom. No depende de la sincronización.
   Antes: arreglar `share_plus` y `record` en Linux, o desactivar esas funciones ahí.

2. **Paso 2: carpeta de sincronización + conflictos (esfuerzo chico a medio).** El usuario elige la carpeta de
   datos (en PC, por defecto `Documentos/apuntes`). La sincroniza Syncthing, o el cliente de Drive o Nextcloud,
   por fuera de la app. OpenNote suma la base por hoja y la copia de conflicto. Esto ya cubre "en casa" y
   "fuera de casa" con transporte probado, sin escribir criptografía propia.
   Antes: probar en la tablet si la carpeta es accesible desde Syncthing (sin confirmar).

3. **Paso 3: LAN propia (esfuerzo grande).** Solo si no se quiere depender de Syncthing. Entregable en dos
   partes: primero emparejar y revocar, sin sincronizar contenido. Después la sincronización. Pruebas previas:
   que `dart:io` verifique el certificado del cliente contra la lista (sin confirmar), `bonsoir` en Android con
   `MulticastLock`, y `mobile_scanner` en la tablet.

4. **Paso 4: nube con cifrado de extremo a extremo (esfuerzo grande).** Primero Nextcloud (WebDAV): el servidor es
   del usuario y no hace falta OAuth. Después Google Drive, porque en PC exige un login propio.

Decisiones que hacen falta antes de empezar: si la carpeta de datos en Android puede ser accesible por Syncthing o
si hay que cambiarla, y si la pérdida de la frase de paso es aceptable para el usuario.

---

## Decisión: Google Drive

**Decidido por el usuario (2026-11-21):** la sincronización va por **Google Drive**. La tablet (Android) y la app de
Linux se conectan una vez con Google y desde ahí sincronizan solas. Permiso `drive.file` (la app solo ve lo que ella
crea), carpeta `OpenNote` en "Mi unidad". El proyecto de Google Cloud lo crea el dueño una sola vez; los IDs de
cliente van dentro de la app publicada. Los usuarios solo tocan "Conectar con Google".

Código: `lib/sync/`. El motor (`sync_engine.dart`, `sync_merge.dart`, `sync_state.dart`) no sabe nada de Google: habla
con la interfaz `RemoteStore` (`remote_store.dart`), que tiene una versión en memoria para los tests
(`fake_remote_store.dart`) y la real (`drive_remote_store.dart`, `googleapis` Drive v3). El login está en
`google_auth.dart`; la pantalla en el menú ⋮ de la biblioteca ("Sincronización con Google Drive").

### Estructura remota

Es la misma estructura que en el disco (ver `TECNICO.md`), bajo `OpenNote/` en "Mi unidad":

```
OpenNote/
  index.json                         cuadernos y carpetas
  notebooks/<id>/notebook.json       orden y datos de las hojas del cuaderno
  notebooks/<id>/sheets/<hoja>.sheet una hoja (binario)
  media/<nombre>                     imágenes y audios (nombre único, solo se agregan)
```

Las rutas se validan con `sync_paths.dart` antes de tocar el disco: lo que no encaja (`..`, otras carpetas,
`prefs.json`, temporales, `.roto`) se ignora. `sync_state.json` (solo local) guarda, por archivo, la **base**, el
hash remoto conocido, el token de cambios y la hora del último sync.

### Qué se sube y qué se baja

- **Subir solo lo cambiado.** Por archivo se compara el md5 de lo local con la **base** (el md5 de la última
  versión que quedó igual en los dos lados). Si no cambió (mismo tamaño y fecha que en la base) ni se relee. Drive
  devuelve `md5Checksum` de cada archivo, así que no hace falta un campo nuevo en los archivos.
- **Bajar con la API de cambios de Drive.** `changes.getStartPageToken` la primera vez; después `changes.list` con
  el token guardado devuelve solo lo que cambió (y lo que se borró o fue a la papelera). **Respaldo:** si no hay token o
  Drive lo rechaza, se lista todo (`files.list`) y se compara el `md5Checksum` contra lo que se conoce. Las subidas
  propias también vuelven en el próximo delta con el mismo hash: no hacen nada.
- **Orden de la pasada:** medios, hojas, `notebook.json`, `index.json` y al final los borrados. Así, si se corta, el
  otro dispositivo nunca ve un índice que apunta a algo que todavía no llegó.

### Conflictos (por hoja)

Se compara local, remoto y base de cada archivo:

| Local | Remoto | Resultado |
|---|---|---|
| igual a la base | cambió | se baja |
| cambió | igual a la base | se sube |
| cambió | cambió | **conflicto** (si no son iguales entre sí) |

**Resolución en una hoja:** queda la local donde estaba y la remota se agrega como **hoja nueva "(conflicto)" justo
después**. Las dos se suben, así el otro dispositivo recibe las dos y, tras una pasada más, los dos lados tienen lo
mismo. No se pierde nada; el usuario borra la que sobre. Una hoja es un archivo entero: dos cambios en partes
distintas de la misma hoja también cuentan como conflicto (ver sección 4, opción (a)).

`notebook.json` e `index.json` no generan hojas de conflicto: se **fusionan** por `id` (tres vías con la base
guardada). Lo agregado en un lado se agrega; lo borrado en un lado se borra si el otro no lo tocó; si cambió en los
dos, queda el más nuevo por `updated`. Los datos propios de cada dispositivo (la última hoja vista, `rev`) no se
pisan entre dispositivos.

### Borrados (lápidas), cuadernos y carpetas

- **No hay archivos de lápida.** Un archivo que falta de un lado y figura en la base **se borró** en ese lado: se borra
  del otro si no cambió. Si el otro lado lo había editado, **editar le gana a borrar**: se conserva (y vuelve a
  subirse o bajarse), también el cuaderno que lo contiene. Archivos sin base (nuevos) nunca se borran.
- En Drive, borrar manda el archivo a la **papelera** (se puede recuperar desde Drive; el plazo de 30 días es **(sin confirmar)**).
- Si la carpeta `OpenNote` aparece vacía (la borraron por error), no se borra nada acá: se vuelve a subir todo.
- **Cuadernos y carpetas nuevos:** aparecen en `index.json` y en `notebooks/<id>/`; el otro lado los crea. **Renombrar o
  mover** cambia solo `index.json` (el `id` no cambia), así que el cuaderno no se vuelve a subir.
- Cambiar de cuenta de Google empieza de cero (sin borrar nada local).
- **Cuaderno de ejemplo.** Cada instalación crea "Mi cuaderno" al primer arranque. En la PRIMERA sincronización de un
  dispositivo (sin base), si la nube ya tiene cuadernos y el local es ese ejemplo intacto (único cuaderno, sin carpetas,
  sin PIN, una sola hoja vacía), se descarta (se borra de disco sin lápida, no se sube) para que no queden dos "Mi cuaderno".
  Si tiene algo escrito, o la nube está vacía, se conserva y se sube.
- **Borrado con la app cerrada (Drive).** El primer `changes()` de un proceso nuevo siempre es un listado COMPLETO
  (`getStartPageToken` + `files.list`), aunque haya token guardado: con un delta, lo borrado mientras la app no corría
  no figuraría en el mapa recién cargado y nunca saldría como borrado. El motor trata el listado completo como verdad
  (lo que está en la base y no en la nube se borra acá); si la carpeta aparece de verdad vacía no se borra nada y se vuelve a subir.
- **"Mapa cargado" no es "listado entregado" (issue #9).** `crypto.wrap` baja `crypto.json` antes del primer `changes()`
  y eso ya carga el mapa de Drive; si el delta se decidiera por "mapa cargado", lo que cambió en Drive antes (otro
  dispositivo, o la tarea de fondo de Android, que es otro proceso) no aparecería nunca y `index.json` daría conflicto
  para siempre. Por eso `DriveRemoteStore` lleva `_listed`: hasta que el motor recibió un listado completo, `changes()`
  lista todo. Defensa extra: si un archivo da `RemoteConflictException`, el motor borra el token y la próxima pasada lista todo.

### Cuaderno abierto (regla de oro)

**Decisión (2026-11-21): con un cuaderno abierto el motor SUBE pero NUNCA escribe ni borra nada local de ese cuaderno.**

- **Subir sí.** Lo que `Storage` ya guardó en disco (hojas `.sheet` y `notebook.json`) se puede subir aunque el cuaderno esté
  abierto: el archivo en disco es consistente porque cada escritura es atómica (temporal + rename). Así lo que escribís
  llega a la nube a los pocos segundos de guardar, sin cerrar el cuaderno. Solo se sube si la nube sigue en la base
  (nadie más lo tocó); un borrado hecho acá (hoja borrada) también se propaga. `index.json` es igual: con algún cuaderno
  abierto es solo-subida (la biblioteca lo tiene en memoria).
- **Bajar no.** Si la nube cambió (o borró) algo de un cuaderno abierto, no se aplica: el cuaderno queda en
  `SyncReport.remoteWaiting` y el editor muestra arriba un aviso discreto **"Hay cambios de otro dispositivo"** con el botón
  **Actualizar**. Actualizar guarda, cierra el cuaderno, hace una pasada (ya sin el cuaderno abierto: se aplican las reglas
  de siempre, o sea, hoja "(conflicto)" si cambiaron las dos) y lo vuelve a abrir. Si no se toca el aviso, se aplica solo al cerrar el
  cuaderno (la biblioteca sincroniza al volver).
- **Por qué no se aplica en vivo (recargar la hoja dentro del documento abierto).** Se evaluó (detach + attach de la hoja, o
  el mecanismo de carga perezosa) y se descartó por riesgo: (1) `NotebookDoc` guarda también `notebook.json` (orden, títulos,
  hojas agregadas o borradas) en `nb.sheets`, que la pantalla, el panel de hojas y el deshacer comparten; una hoja nueva o
  movida desde otro dispositivo obligaría a reconciliar eso con el historial de deshacer, que apunta a elementos que
  desaparecerían; (2) una hoja "sucia o con cambios sin guardar" puede estar a medio gesto (trazo en curso, selección); (3)
  `Storage` recuerda el hash de cada archivo en disco para guardar solo lo que cambió, y un cambio externo lo invalidaría
  justo cuando se escribe; (4) el costo de un error es perder escritura del usuario, y el aviso con botón no tiene ese
  riesgo. Queda como mejora futura: aplicar en vivo solo las hojas remotas cambiadas que no estén sucias, sin cambios
  de estructura.
- **Carreras.** Se consulta qué cuadernos están abiertos antes de CADA archivo y otra vez justo antes de escribirlo en
  disco; si el usuario lo abrió mientras tanto, esa escritura se saltea y queda para después. Lo que se escribe en
  disco desde la sync (cuadernos cerrados) va por las mismas escrituras atómicas de `Storage`, y no se pisa un archivo que
  cambió entre que se leyó y que se escribió (queda para la próxima pasada).

### Sin red, cortes y errores

Sin red la pasada se corta y se reintenta con **retroceso** (30 s, 1 min, 2 min, 4 min, 8 min y de ahí cada 10 min);
volver a primer plano o "Sincronizar ahora" cortan la espera y reintentan ya. En segundo plano no se reintenta (se retoma al
volver). No se pierde nada. El estado se guarda **después de cada archivo**, así que repetir la pasada converge (es
idempotente). Un archivo que falla no frena a los demás. Si la sesión venció o se revocó, el estado pasa a
"desconectado" y hay que tocar "Conectar con Google". No hay un plugin de conectividad: la "vuelta de la red" se detecta por
el próximo reintento, la próxima consulta periódica o volver a primer plano.

### Cuándo sincroniza

Todo lo decide `SyncController` (`lib/sync/sync_controller.dart`); el motor solo hace una pasada cuando se lo piden.

| Disparador | Cuándo | Costo |
|---|---|---|
| Abrir la app | al arrancar, si hay sesión | una pasada |
| **Subir pronto** | `Storage` avisa (`onSaved`) cuando termina de escribir algo (hojas sucias, `notebook.json`, o un cambio del índice que se sincroniza: abrir un cuaderno no cuenta). Espera **5 s desde el último guardado**, y **como mucho 30 s desde el primero** si se sigue escribiendo sin parar | una pasada por ráfaga |
| **Bajar pronto** | con la app **en primer plano**, cada **45 s**, una sola llamada `changes.list` con el token guardado; si no hay cambios no se baja nada | 1 llamada |
| Volver a primer plano | `AppLifecycleState.resumed`: pasada ya, y se retoman las consultas | una pasada |
| Pasar a segundo plano | si hay algo guardado sin subir, se sube ya (Android puede cerrar la app); sin consultas periódicas | una pasada |
| Cerrar un cuaderno | al volver a la biblioteca | una pasada |
| "Sincronizar ahora" | a mano; corta el retroceso | una pasada |

**Nunca dos pasadas a la vez:** un pedido que llega mientras corre una (poll, debounce, "ahora"...) no arranca otra: marca
"una más al terminar", y los que lleguen mientras tanto se juntan en esa misma. Con la app cerrada, ver "Segundo plano".

**Indicador.** En la barra de arriba de la biblioteca y del editor, un icono chico (sin texto; el texto está en el
tooltip): nube con tilde = sincronizado, nube que gira = sincronizando, nube con flecha = hay cambios por subir, nube
tachada = sin conexión, triángulo = error. No se ve si no hay sesión con Google. Tocarlo abre la hoja de Sincronización.

### Segundo plano (Android)

Con la app cerrada o en segundo plano corre una tarea periódica de `workmanager` (cada **15 min**, el mínimo de Android,
solo con red). Se registra al conectar con Google y al abrir la app si hay sesión (`ExistingPeriodicWorkPolicy.update`);
se cancela al desconectar. Interruptor "Sincronizar en segundo plano" en la hoja de Sincronización (menú ⋮ de la
biblioteca; por defecto encendido, se guarda como `bgSync` en `prefs.json`; solo se ve en Android: en Linux los timers ya
corren con la ventana minimizada). Código: `lib/sync/background_sync.dart`.

- **Otro isolate, sin UI.** El callback (`backgroundSyncDispatcher`) arma `Storage` + `GoogleBackend.restore()` + el motor
  y llama a `runBackgroundPass`, que es una función común y testeable (sin WorkManager). Si `restore()` no da sesión o
  lanza, termina sin hacer nada y sin error.
- **Nunca a la vez que la app.** Un candado `sync.lock` en la carpeta de datos (PID, dueño y hora; se crea de forma
  exclusiva; **vence a los 10 min** para que uno abandonado no bloquee para siempre) que toman las dos pasadas, la de
  `SyncController` también (si lo tiene la de fondo espera 15 s y reintenta). Además la app marca `sync.fg` mientras
  está en primer plano (se renueva cada consulta; vale 3 min): con la app en primer plano la tarea de fondo no hace nada.
- **Cuadernos abiertos.** Al pasar a segundo plano la app anota en `sync.busy` los cuadernos abiertos en el editor: la
  tarea de fondo solo les sube lo suyo, no les escribe encima (misma regla de oro). La marca se borra al abrir la app.
- **Volver a primer plano.** Si la tarea bajó cambios deja `sync.bgchanged`; la próxima pasada de la app la consume y
  relee el índice y las miniaturas del disco (`onBackgroundChanged`).
- **Sesión en el isolate de fondo (Android): refresh token propio.** `google_sign_in` pide una `Activity` para retomar la
  sesión y en la tarea de fondo no hay. Entonces, con la app en primer plano (al conectar, o al abrir la app si todavía
  no hay token), se le pide a `google_sign_in` un `serverAuthCode` (`authorizeServer`), se canjea en
  `https://oauth2.googleapis.com/token` con el cliente Web (`GOOGLE_WEB_CLIENT_ID` + `GOOGLE_WEB_CLIENT_SECRET`) y el
  refresh token queda en el almacenamiento seguro junto con la cuenta (`lib/sync/refresh_token_auth.dart`). La tarea de
  fondo (`GoogleBackend.restoreInBackground`) saca tokens de acceso con ese refresh token, sin tocar `google_sign_in`.
  Si Google responde `invalid_grant` el token se borra y la app lo vuelve a pedir la próxima vez en primer plano. Al
  desconectar se revoca en Google y se borra. La app en primer plano sigue usando `google_sign_in` como siempre. Si falta
  el secreto `GOOGLE_WEB_CLIENT_SECRET`, todo anda igual y solo el segundo plano no sincroniza.

### Cuotas de Drive API: cuántas llamadas hacemos

Con la app abierta en primer plano:

- **Quieto** (nada que subir ni bajar): 1 `changes.list` cada 45 s = **80 llamadas por hora**.
- **Escribiendo sin parar:** como mucho una pasada cada 30 s (2 por minuto, 120 por hora); cada pasada = 1 `changes.list` + las
  subidas de lo que cambió (típicamente 1 o 2 hojas + `notebook.json`, y cada subida con control optimista, o sea 1 a 3 llamadas
  por archivo) = alrededor de 5 a 10 llamadas. Orden de **300 a 1200 llamadas por hora** en el peor caso, y solo mientras
  se escribe de verdad.
- **Dos dispositivos abiertos a la vez:** se suman las consultas (160 por hora quietos).
- Segundo plano: **0** consultas periódicas.

Contra la cuota: Google mide ahora la Drive API en "unidades de cuota": **1 000 000 por minuto por proyecto y 325 000 por
minuto por usuario por proyecto**, sin límite diario de peticiones mientras se respete lo por minuto (el único tope diario
que figura es de 1 TB de subida por proyecto) [Google, "Usage limits | Google Drive",
<https://developers.google.com/workspace/drive/api/guides/limits>, consultada el 2026-11-21]. Cuántas unidades cuesta cada
llamada concreta **(sin confirmar: la página no lo muestra en la parte leída)**; aun suponiendo unas decenas de unidades por
llamada, 80 a 1200 llamadas por hora son del orden de 0,1 a 6 llamadas por minuto, miles de veces por debajo del tope de un
solo usuario. (Antes la cuota se contaba en consultas: "12 000 por 60 s por proyecto" y "1 000 000 000 por día" **(sin
confirmar, de documentación vieja)**; también muy por encima.) La cuota es **por proyecto de Google Cloud** y se
comparte entre todos los usuarios de la app: con muchos usuarios el tope por minuto del proyecto (1 000 000 unidades) es lo
que habría que mirar; con 1 000 usuarios consultando cada 45 s son unas 1 300 llamadas por minuto en total.
La consulta periódica es barata para la batería: una petición HTTPS chica cada 45 s con la pantalla prendida y la app visible.

### Cifrado de extremo a extremo (opcional)

Código: `lib/sync/e2e_crypto.dart` (formato y claves), `encrypted_remote_store.dart` (decorador de `RemoteStore`),
`sync_crypto.dart` (estado, clave guardada, activar / desactivar / frase), UI en
`lib/screens/library/crypto_section.dart` (hoja de sincronización, sección "Cifrado"). Tests: `test/sync/e2e_test.dart`.

**Qué ve Google con el cifrado activo:** archivos sin sentido (contenido cifrado), su **cantidad, tamaños y fechas**, y
sus **rutas**. Las rutas (`notebooks/<id>/sheets/<hoja>.sheet`, `media/<nombre>`) **quedan en claro a propósito**: son ids
al azar, no llevan el nombre del cuaderno (el nombre está dentro de `index.json`, que va cifrado), y así el motor y la
API de cambios de Drive siguen funcionando igual. Lo que no se oculta: cuántos cuadernos y hojas hay y cuándo se tocan.

**Esquema**

- Frase elegida por el usuario (mínimo 8 caracteres) → clave de 32 bytes con **Argon2id** (paquete `cryptography`
  2.9.0, última versión disponible al hacerlo) y una **sal de 16 bytes al azar**. La derivación va en otro isolate para no
  trabar la pantalla.
- **Parámetros: 64 MiB de memoria, 3 pasadas, 1 hilo** (RFC 9106, segunda opción recomendada para poca memoria). En Dart puro
  no hay paralelismo real, así que se usa 1 hilo. **Medido en la PC de desarrollo (Linux, Dart JIT): 585 ms** (con 19 MiB y
  2 pasadas: 217 ms). **En la Galaxy Tab S6 Lite NO se midió**: se estima unos 3 a 5 segundos (varias veces más lenta);
  se paga solo al activar el cifrado y al ingresar la frase en un dispositivo nuevo. Los parámetros viajan en
  `crypto.json`, así que se pueden cambiar en una versión futura sin romper nubes ya cifradas.
- **Cada archivo:** XChaCha20-Poly1305 con nonce de 24 bytes al azar (no se repite en la práctica). Formato:
  `ONCR` (4 bytes mágicos) + versión (1 byte, hoy 1) + nonce (24) + texto cifrado + etiqueta (16). Datos asociados (AAD):
  versión + **ruta del archivo**, así un archivo cifrado no se puede mover a otra ruta sin que falle. Medido: 5 MiB se cifran en
  ~170 ms y se descifran en ~140 ms (PC).
- **`OpenNote/crypto.json`** (en claro, sin secretos): `version`, `cipher`, parámetros del KDF, `salt`, `verifier` (un texto
  conocido cifrado con la clave: descifrarlo bien prueba que la frase es la correcta) y `migrating` (null, o
  `encrypting` / `decrypting` mientras se cambia el cifrado). Si existe, la nube está cifrada.
- **La clave derivada (no la frase) se guarda en el almacenamiento seguro** (`TokenStore` / `flutter_secure_storage`:
  Keystore en Android, libsecret en Linux) con la clave `opennote.sync.e2e.key`. Al desconectar de Google se borra. En un
  dispositivo nuevo, al conectarse y ver `crypto.json`, la app pide la frase: con una incorrecta no sincroniza y avisa
  ("La frase de cifrado es incorrecta"); no se reintenta sola.
- **Si se olvida la frase no hay forma de recuperar lo que está en la nube** (lo local sigue entero). La UI lo avisa en la
  sección y en el diálogo de activación.

**Los hashes (lo delicado).** El motor compara el md5 de lo local (claro) con la base y con el md5 que informa el remoto.
Con cifrado, el md5 remoto es del texto cifrado y cambia en cada subida (nonce al azar) aunque el contenido sea igual: el
motor vería conflictos o subidas sin fin. No se tocó el motor: `EncryptedRemoteStore` le habla **siempre en hashes del
claro** y se acuerda de la correspondencia (md5 del cifrado en la nube → md5 del claro) en una caché por ruta
(`HashCache`, guardada en `sync_crypto_cache.json`, solo local):

1. Al **subir**: calcula el md5 del claro, sube el cifrado y anota (md5 devuelto por la nube → md5 del claro). Devuelve al
   motor el md5 del claro. El `ifRemoteMd5` que manda el motor (claro) se traduce al del cifrado antes de pasarlo.
2. Al **listar cambios**: traduce cada md5 de la nube con la caché. Las subidas propias que vuelven en el próximo delta
   figuran con el mismo hash claro: no hacen nada. Si el archivo es nuevo (lo subió otro dispositivo) lo baja y lo
   descifra **una vez** para saber su hash claro (se guarda unos MB en memoria para que el `download` del motor no lo baje
   dos veces) y lo anota. Con la caché perdida no se rompe nada: se reconstruye bajando (el `upload` también se autocorrige).
3. Un archivo de la nube **no cifrado o que no descifra** corta la pasada con un error claro. No se lo ignora: el motor lo
   tomaría por "borrado en la nube" y borraría el local.
4. El decorador oculta `crypto.json` del motor y vigila su contenido: si lo cambió otro dispositivo (activó, desactivó o
   rehízo el cifrado) la pasada se corta y se vuelve a leer; si la carpeta de la nube apareció vacía, **repone `crypto.json`**
   antes de subir nada (nunca se sube nada sin cifrar con el cifrado activo). Con la nube sin cifrar, un envoltorio mínimo
   (`PlainRemoteStore`) detecta que apareció `crypto.json`.

Medido en los tests: con dos dispositivos, pasadas sucesivas sin cambios hacen 0 subidas y 0 bajadas de archivos.

**Activar con datos ya en la nube (implementado: re-sube todo cifrado)**

1. Se deriva la clave y se hace una pasada normal (todo al día).
2. Se sube `crypto.json` con `migrating: encrypting` (los otros dispositivos que se conecten ya piden la frase) y la clave
   queda en el almacenamiento seguro.
3. Cada archivo de la nube se baja, se **borra de forma definitiva** (`files.delete` de Drive, no papelera: si no, el texto
   en claro quedaría 30 días en la papelera y como revisión vieja) y se vuelve a subir cifrado. Los que ya están cifrados se saltean.
4. Se vuelve a subir `crypto.json` con `migrating: null`.

**Desactivar** es lo inverso (se marca `decrypting`, cada archivo se baja, se descifra, se borra y se sube en claro; al final
se borra `crypto.json` y la clave del dispositivo). Si se corta a la mitad (sin red, app cerrada), `crypto.json` sigue marcado y
**la próxima pasada de un dispositivo que tenga la clave lo retoma**. Al empezar o fallar un cambio de cifrado se borra
`sync_state.json` (la base): si no, un archivo que quedó borrado de la nube a la mitad se tomaría por un borrado en la nube y
se borraría el local; sin base, el motor lo vuelve a subir. Los cuadernos locales no se tocan nunca.

**Límites y riesgos conocidos**

- **Metadatos visibles:** cantidad de archivos, tamaños, fechas y rutas (ver arriba).
- **Rollback:** la nube puede devolver una versión vieja de un archivo que sigue siendo válida (el AAD lleva la ruta pero no
  un contador). Sin resolver (ver sección 3.2).
- **Integridad entre dispositivos durante un cambio de cifrado:** no tocar la nube desde otro dispositivo mientras se
  activa o desactiva; dos dispositivos convirtiendo a la vez deberían converger pero no se probó.
- **Cifrado de archivos grandes en Dart puro:** carga el archivo entero en memoria (las imágenes de `media/` son de unos MB).
- **No se probó contra Drive real ni en la tablet** (sin tablet conectada); solo con el remoto falso en los tests. En
  particular el borrado definitivo de Drive (`files.delete`) y el tiempo de Argon2id en la tablet.
- **Linux sin llavero:** si el sistema no tiene almacenamiento seguro, no se puede guardar la clave y la frase se pide de nuevo.

### Seguridad

- **Tokens.** Android: los maneja `google_sign_in` / Google Play services; la app no guarda ninguno. Linux: el
  refresh token va en el almacenamiento seguro del sistema (`flutter_secure_storage`, libsecret en Linux); si el
  sistema no tiene llavero, ver la nota de `google_auth.dart` (no se probó en una PC sin llavero **(sin confirmar)**).
- **Alcance.** `drive.file`: la app no ve nada más de tu Drive. Es un permiso "no sensible" **(sin confirmar la
  clasificación exacta: si lo es, no hace falta la verificación de Google)**.
- **El secreto del cliente de escritorio no es confidencial** [según Google, en apps instaladas no puede mantenerse en
  secreto]. Va en la app igual que el ID. Lo que protege la cuenta es el consentimiento del usuario y PKCE.
- **Google puede leer lo que se sube** salvo que se active el cifrado de extremo a extremo (sección "Cifrado", más
  abajo). Es opcional y viene apagado.

### Configurar Google Cloud (pasos del dueño)

Se hace una sola vez. Los usuarios no hacen nada de esto. Estos pasos no los ejecutó nadie todavía: la app compila sin
ellos y avisa que falta configurar.

1. En <https://console.cloud.google.com/> crear un proyecto (por ejemplo "OpenNote").
2. **APIs y servicios > Biblioteca:** habilitar **Google Drive API**.
3. **Pantalla de consentimiento OAuth:** tipo de usuario **External**; nombre de la app, correo de soporte; agregar el
   scope `.../auth/drive.file`.
4. **Pasar la app a "In production" (Publicar la app).** Si se queda en *Testing*, Google hace vencer los refresh
   tokens a los **7 días** (confirmado en la doc de Google: "Using OAuth 2.0 to Access Google APIs", sección *Refresh
   token expiration*, salvo que los scopes sean solo nombre, correo y perfil) y habría que reconectar cada semana. Con `drive.file`
   en producción puede aparecer "app no verificada" hasta que Google la revise **(sin confirmar si `drive.file` exige
   verificación)**; hasta entonces el usuario puede seguir con "Avanzado".
5. **Credenciales > Crear credenciales > ID de cliente de OAuth**, tres clientes:
   - **Android** `com.apuntes.apuntes` con el **SHA-1 de la clave de release** (el keystore de los secretos del
     repo; lo agrega el dueño: `keytool -list -v -keystore release.jks`).
   - **Android** `com.apuntes.apuntes.test` con el SHA-1 de debug:
     `F5:83:13:66:18:80:5D:F9:69:D6:EE:D9:C3:EA:82:AC:07:E2:FF:56`.
   - **Aplicación web** (lo pide `google_sign_in` en Android como `serverClientId`; no se usa para nada más).
   - **Aplicación de escritorio** ("Desktop app") para Linux (da ID y secreto).
6. Poner los valores:

| Valor | Secreto de GitHub (Settings > Secrets > Actions) | Local (`--dart-define`) |
|---|---|---|
| ID del cliente Web | `GOOGLE_WEB_CLIENT_ID` | `GOOGLE_WEB_CLIENT_ID` |
| Secreto del cliente Web (segundo plano en Android, opcional) | `GOOGLE_WEB_CLIENT_SECRET` | `GOOGLE_WEB_CLIENT_SECRET` |
| ID del cliente de escritorio | `GOOGLE_DESKTOP_CLIENT_ID` | `GOOGLE_DESKTOP_CLIENT_ID` |
| Secreto del cliente de escritorio | `GOOGLE_DESKTOP_CLIENT_SECRET` | `GOOGLE_DESKTOP_CLIENT_SECRET` |

   Los clientes Android no llevan ningún valor en la app: Google los reconoce por el nombre del paquete y la firma.
   El workflow de release arma `google_config.json` desde esos secretos y compila con
   `--dart-define-from-file=google_config.json`. Si falta `GOOGLE_WEB_CLIENT_ID`, la release sale sin sync (con un aviso).
   Local: copiar `google_config.example.json` a `google_config.json` (ignorado por git) y
   `flutter run --dart-define-from-file=google_config.json`.
7. Si se sube la clave de release de la tablet o se cambia el keystore, hay que actualizar el SHA-1 del cliente Android.

### Riesgos conocidos

- **Segundo plano sin probar en la tablet:** el canje del `serverAuthCode` (`authorizeServer` puede mostrar la pantalla de permiso la primera vez, y Google no siempre devuelve refresh token si ya había uno emitido para esa cuenta y cliente; en ese caso el segundo plano queda sin token hasta revocar el acceso de la app en la cuenta de Google y volver a conectar). El secreto del cliente Web va dentro de la app, igual que el de escritorio: no es confidencial.
- Drive no tiene escritura condicional: dos dispositivos subiendo la misma hoja en el mismo instante pueden pisarse.
  Se mitiga comparando el hash justo antes de subir; el caso que queda es muy angosto.
- Con `drive.file` solo se ven los archivos creados por esta app; si el usuario sube o mueve archivos a mano dentro de
  `OpenNote`, la app no los ve.
- Dos carpetas con el mismo nombre (si dos dispositivos crean `notebooks/` a la vez) se tratan como la misma por ruta.

---

## 7. Fuentes

Leídas directamente:

1. https://github.com/flutter/flutter/issues/63209 (presión y PointerDeviceKind en Linux, cerrado 2026)
2. https://github.com/flutter/flutter/pull/186831 ("Improve stylus support on linux", mergeado)
3. https://github.com/adil192/saber/issues/90 (Saber, lápiz en Linux)
4. https://github.com/dart-windows/win32/discussions/843 (tabletas en Flutter Windows)
5. https://www.github.com/saber-notes/saber/issues/1218 (Saber, presión en macOS)
6. https://pub.dev/packages/stylet (Stylet, presión por plataforma)
7. https://github.com/flutter/flutter/issues/196867 (muestras de trazo perdidas en Android)
8. https://seclists.org/oss-sec/2020/q4/169 (CVE-2020-26164, KDE Connect)
9. https://pkg.go.dev/github.com/bethropolis/kcd/internal/cert (implementación de terceros, sin confirmar)
10. https://docs.syncthing.net/users/security (Syncthing: IDs, TLS, descubrimiento)
11. https://github.com/localsend/protocol (LocalSend: huella, multicast, HTTPS)
12. https://api.dart.dev/dart-io/HttpServer/bindSecure.html
13. https://api.dart.dev/dart-io/SecurityContext-class.html y https://api.dart.dev/dart-io/HttpClient/badCertificateCallback.html
14. https://pub.dev/packages/path_provider (y las páginas de los paquetes de la sección 1.4, listadas abajo)
15. https://docs.flutter.dev/deployment/linux
16. https://docs.flutter.dev/deployment/windows
17. https://docs.flutter.dev/deployment/macos
18. https://developer.apple.com/documentation/security/customizing-the-notarization-workflow (leída por resumen de búsqueda)
19. https://docs.github.com/en/actions/reference/runners/github-hosted-runners
20. https://pub.dev/packages/basic_utils
21. https://pub.dev/packages/mobile_scanner
22. https://pub.dev/packages/bonsoir
23. https://developer.android.com/reference/android/net/wifi/WifiManager.MulticastLock
24. https://developer.android.com/topic/performance/power/power-details (por resumen de búsqueda)
25. https://pub.dev/packages/nsd
26. https://pub.dev/packages/multicast_dns
27. https://pub.dev/packages/pointycastle
28. https://pub.dev/packages/cryptography
29. https://pub.dev/packages/qr_flutter
30. https://pub.dev/packages/googleapis
31. https://pub.dev/packages/google_sign_in
32. https://developers.google.com/identity/protocols/oauth2/native-app
33. https://developers.google.com/workspace/drive/api/guides/appdata
34. https://docs.nextcloud.com/server/latest/user_manual/en/files/access_webdav.html
35. https://pub.dev/packages/webdav_client
36. https://www.rfc-editor.org/rfc/rfc9106.html
37. https://doc.libsodium.org/secret-key_cryptography/aead/chacha20-poly1305/xchacha20-poly1305_construction

Páginas de paquetes de pub.dev consultadas para la tabla de la sección 1.4 (todas de `https://pub.dev/packages/<nombre>`):
`path_provider`, `file_picker`, `image_picker`, `printing`, `share_plus`, `record`, `audioplayers`, `dynamic_color`,
`material_ui`.

Referencia que salió solo de búsqueda (no leída completa): https://docs.syncthing.net/dev/device-ids
