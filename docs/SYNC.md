# PC app and sync

Research on the PC app and sync. The decision taken (Google Drive) and its design are in
"Decision: Google Drive", before the sources; the rest is the earlier research.
Research date: 2026-11-20.

Sources are listed at the end (section 6) with numbers in square brackets, for example `[2]`.
What I could not confirm by reading a source is marked **(unconfirmed)**.

## Starting point: how data is stored today

What is in the code (`lib/data/storage.dart`, `lib/data/sheet_codec.dart`) and conditions everything else:

- **A notebook is a folder.** Inside there is `notebook.json` (sheet order, `rev`, `updated`, bookmark,
  background, paper, spacing) and `sheets/<sheet>.sheet` (binary, one file per sheet). Images and audio go in
  `media/`, shared by all notebooks. `media/` must be synced too, not only the sheets.
- **`rev` and `updated` are local.** `rev` goes up on every save on that device (`_saveNow`) and `updated`
  is the time on that device's clock. Two tablets can have the same sheet with `rev` 5 and different contents.
  On their own they are not enough to detect a conflict: we also need to know which version each side edited.
- **There is already a hash per sheet.** `Storage` keeps the md5 of each `.sheet` as it was last written
  (`_DiskState`). It tells us what changed on this side without rereading everything.
- **Strokes have an `id`** (prefix `s` + 12 random hex, `values.dart`). The eraser removes whole strokes
  (`page_editor.dart`, `_eraseAt`): it does not split them. That simplifies deletion across devices a lot.
- **Writing is atomic** (temporary file + rename), and only the sheets that changed are written.
- **On PC the base folder is `Documents/apuntes`.** `_defaultBase()` uses `getExternalStorageDirectory` only on
  Android; elsewhere it falls back to `getApplicationDocumentsDirectory()`. I did not confirm the exact path per
  operating system against the `path_provider` docs [14].
- **The repo only has the `android/` and `linux/` folders.** There is no `windows/` or `macos/`: they would have
  to be added (`flutter create --platforms=...`, exact command not confirmed against the docs).

---

## 1. Flutter desktop PC app

### 1.1 Input: stylus, mouse and tablets

The critical point for Vynote is that the stylus of a Wacom/Huion tablet on PC arrives as
`PointerDeviceKind.stylus` and with pressure. Today on Android it works because `ink.dart` decides by that type.

**Linux (improved a lot in 2026).**
- Flutter issue #63209 asked for stylus pressure and `PointerDeviceKind` on Linux since 2020. It was closed on
  28/08/2026 citing PR #186831, "Improve stylus support on linux", which landed in the 1/07/2026 roll-up. The PR
  adds stylus pressure, tilt, rotation and buttons on Linux [1][2].
- Its author tested it with a Wacom on Fedora/KDE over Wayland [2]. **(unconfirmed)**: X11, GNOME, Huion
  tablets, and whether that version is already on the channel the project uses (check `flutter --version`).
- Earlier, Saber (a Flutter app) reported on Linux that the stylus was detected as a finger and that there was no
  pressure. It was closed as "not planned" in 2022 [3]. That is history, but it shows why we must test on each
  machine.

**Windows (no confirmed fix).**
- I did not find a change in the engine. A question from April 2024 in `dart-windows/win32` says Flutter's
  official Windows support does not include tablets. It got no answers [4].
- Stylet (a third-party package) gets pressure on Windows from the Wintab driver, not from pointer events [6].
- Conclusion: on Windows we must test with a real stylus before deciding. It may arrive as a mouse or without
  pressure **(unconfirmed)**. If it does not arrive, the option is a third-party plugin or native code.

**macOS (no confirmed fix).**
- Saber #1218 (macOS Sonoma, Wacom Intuos BT): pressure does not work and the stylus behaves like a left click.
  It was closed as "not planned" in June 2024 [5].
- Stylet says pressure comes from AppKit [6]. I did not find a Flutter issue about macOS **(unconfirmed)**.

**Android (for comparison, not the PC).** Issue #196867 (November 2026) reports that on Android historical samples
of the stroke are lost and the curve looks straight. The fix PR was still open on the date of the issue [7].
It is a tablet issue worth following because it affects stroke quality.

**Mouse.** The right button already erases. With a mouse the pressure is 1
**(unconfirmed)**.

**Input recommendation:** Linux first. For Windows and macOS, test with a real stylus and decide afterwards
between a plugin (Stylet is new: published 43 days ago, 0 likes [6]) or native code.

### 1.2 Keyboard shortcuts

- Ctrl+B/I/U and Tab/Shift+Tab already exist in the text.
- We still need to survey which exist for undo/redo, save, delete selection, copy and paste. I did not do it.
- Flutter resolves shortcuts with `Shortcuts` and `Actions` **(unconfirmed)**.

### 1.3 Data paths

- `path_provider` declares support on Linux (any version), Windows 10+ and macOS 10.15+ [14].
- What changes for the user: on Android the data is in the app's external storage (backed up over USB). On PC it
  goes to Documents. That is good: a visible folder that Syncthing, Drive or Nextcloud can sync without touching
  the app.
- The concrete paths per system (for example `~/Documents` on Linux) **(unconfirmed)**: they must be printed in
  a test.

### 1.4 `pubspec.yaml` plugins on desktop

Status according to each package's page on pub.dev [14]. "Unconfirmed" means I did not check it.

| Package (pubspec) | Linux | Windows | macOS | Notes |
|---|---|---|---|---|
| `material_ui` ^1.1.0 | yes | yes | yes | Official Flutter. |
| `path_provider` ^2.1.6 | yes | yes | yes | Paths: see 1.3. |
| `file_picker` ^13.4.0 | yes | yes | yes | Folder: not on web. |
| `image_picker` ^1.2.4 | partial | partial | partial | Desktop goes through `image_picker_linux/windows/macos` (0.2.x). No max width/height on desktop. |
| `printing` ^5.15.1 | yes | yes | yes | PDF. |
| `share_plus` ^13.3.1 | partial | partial | yes | Linux: text and URL only, **no files**. Windows: URL as text. |
| `record` ^7.2.0 | partial | partial | partial | Linux needs `parecord`, `pactl` and `ffmpeg` installed. Windows and macOS via separate packages; macOS unconfirmed. |
| `audioplayers` ^6.8.1 | yes | yes | yes | |
| `dynamic_color` ^2.1.0 | yes | yes | yes | On Linux it takes the color from the XDG portal or the GTK theme. |
| `package_info_plus` ^10.2.2 | unconfirmed | unconfirmed | unconfirmed | I did not check it. |
| `pdf`, `crypto`, `material_symbols_icons`, `cupertino_icons` | unconfirmed | unconfirmed | unconfirmed | I did not check them. `pdf` and `crypto` should be pure Dart (unconfirmed). |

What blocks or changes something: `share_plus` on Linux (a file cannot be shared) and `record` on Linux (we must
require `ffmpeg`). Neither prevents the PC version; we must warn the user or disable the feature.

### 1.5 Packaging

**Linux.**
- Flutter's docs describe packaging with Snap (`snapcraft`) [15]. AppImage, deb and rpm appear only as third-party
  tools (fastforge), and Flatpak as another tool (flatpak-flutter) [15].
- Suggestion: AppImage first (one file, no store and no system permissions). Then Flathub, if wanted.
  **(unconfirmed)**: the best format for this app; I did not review `linux/` inside (app ID, etc.).

**Windows.**
- Flutter's docs describe MSIX (with the `msix` package, configured with `msix_config` in `pubspec.yaml`) and
  publishing to the Microsoft Store with the `msstore` CLI [16].
- Classic installer (MSI or Inno Setup): not in the docs **(unconfirmed)**.
- The docs do not mention code signing [16]. Without signing, Windows shows warnings on install **(unconfirmed)**.

**macOS.**
- Flutter's docs cover signing with Xcode and the App Store, but not notarization or DMG [17].
- Apple documents notarization with `notarytool` and `stapler` for software outside the App Store, signed with
  Developer ID [18]. I read this from a search summary, not the full page **(details unconfirmed)**.
- Requires an Apple Developer account **(cost unconfirmed)**.

**GitHub Actions.**
- Available runners: `ubuntu-latest`, `windows-latest` and `macos-latest` (arm64) [19].
- Today the releases workflow only does Android (`docs/RELEASES.md`). Jobs per system can be added with
  `flutter build linux --release`, `flutter build windows` and `flutter build macos`.
- Windows and macOS signing: the certificates go in as repo secrets **(unconfirmed)**.

### 1.6 Estimated effort

- **Linux: medium.** Release build, stylus test with the project's Flutter version, AppImage, CI job.
- **Windows: large.** Add the `windows/` folder, solve the stylus (probably with a plugin), MSIX and signing.
- **macOS: large.** Apple account, Developer ID signing, notarization, stylus test (doubtful) and a Mac to test
  on **(unconfirmed which Mac is available)**.

---

## 2. Secure LAN sync (home network)

Requirement: nobody else on the same network can see the content or connect. An unpaired device cannot even
establish the connection.

### 2.1 How others solve it

**KDE Connect.**
- Each device has a self-signed certificate. Identity is the public key and the certificate's signature, not the
  name. Since version 1.0 it uses *trust on first use* (TOFU), like SSH [7].
- Pairing depends on the user comparing the fingerprints on both machines. The app does not force that comparison [7].
- CVE-2020-26164: the device name is announced over unencrypted UDP. An attacker on the LAN can impersonate a known
  machine and request pairing. The fix shows the SHA-256 of both public keys together: first 8 hex characters and
  the rest behind "ver clave" (show key) [8].
- Lesson: the first pairing is the weak point. Do not trust the name or the discovery.
- A third-party Go package says the certificates are RSA 2048 with 10 years of validity and CN equal to the device
  ID [9]. It is a third-party implementation; I did not confirm it against the official code.

**Syncthing.**
- The Device ID is the SHA-256 of the TLS certificate. Each connection compares that ID against a fixed list of
  accepted machines; if it is not there, it disconnects [10].
- Local discovery sends the ID and port every 30 s by broadcast/multicast. An attacker on the LAN sees which machines
  run Syncthing and their IDs, but cannot connect without being on the list [10].
- Whoever has the TLS keys and the configuration file can impersonate the machine. That is why they recommend
  protecting the configuration folder [10].

**LocalSend.**
- In HTTPS mode, the fingerprint is the SHA-256 of the certificate [11].
- Discovery goes over UDP multicast to the group `224.0.0.167`, port `53317` [11].
- The specification marks the fingerprint as "ignored" in `/register` and `/prepare-upload` over HTTPS, and does not
  describe the receiver verifying the fingerprint [11]. That is: it encrypts, but does not bind the identity.
- Lesson: fingerprint verification must be done on both sides. There is an optional PIN for transfers [11].

### 2.2 Proposed design for Vynote

**Identity (once per installation).**
- A self-signed X.509 certificate is generated with `basic_utils`, which generates RSA and EC self-signed
  certificates in pure Dart [20]. EC P-256 is the lightest **(unconfirmed that dart:io accepts it on all platforms)**.
- The certificate and its key are kept in the app's private folder. On Android I did not evaluate the secure store
  (Keystore) **(unconfirmed)**.
- The device ID is the SHA-256 of the certificate, the same as Syncthing and LocalSend.
- Long validity: the third-party implementation in [9] uses 10 years. Validity recommendation **(unconfirmed)**.

**Pairing (once per pair of devices).**
1. On device A, "Pair another device" shows a QR with: version, name, SHA-256
   fingerprint of A's certificate, a 128-bit single-use secret, and A's IP:port. It expires after 2 minutes.
2. Device B scans the QR. **The scanner has to be Android, iOS or macOS**, because `mobile_scanner` does not support
   Linux or Windows [21]. If B is a PC, it is A (the tablet) that scans the QR the PC shows. If both are PCs, another
   path is needed (pasting a text or an 8-digit code). Not designed yet.
3. B opens TLS to A and compares A's certificate with the fingerprint in the QR. If it does not match, it disconnects.
   This prevents the man in the middle.
4. B sends its certificate and an HMAC-SHA256 of the secret over both fingerprints. A verifies the HMAC and, if it is
   valid, stores B's fingerprint. A replies with its own HMAC and B stores A's **(design, unconfirmed against an existing protocol)**. The `crypto` package, which is already
   in `pubspec.yaml`, includes HMAC and SHA-256 **(exact API unconfirmed)**.
5. The secret is burned when used or when it expires. An attacker on the LAN only sees TLS traffic: they cannot
   impersonate A (different fingerprint) nor complete the HMAC (they do not know the secret).
6. Remaining risk: whoever photographs the QR can pair during the 2 minutes. Mitigation: the QR is shown only when the
   user enters "Pair", and A asks for confirmation "Accept <name>?" before saving.

**Daily connection (mutual TLS with pinned certificates).**
- Server: `HttpServer.bindSecure` with `requestClientCertificate: true` [12]. The `SecurityContext` carries the own
  certificate and the certificates of all paired devices as trusted roots (`setTrustedCertificatesBytes`) [13].
  **(unconfirmed)**: that dart:io verifies the client certificate against that list. It must be tested with two
  machines.
- Client: `HttpClient` with the own certificate (`useCertificateChainBytes` and `usePrivateKeyBytes` [13]) and
  `badCertificateCallback`. That callback is called when the server certificate cannot be validated against the
  trusted roots, and returns `true` to accept the connection [13]. That is where the server fingerprint is compared
  with the stored one.
- To see the client fingerprint after the handshake on the server side, `HttpRequest.certificate` is needed
  **(unconfirmed)**.
- An unpaired device is not on the list: the handshake fails.

**Discovery (mDNS / DNS-SD).**
- `bonsoir` announces and searches for services (Android, iOS, Linux, macOS and Windows) [22].
- The announcement carries a random name per pairing, never the fingerprint.
- Discovery gives IP and port, never trust. If mDNS does not work, the QR already carries IP:port.
- On Android, Wi-Fi filters multicast packets by default. To receive them a `MulticastLock` is needed [23]. I did not
  check whether `bonsoir` does it by itself **(unconfirmed)**.

**Revoke (from settings).**
- "Settings" > "Devices": the fingerprint is removed from the list, the `SecurityContext` is
  rebuilt and active connections are cut.
- If a tablet is lost, it is revoked from the other one. That is not enough for the cloud key (section 3): it must be
  rotated.
- "Restablecer identidad" (Reset identity) breaks all pairings: they must be paired again.

### 2.3 Risks

- **Android in the background.** According to the summary of Android's power docs, foreground apps have no execution
  limits; in the background Doze and App Standby apply [24]. Sync happens when the app opens, when it returns to the
  foreground, shortly after each save, and every 45 s while the app is visible (see "When sync
  happens"). Continuous sync would need a foreground service with a notification **(unconfirmed how the system treats it in practice)**.
- **Networks that block multicast.** Guest Wi-Fi, access points with client isolation **(unconfirmed: I did not look)**. Fallback: IP:port in the QR or typing the IP by hand.
- **Key theft.** The app's private folder is the only place with the identity. On PC, the file must have permissions
  for the user only **(unconfirmed on Windows)**.
- **New certificate breaks pairing.** If it is regenerated, pairing must be redone. That is why validity must be long
  and the app must warn beforehand.

### 2.4 Dart/Flutter packages for each piece (status)

| Piece | Package | Platforms | Status (according to pub.dev) |
|---|---|---|---|
| Discovery | `bonsoir` 7.1.6 | Android, iOS, Linux, macOS, Windows [22] | Published 26 days ago, 150 points. |
| Discovery | `nsd` 5.0.1 | Android, iOS, macOS, Windows. **No Linux** [25] | Published 7 months ago. |
| Discovery | `multicast_dns` 0.3.3+1 | Android, iOS, Linux, macOS, Windows [26] | Published 5 months ago, verified publisher (flutter.dev). If it registers services: **(unconfirmed)**. |
| TLS | `dart:io` (SDK) | All | Not a package: `SecurityContext`, `bindSecure`, `badCertificateCallback` [12][13]. |
| Certificates | `basic_utils` 5.8.2 | Pure Dart [20] | Published 21 months ago. Generates RSA and EC self-signed certificates. |
| Cryptography | `pointycastle` 4.0.0 | Android, iOS, Linux, macOS, web, Windows [27] | Published about 21 months ago, verified publisher (bouncycastle.org). HKDF, Argon2, ECDSA. |
| Cryptography | `cryptography` 2.9.0 | Native on Android, iOS, macOS and web; pure Dart as fallback [28] | Published about 12 months ago, verified publisher (dint.dev). Argon2id, XChaCha20-Poly1305, Ed25519, X25519, HKDF. Check whether there is a 3.x. |
| HMAC / SHA-256 | `crypto` 3.0.8 (already in `pubspec.yaml`) | **(unconfirmed)** | For fingerprints and the pairing HMAC. |
| Scan QR | `mobile_scanner` 7.5.0 | Android, iOS, macOS, web. **No Linux or Windows** [21] | Published 19 days ago, verified publisher. |
| Show QR | `qr_flutter` 4.1.0 | Android, iOS, Linux, macOS, web, Windows [29] | Published 3 years ago. Stable, but no recent releases. |

---

## 3. Outside the home

There are three paths. Syncthing is already a secure device-to-device path (section 2). Google Drive and WebDAV are
clouds, and on them end-to-end encryption is needed.

### 3.1 Options

**Google Drive.**
- `googleapis` 19.0.0 includes Drive v3 and was published 8 days ago [30].
- `google_sign_in` supports Android, iOS, macOS and web. Linux and Windows are not listed on its page [31]. On PC the
  login must be done through the browser: client of type "Desktop app", PKCE and redirect to a loopback
  (`http://127.0.0.1:port`). Google rejects embedded webviews [32]. That makes two login paths.
- `appDataFolder`: hidden folder, only for the app that created it; the user does not see it in Drive and other apps
  cannot read it. It uses the `drive.appdata` scope, which is not sensitive [33].
- Google can still read what is uploaded without our own encryption: the E2E layer is needed.
- Pros: an account many people already have, no server of our own. Cons: dependency on Google, two login paths, and
  the verification of the OAuth client **(unconfirmed)**.

**WebDAV (Nextcloud).**
- Endpoint: `https://<server>/remote.php/dav/files/<user>/`. They recommend an app password and HTTPS [34].
- `webdav_client` 1.2.2 supports Android, iOS, Linux, macOS and Windows [35]. Its latest version is about 2 years old
  and the publisher is not verified: maintenance risk. It could be simpler to make the WebDAV calls directly with
  `dio` or `http` **(unconfirmed)**.
- Pros: the server belongs to the user, there is no OAuth. Cons: you need a server. Without E2E, the server sees the
  content.

**Syncthing installed separately.**
- Vynote only uses one folder; Syncthing syncs between machines with TLS and an ID list [10].
- There is no cloud in between, so E2E is not needed. Syncthing has an "untrusted" device mode with encryption
  **(unconfirmed: I did not read it)**.
- Cons: it must be configured on each machine. On Android it runs as a separate app **(unconfirmed how it behaves in the background)**. Vynote's private folder on Android
  may not be accessible from another app **(unconfirmed: it
  must be tested with the current path)**.
- Conflicts: when two machines change the same file, Syncthing keeps a copy named `*.sync-conflict-*`
  **(unconfirmed: I did not read the conflicts docs)**. Vynote would
  have to ignore them or handle them (section 4).

### 3.2 End-to-end encryption for Drive and WebDAV

Proposed scheme:

- **Passphrase** chosen by the user, and from it a **32-byte master key** with **Argon2id**. RFC 9106 recommends
  Argon2id if you don't know which to use, and gives two options: `t=1, m=2 GiB, p=4` (very heavy for a tablet) and
  `t=3, m=64 MiB, p=4` for machines with little memory [36]. For the tablet, the second one. It must be measured on
  the Galaxy Tab S6 Lite before fixing it **(unconfirmed the RAM of that tablet)**.
- **Random 16-byte salt**, stored in a public `vault.json` file in the cloud. The salt is not secret.
- **Per file:** XChaCha20-Poly1305 with a random 24-byte nonce. libsodium says the 192 bits of the nonce allow random
  nonces with no practical risk of repetition [37]. `cryptography` includes that algorithm [28].
- **Associated data (AAD):** file ID and version number. That way an encrypted file is useless somewhere else
  **(design, unconfirmed against an implementation)**.
- **Names:** files are named by a random ID. The index (notebook names, order) is encrypted in its own file.
- **What the cloud still sees:** number of files, sizes and dates.
- **What the cloud cannot read:** the content or the names.
- **Limitation:** the cloud can return an old version that is still valid (rollback). A possible mitigation: version
  number in the AAD and a signed manifest. **Not resolved.**
- **Lost passphrase = lost cloud data.** There is no recovery. This must be stated on the setup screen.
- **Fits with what already exists:** only the sheets that changed are uploaded (saving already computes that). Each
  `.sheet` is encrypted as a whole, so a changed sheet is uploaded in full.

### 3.3 How the key is shared between devices

Short answer: **the QR must not carry the master key in clear.**

Options:

- **(a) Inside the LAN:** pairing already has a verified TLS channel (section 2). The master key travels over that
  channel, once. **Recommended for the LAN.**
- **(b) Outside the LAN or unpaired:** the new device types the passphrase, derives the key with Argon2id and reads
  the salt from `vault.json`. **Recommended for the cloud.**
- **(c) QR with the wrapped key:** the QR carries the key encrypted with a key derived from the passphrase. A photo of
  the QR alone is not enough. But it adds nothing over (b): if the new device already has the passphrase, it can derive
  the key without the QR. **Not recommended.**

---

## 4. Conflicts

### 4.1 What happens today if the same sheet is edited on both sides

With the current format there is no reliable way to know whether both sides edited the same version. `rev` and
`updated` are local (section "Starting point"). A simple folder sync would let the last file that arrives overwrite
the other one, without warning.

To detect it, we need to store, per sheet, **the last version that was synced** (its hash, or the other machine's
`rev`). That is a new optional field in `notebook.json`, as was already done with `z` and `spacing`.

### 4.2 Options

**(a) Keep both versions (conflict copy).**
- If both sides changed relative to the last synced version, the version that arrives from the other side is saved
  as a new sheet "(conflicto)" (conflict). The local one stays where it was.
- Pro: nothing is lost. Simple. It is handled by the UI that already exists (one more sheet).
- Con: duplicate sheets that the user cleans up by hand. Two changes in different parts of the same sheet are also
  treated as a conflict.

**(b) Last write wins (by `updated`).**
- Pro: nothing to do.
- Con: strokes are silently lost. It depends on each tablet's clocks, which can be out of sync. **Not recommended.**

**(c) Merge by stroke id, with tombstones.**
- The strokes from both sides are joined. Deletions are stored as a list of deleted ids (tombstones). Since the eraser
  deletes whole strokes, the tombstone is just the id.
- Con: there are several problems to solve first:
  - The layer order (`z`) is position 0..n-1 and is renumbered on every save (`encodeSheet`). It is not stable across
    devices; it must be moved to a stable order **(design pending)**.
  - A formatted text (`TextBlock`) is a single whole object. Two edits to the same block are a conflict at the block
    level.
  - The background, paper, spacing, bookmark and title live in `notebook.json`: field-level rules would be needed.
  - A sheet deleted on one side and edited on the other.
  - Undo is not synced.
  - Media (`media/`) names have unique IDs, so they do not clash. But they must be synced too.

### 4.3 Recommendation

- **To start with: (a).** It loses no data, it is simple, and the UI already knows how to show sheets.
- **In the future: (c) for strokes**, once the stable layer order and the criterion for texts and sheets are resolved.
  Stroke IDs are unique (prefix + 12 hex) and deletion is by whole stroke, so the strokes part is the cheapest.

Effort of (a): base field per sheet in `notebook.json`, detection on load and on save, a "(conflicto)" sheet, and
handling Syncthing's `*.sync-conflict-*` files **(unconfirmed)**.

---

## 5. Comparison table

| Option | Security | Convenience | Effort | Dependencies and risks |
|---|---|---|---|---|
| **Folder + Syncthing** (installed separately) | High: TLS and ID list [10]. Visible that the machine runs Syncthing. | Medium: pair once in Syncthing, no accounts. Outside the home, depends on the machines finding each other **(unconfirmed)**. | Small to medium (Vynote: choose folder and conflicts). | Syncthing on all machines. Folder accessible from Android **(unconfirmed)**. |
| **Own LAN** (QR + mutual TLS + mDNS) | High if done well. The weak point is the first pairing (CVE-2020-26164 [8]). | High: QR once, no accounts. Only on the same network and with the app open. | Large. | `bonsoir`, `basic_utils`, `crypto` or `cryptography`, `dart:io`, `mobile_scanner` (does not scan on PC), `qr_flutter`. |
| **Google Drive + E2E** | Google cannot read the content; it does see metadata. | High: no server, sign in with Google. | Large. | `googleapis`; own login on PC; `cryptography`. |
| **WebDAV (Nextcloud) + E2E** | Same as Drive, but the server is our own. | Medium: you need a server. | Large. | `webdav_client` (little maintained) or direct HTTP. |
| **Export/import `.vynote`** | High: local file, no network. | Low: manual. | Medium. | ZIP. Complements the others, does not replace them. |

---

## 6. Recommendation

Small steps, each deliverable on its own.

1. **Step 1: PC app for Linux (medium effort).** Release build, stylus test with the project's Flutter version (which
   includes PR #186831), AppImage and a GitHub Actions job. Criterion: it draws with pressure on a Wacom tablet. It
   does not depend on sync.
   Before: fix `share_plus` and `record` on Linux, or disable those features there.

2. **Step 2: sync folder + conflicts (small to medium effort).** The user chooses the data folder (on PC, by default
   `Documentos/apuntes`). It is synced by Syncthing, or by the Drive or Nextcloud client, outside the app. Vynote adds
   the per-sheet base and the conflict copy. This already covers "at home" and "outside the home" with proven transport,
   without writing our own cryptography.
   Before: test on the tablet whether the folder is accessible from Syncthing (unconfirmed).

3. **Step 3: own LAN (large effort).** Only if we don't want to depend on Syncthing. Delivered in two parts: first pair
   and revoke, without syncing content. Then the sync. Prior tests: that `dart:io` verifies the client certificate
   against the list (unconfirmed), `bonsoir` on Android with `MulticastLock`, and `mobile_scanner` on the tablet.

4. **Step 4: cloud with end-to-end encryption (large effort).** First Nextcloud (WebDAV): the server belongs to the user
   and no OAuth is needed. Then Google Drive, because on PC it requires its own login.

Decisions needed before starting: whether the Android data folder can be accessible by Syncthing or must be changed,
and whether losing the passphrase is acceptable for the user.

---

## Decision: Google Drive

**Decided by the user (2026-11-21):** sync goes through **Google Drive**. The tablet (Android) and the Linux app connect
once with Google and from then on sync on their own. Scope `drive.file` (the app only sees what it creates), folder
`Vynote` in "Mi unidad" (My Drive). The Google Cloud project is created once by the owner; the client IDs go inside the
published app. Users only tap "Connect with Google".

Code: `lib/sync/`. The engine (`sync_engine.dart`, `sync_merge.dart`, `sync_state.dart`) knows nothing about Google: it
talks to the `RemoteStore` interface (`remote_store.dart`), which has an in-memory version for the tests
(`fake_remote_store.dart`) and the real one (`drive_remote_store.dart`, `googleapis` Drive v3). The login is in
`google_auth.dart`; the screen is in the ⋮ menu of the library ("Google Drive sync").

### Remote structure

It is the same structure as on disk, under `Vynote/` in "Mi unidad" (My Drive):

```
Vynote/
  index.json                         notebooks and folders
  notebooks/<id>/notebook.json       order and sheet data of the notebook
  notebooks/<id>/sheets/<sheet>.sheet one sheet (binary)
  media/<name>                       images and audio (unique name, only ever added)
```

Paths are validated with `sync_paths.dart` before touching the disk: anything that does not fit (`..`, other folders,
`prefs.json`, temporary files, `.roto`) is ignored. `sync_state.json` (local only) stores, per file, the **base**, the
known remote hash, the change token and the time of the last sync.

### What is uploaded and what is downloaded

- **Upload only what changed.** Per file, the md5 of the local copy is compared with the **base** (the md5 of the last
  version that ended up equal on both sides). If it did not change (same size and date as in the base), it is not even
  reread. Drive returns `md5Checksum` for each file, so no new field is needed in the files.
- **Download with the Drive changes API.** `changes.getStartPageToken` the first time; after that `changes.list` with the
  saved token returns only what changed (and what was deleted or moved to the trash). **Fallback:** if there is no token or
  Drive rejects it, everything is listed (`files.list`) and the `md5Checksum` is compared with what is known. Our own
  uploads also come back in the next delta with the same hash: they do nothing.
- **Order of the pass:** media, sheets, `notebook.json`, `index.json` and finally the deletions. That way, if it gets
  cut off, the other device never sees an index that points to something that has not arrived yet.

### Conflicts (per sheet)

Local, remote and base of each file are compared:

| Local | Remote | Result |
|---|---|---|
| equal to the base | changed | download |
| changed | equal to the base | upload |
| changed | changed | **conflict** (if they are not equal to each other) |

**Resolution on a sheet:** the local one stays where it was and the remote one is added as a new sheet "(conflicto)"
(conflict) **right after**. Both are uploaded, so the other device receives both and, after one more pass, both sides
have the same thing. Nothing is lost; the user deletes the extra one. A sheet is a whole file: two changes in different
parts of the same sheet also count as a conflict (see section 4, option (a)).

`notebook.json` and `index.json` do not generate conflict sheets: they are **merged** by `id` (three-way, with the saved
base). What was added on one side is added; what was deleted on one side is deleted if the other did not touch it; if it
changed on both, the newer one by `updated` stays. Each device's own data (the last sheet viewed, `rev`) is not
overwritten between devices.

### Deletions (tombstones), notebooks and folders

- **There are no tombstone files.** A file that is missing on one side and appears in the base **was deleted** on that
  side: it is deleted on the other if it did not change. If the other side had edited it, **editing beats deleting**: it
  is kept (and uploaded or downloaded again), along with the notebook that contains it. Files without a base (new ones)
  are never deleted.
- On Drive, deleting sends the file to the **trash** (it can be recovered from Drive; the 30-day window is
  **(unconfirmed)**).
- If the `Vynote` folder appears empty (it was deleted by mistake), nothing is deleted here: everything is uploaded again.
- **New notebooks and folders:** they appear in `index.json` and in `notebooks/<id>/`; the other side creates them.
  **Renaming or moving** changes only `index.json` (the `id` does not change), so the notebook is not uploaded again.
- Switching Google account starts from scratch (without deleting anything locally).
- **Example notebook.** Each installation creates "My notebook" on first launch. On the FIRST sync of a
  device (no base), if the cloud already has notebooks and the local one is that untouched example (only notebook, no
  folders, no PIN, a single empty sheet), it is discarded (deleted from disk without a tombstone, not uploaded) so that
  two copies of the example notebook do not end up existing. If it has anything written, or the cloud is empty, it is kept and uploaded.
- **Deletion with the app closed (Drive).** The first `changes()` of a new process is always a COMPLETE listing
  (`getStartPageToken` + `files.list`), even if a token is saved: with a delta, what was deleted while the app was not
  running would not appear in the freshly loaded map and would never come out as deleted. The engine treats the complete
  listing as the truth (what is in the base and not in the cloud is deleted here); if the folder really appears empty,
  nothing is deleted and it is uploaded again.
- **"Mapa cargado" (map loaded) is not "listado entregado" (listing delivered) (issue #9).** `crypto.wrap` downloads
  `crypto.json` before the first `changes()`, and that already loads the Drive map; if the delta were decided by "map
  loaded", whatever changed in Drive before (another device, or the Android background task, which is another process)
  would never appear and `index.json` would conflict forever. That is why `DriveRemoteStore` has `_listed`: until the
  engine has received a complete listing, `changes()` lists everything. Extra defense: if a file throws
  `RemoteConflictException`, the engine deletes the token and the next pass lists everything.

### Open notebook (golden rule)

**Decision (2026-11-21): with a notebook open, the engine UPLOADS but NEVER writes or deletes anything locally from that
notebook.**

- **Uploading is allowed.** What `Storage` has already saved to disk (`.sheet` sheets and `notebook.json`) can be
  uploaded even while the notebook is open: the file on disk is consistent because every write is atomic (temporary
  file + rename). So what you write reaches the cloud a few seconds after saving, without closing the notebook. It is
  only uploaded if the cloud is still at the base (nobody else touched it); a deletion made here (deleted sheet) is also
  propagated. `index.json` is the same: while any notebook is open it is upload-only (the library keeps it in memory).
- **Downloading is not.** If the cloud changed (or deleted) something in an open notebook, it is not applied: the
  notebook goes to `SyncReport.remoteWaiting` and the editor shows a discreet banner at the top, **"Hay cambios de otro
  dispositivo"** (There are changes from another device), with a **"Actualizar"** (Refresh) button. Refresh saves,
  closes the notebook, runs a pass (now without the notebook open: the usual rules apply, i.e. a "(conflicto)" sheet if
  both sides changed) and opens it again. If the banner is ignored, the changes are applied only when the notebook is
  closed (the library syncs when you return to it).
- **Why it is not applied live (reloading the sheet inside the open document).** It was evaluated (detach + attach of the
  sheet, or the lazy-loading mechanism) and discarded due to risk: (1) `NotebookDoc` also keeps `notebook.json` (order,
  titles, added or deleted sheets) in `nb.sheets`, which the screen, the sheets panel and undo share; a new or moved sheet
  coming from another device would force reconciling that with the undo history, which points to elements that would
  disappear; (2) a sheet that is "dirty or has unsaved changes" may be mid-gesture (stroke in progress, selection); (3)
  `Storage` remembers each file's hash on disk so it only saves what changed, and an external change would invalidate it
  right when writing; (4) the cost of an error is losing the user's writes, and the banner with a button does not carry
  that risk. It stays as a future improvement: apply live only the changed remote sheets that are not dirty and have no
  structural changes.
- **Races.** Which notebooks are open is checked before EACH file and again right before writing it to disk; if the user
  opened it in the meantime, that write is skipped and left for later. What the sync writes to disk (closed notebooks)
  goes through the same atomic writes of `Storage`, and a file that changed between being read and being written is not
  overwritten (it is left for the next pass).

### No network, interruptions and errors

Without a network the pass is cut off and retried with **backoff** (30 s, 1 min, 2 min, 4 min, 8 min, and every 10 min
from then on); returning to the foreground or "Sync now" cut the wait short and retry right away. In
the background there is no retry (it resumes when you return). Nothing is lost. The state is saved **after each file**,
so repeating the pass converges (it is idempotent). A file that fails does not stop the others. If the session expired
or was revoked, the state goes to "disconnected" and you have to tap "Connect with
Google". There is no connectivity plugin: "network is back" is detected by the next retry, the next periodic check or
returning to the foreground.

### When sync happens

Everything is decided by `SyncController` (`lib/sync/sync_controller.dart`); the engine only does a pass when asked.

| Trigger | When | Cost |
|---|---|---|
| Open the app | on start, if there is a session | one pass |
| **Upload soon** | `Storage` signals (`onSaved`) when it finishes writing something (dirty sheets, `notebook.json`, or an index change that gets synced: opening a notebook does not count). Waits **5 s since the last save**, and **at most 30 s since the first** if writing continues non-stop | one pass per burst |
| **Download soon** | with the app **in the foreground**, every **45 s**, a single `changes.list` call with the saved token; if there are no changes nothing is downloaded | 1 call |
| Return to foreground | `AppLifecycleState.resumed`: pass right away, and the polling resumes | one pass |
| Go to background | if there is something saved but not uploaded, it is uploaded now (Android may close the app); no periodic polling | one pass |
| Close a notebook | when returning to the library | one pass |
| "Sync now" | manual; cuts the backoff short | one pass |

**Never two passes at once:** a request that arrives while one is running (poll, debounce, "now"...) does not start
another: it marks "one more when this finishes", and any that arrive in the meantime are merged into that one. With the
app closed, see "Background (Android)".

**Indicator.** In the bar at the top of the library and the editor, a small icon (no text; the text is in the tooltip):
cloud with a check = synced, spinning cloud = syncing, cloud with an arrow = changes waiting to upload, crossed-out cloud
= no connection, triangle = error. It is not shown if there is no Google session. Tapping it opens the Sync sheet.

### Background (Android)

With the app closed or in the background, a periodic `workmanager` task runs (every **15 min**, Android's minimum, only
with a network). It is registered when you connect to Google and when the app opens with a session
(`ExistingPeriodicWorkPolicy.update`); it is cancelled on disconnect. There is a "Sync in
background" switch in the Sync sheet (library ⋮ menu; on by default, saved as `bgSync` in `prefs.json`; only shown on
Android: on Linux the timers already run with the window minimized). Code: `lib/sync/background_sync.dart`.

- **Separate isolate, no UI.** The callback (`backgroundSyncDispatcher`) sets up `Storage` + `GoogleBackend.restore()` +
  the engine and calls `runBackgroundPass`, a shared, testable function (without WorkManager). If `restore()` gives no
  session or throws, it ends without doing anything and without an error.
- **Never at the same time as the app.** A lock `sync.lock` in the data folder (PID, owner and time; created exclusively;
  **expires after 10 min** so an abandoned one does not block forever), which both passes take, the `SyncController` one
  too (if the background one holds it, it waits 15 s and retries). In addition, the app marks `sync.fg` while it is in
  the foreground (renewed on each poll; valid for 3 min): with the app in the foreground the background task does nothing.
- **Open notebooks.** When the app goes to the background it notes in `sync.busy` the notebooks open in the editor: the
  background task only uploads their changes, it does not write over them (same golden rule). The mark is deleted when the
  app opens.
- **Return to foreground.** If the task downloaded changes it leaves `sync.bgchanged`; the app's next pass consumes it and
  rereads the index and thumbnails from disk (`onBackgroundChanged`).
- **Session in the background isolate (Android): its own refresh token.** `google_sign_in` needs an `Activity` to resume the
  session, and the background task has none. So, with the app in the foreground (when connecting, or when opening the app
  if there is still no token), `google_sign_in` is asked for a `serverAuthCode` (`authorizeServer`), which is exchanged at
  `https://oauth2.googleapis.com/token` with the Web client (`GOOGLE_WEB_CLIENT_ID` + `GOOGLE_WEB_CLIENT_SECRET`), and the
  refresh token is stored in the secure storage along with the account (`lib/sync/refresh_token_auth.dart`). The
  background task (`GoogleBackend.restoreInBackground`) gets access tokens with that refresh token, without touching
  `google_sign_in`. If Google responds `invalid_grant` the token is deleted and the app asks for it again the next time
  in the foreground. On disconnect it is revoked at Google and deleted. The foreground app keeps using `google_sign_in` as
  always. If the `GOOGLE_WEB_CLIENT_SECRET` secret is missing, everything works the same and only background sync does not.

### Drive API quotas: how many calls we make

With the app open in the foreground:

- **Idle** (nothing to upload or download): 1 `changes.list` every 45 s = **80 calls per hour**.
- **Writing non-stop:** at most one pass every 30 s (2 per minute, 120 per hour); each pass = 1 `changes.list` + the uploads
  of what changed (typically 1 or 2 sheets + `notebook.json`, and each upload with optimistic concurrency control, i.e. 1 to
  3 calls per file) = around 5 to 10 calls. On the order of **300 to 1200 calls per hour** in the worst case, and only while
  you are actually writing.
- **Two devices open at once:** the polls add up (160 per hour idle).
- Background: **0** periodic polls.

Against the quota: Google now measures the Drive API in "quota units": **1,000,000 per minute per project and 325,000 per
minute per user per project**, with no daily request limit as long as the per-minute limit is respected (the only daily
cap listed is 1 TB of upload per project) [Google, "Usage limits | Google Drive",
<https://developers.google.com/workspace/drive/api/guides/limits>, accessed 2026-11-21]. How many units each specific call
costs **(unconfirmed: the page does not show it in the part
read)**; even assuming a few dozen units per call, 80 to 1200 calls per hour is on the order of 0.1 to 6 calls per minute,
thousands of times below the limit for a single user. (Previously the quota was counted in requests: "12,000 per 60 s per
project" and "1,000,000,000 per day" **(unconfirmed, from old documentation)**;
also far above.) The quota is **per Google Cloud project** and is shared among all the app's users: with many users the
per-minute limit of the project (1,000,000 units) is what to watch; with 1,000 users polling every 45 s it is about 1,300
calls per minute in total. The periodic poll is cheap for the battery: a small HTTPS request every 45 s with the screen on
and the app visible.

### End-to-end encryption (optional)

Code: `lib/sync/e2e_crypto.dart` (format and keys), `encrypted_remote_store.dart` (decorator of `RemoteStore`),
`sync_crypto.dart` (state, saved key, enable / disable / passphrase), UI in `lib/screens/library/crypto_section.dart`
(Sync sheet, "Encryption" section). Tests: `test/sync/e2e_test.dart`.

**What Google sees with encryption on:** meaningless files (encrypted content), their **number, sizes and dates**, and
their **paths**. The paths (`notebooks/<id>/sheets/<sheet>.sheet`, `media/<name>`) **are left in clear on purpose**: they
are random IDs, they do not carry the notebook's name (the name is inside `index.json`, which is encrypted), and this way
the engine and the Drive changes API keep working the same. What is not hidden: how many notebooks and sheets there are
and when they are touched.

**Scheme**

- Passphrase chosen by the user (minimum 8 characters) → 32-byte key with **Argon2id** (`cryptography` package 2.9.0, the
  latest version available when this was done) and a **random 16-byte salt**. The derivation runs in another isolate so as
  not to freeze the screen.
- **Parameters: 64 MiB of memory, 3 passes, 1 thread** (RFC 9106, the second option recommended for low memory). In pure
  Dart there is no real parallelism, so 1 thread is used. **Measured on the development PC (Linux, Dart JIT): 585 ms**
  (with 19 MiB and 2 passes: 217 ms). **NOT measured on the Galaxy Tab S6 Lite**: estimated at about 3 to 5 seconds (several
  times slower); it is only paid when enabling encryption and when entering the passphrase on a new device. The parameters
  travel in `crypto.json`, so they can be changed in a future version without breaking clouds already encrypted.
- **Each file:** XChaCha20-Poly1305 with a random 24-byte nonce (it does not repeat in practice). Format:
  `ONCR` (4 magic bytes) + version (1 byte, currently 1) + nonce (24) + ciphertext + tag (16). Associated data (AAD):
  version + **file path**, so an encrypted file cannot be moved to another path without failing. Measured: 5 MiB encrypt in
  ~170 ms and decrypt in ~140 ms (PC).
- **`Vynote/crypto.json`** (in clear, no secrets): `version`, `cipher`, KDF parameters, `salt`, `verifier` (a known text
  encrypted with the key: decrypting it correctly proves the passphrase is right) and `migrating` (null, or
  `encrypting` / `decrypting` while the encryption is being changed). If it exists, the cloud is encrypted.
- **The derived key (not the passphrase) is stored in the secure storage** (`TokenStore` / `flutter_secure_storage`:
  Keystore on Android, libsecret on Linux) under the key `opennote.sync.e2e.key`. It is deleted on Google disconnect. On a
  new device, when connecting and seeing `crypto.json`, the app asks for the passphrase: with a wrong one it does not sync
  and warns ("La frase de cifrado es incorrecta" (The encryption passphrase is incorrect)); it does not retry by itself.
- **If the passphrase is forgotten there is no way to recover what is in the cloud** (local data stays intact). The UI warns
  about this in the section and in the activation dialog.

**The hashes (the delicate part).** The engine compares the md5 of the local (clear) file with the base and with the md5
reported by the remote. With encryption, the remote md5 is of the ciphertext and changes on every upload (random nonce)
even when the content is the same: the engine would see endless conflicts or uploads. The engine was not touched:
`EncryptedRemoteStore` **always speaks clear-text hashes** to it and keeps track of the mapping (cloud ciphertext md5 →
clear md5) in a per-path cache (`HashCache`, saved in `sync_crypto_cache.json`, local only):

1. On **upload**: computes the clear md5, uploads the ciphertext and records (md5 returned by the cloud → clear md5).
   Returns the clear md5 to the engine. The `ifRemoteMd5` the engine sends (clear) is translated to the ciphertext one
   before being passed on.
2. On **listing changes**: translates each cloud md5 using the cache. Our own uploads that come back in the next delta
   show the same clear hash: they do nothing. If the file is new (uploaded by another device) it downloads and decrypts it
   **once** to learn its clear hash (a few MB are kept in memory so the engine's `download` does not fetch it twice) and
   records it. If the cache is lost nothing breaks: it is rebuilt by downloading (the `upload` also self-corrects).
3. A cloud file that is **unencrypted or does not decrypt** stops the pass with a clear error. It is not ignored: the engine
   would take it as "deleted in the cloud" and would delete the local copy.
4. The decorator hides `crypto.json` from the engine and watches its content: if another device changed it (enabled,
   disabled or redid the encryption) the pass is cut off and it is reread; if the cloud folder appeared empty, it
   **restores `crypto.json`** before uploading anything (nothing unencrypted is ever uploaded while encryption is on). With
   the cloud unencrypted, a minimal wrapper (`PlainRemoteStore`) detects that `crypto.json` appeared.

Measured in the tests: with two devices, successive passes without changes do 0 file uploads and 0 file downloads.

**Enabling with data already in the cloud (implemented: re-uploads everything encrypted)**

1. The key is derived and a normal pass is run (everything up to date).
2. `crypto.json` is uploaded with `migrating: encrypting` (other devices that connect now ask for the passphrase) and the
   key is stored in the secure storage.
3. Each cloud file is downloaded, **permanently deleted** (Drive `files.delete`, not the trash: otherwise the clear text
   would sit for 30 days in the trash and as an old revision) and uploaded again encrypted. Those already encrypted are
   skipped.
4. `crypto.json` is uploaded again with `migrating: null`.

**Disabling** is the reverse (it is marked `decrypting`, each file is downloaded, decrypted, deleted and uploaded in clear;
at the end `crypto.json` and the device key are deleted). If it is cut off midway (no network, app closed), `crypto.json`
stays marked and **the next pass from a device that has the key resumes it**. When an encryption change starts or fails,
`sync_state.json` (the base) is deleted: otherwise a file that was deleted from the cloud midway would be taken as a
deletion in the cloud and the local copy would be deleted; without a base, the engine uploads it again. Local notebooks are
never touched.

**Known limits and risks**

- **Visible metadata:** number of files, sizes, dates and paths (see above).
- **Rollback:** the cloud can return an old version of a file that is still valid (the AAD carries the path but not a
  counter). Not resolved (see section 3.2).
- **Integrity across devices during an encryption change:** do not touch the cloud from another device while enabling or
  disabling; two devices converting at the same time should converge but this was not tested.
- **Encrypting large files in pure Dart:** loads the whole file into memory (the images in `media/` are a few MB each).
- **Not tested against real Drive or on the tablet** (no tablet connected); only with the fake remote in the tests. In
  particular the permanent Drive deletion (`files.delete`) and the Argon2id time on the tablet.
- **Linux without a keyring:** if the system has no secure storage, the key cannot be saved and the passphrase is asked
  for again.

### Security

- **Tokens.** Android: handled by `google_sign_in` / Google Play services; the app does not store any. Linux: the refresh
  token goes in the system's secure storage (`flutter_secure_storage`, libsecret on Linux); if the system has no keyring,
  see the note in `google_auth.dart` (not tested on a PC without a keyring **(unconfirmed)**).
- **Scope.** `drive.file`: the app sees nothing else in your Drive. It is a "non-sensitive" permission **(exact classification unconfirmed: if it is,
  Google verification is not needed)**.
- **The desktop client secret is not confidential** [according to Google, installed apps cannot keep it secret]. It goes in
  the app along with the ID. What protects the account is the user's consent and PKCE.
- **Google can read what is uploaded** unless end-to-end encryption is enabled (section "Encryption", below). It is
  optional and comes off by default.

### Set up Google Cloud (owner steps)

Done once. Users do none of this. Nobody has run these steps yet: the app compiles without them and warns that setup is
missing.

1. At <https://console.cloud.google.com/> create a project (for example "Vynote").
2. **"APIs y servicios" (APIs & Services) > "Biblioteca" (Library):** enable **Google Drive API**.
3. **"Pantalla de consentimiento OAuth" (OAuth consent screen):** user type **External**; app name, support email; add the
   scope `.../auth/drive.file`.
4. **Move the app to "In production" ("Publicar la app" (Publish app)).** If it stays in *Testing*, Google makes refresh
   tokens expire after **7 days** (confirmed in Google's doc: "Using OAuth 2.0 to Access Google APIs", section *Refresh
   token expiration*, unless the scopes are only name, email and profile), and you would have to reconnect every week.
   With `drive.file` in production, "app no verificada" (app not verified) may appear until Google reviews it **(unconfirmed whether `drive.file` requires verification)**; until then the
   user can continue with "Avanzado" (Advanced).
5. **"Credenciales" (Credentials) > "Crear credenciales" (Create credentials) > "ID de cliente de OAuth" (OAuth client ID)**,
   three clients:
   - **Android** `io.github.santiagofr1.vynote` with the **SHA-1 of the release key** (the keystore from the repo secrets; the owner
     adds it: `keytool -list -v -keystore release.jks`).
   - **Android** `io.github.santiagofr1.vynote.test` with the debug SHA-1:
     `F5:83:13:66:18:80:5D:F9:69:D6:EE:D9:C3:EA:82:AC:07:E2:FF:56`.
   - **"Web application"** (`google_sign_in` asks for it on Android as `serverClientId`; it is not used for
     anything else).
   - **"Desktop app"** for Linux (gives an ID and a secret).
6. Set the values:

| Value | GitHub secret (Settings > Secrets > Actions) | Local (`--dart-define`) |
|---|---|---|
| Web client ID | `GOOGLE_WEB_CLIENT_ID` | `GOOGLE_WEB_CLIENT_ID` |
| Web client secret (Android background, optional) | `GOOGLE_WEB_CLIENT_SECRET` | `GOOGLE_WEB_CLIENT_SECRET` |
| Desktop client ID | `GOOGLE_DESKTOP_CLIENT_ID` | `GOOGLE_DESKTOP_CLIENT_ID` |
| Desktop client secret | `GOOGLE_DESKTOP_CLIENT_SECRET` | `GOOGLE_DESKTOP_CLIENT_SECRET` |

   The Android clients carry no value in the app: Google recognizes them by the package name and the signature.
   The release workflow builds `google_config.json` from those secrets and compiles with
   `--dart-define-from-file=google_config.json`. If `GOOGLE_WEB_CLIENT_ID` is missing, the release goes out without sync
   (with a warning). Locally: copy `google_config.example.json` to `google_config.json` (ignored by git) and run
   `flutter run --dart-define-from-file=google_config.json`.
7. If the tablet's release key is uploaded or the keystore changes, the Android client's SHA-1 must be updated.

### Known risks

- **Background untested on the tablet:** the `serverAuthCode` exchange (`authorizeServer` may show the permission screen the
  first time, and Google does not always return a refresh token if one was already issued for that account and client; in
  that case background sync has no token until you revoke the app's access in the Google account and connect again). The
  Web client secret ships inside the app, same as the desktop one: it is not confidential.
- Drive has no conditional write: two devices uploading the same sheet at the very same moment can overwrite each other.
  It is mitigated by comparing the hash right before uploading; the remaining case is very narrow.
- With `drive.file` only the files created by this app are visible; if the user uploads or moves files by hand inside
  `Vynote`, the app does not see them.
- Two folders with the same name (if two devices create `notebooks/` at once) are treated as the same by path.

---

## 7. Sources

Read directly:

1. https://github.com/flutter/flutter/issues/63209 (pressure and PointerDeviceKind on Linux, closed 2026)
2. https://github.com/flutter/flutter/pull/186831 ("Improve stylus support on linux", merged)
3. https://github.com/adil192/saber/issues/90 (Saber, stylus on Linux)
4. https://github.com/dart-windows/win32/discussions/843 (tablets in Flutter Windows)
5. https://www.github.com/saber-notes/saber/issues/1218 (Saber, pressure on macOS)
6. https://pub.dev/packages/stylet (Stylet, pressure per platform)
7. https://github.com/flutter/flutter/issues/196867 (stroke samples lost on Android)
8. https://seclists.org/oss-sec/2020/q4/169 (CVE-2020-26164, KDE Connect)
9. https://pkg.go.dev/github.com/bethropolis/kcd/internal/cert (third-party implementation, unconfirmed)
10. https://docs.syncthing.net/users/security (Syncthing: IDs, TLS, discovery)
11. https://github.com/localsend/protocol (LocalSend: fingerprint, multicast, HTTPS)
12. https://api.dart.dev/dart-io/HttpServer/bindSecure.html
13. https://api.dart.dev/dart-io/SecurityContext-class.html and https://api.dart.dev/dart-io/HttpClient/badCertificateCallback.html
14. https://pub.dev/packages/path_provider (and the package pages in section 1.4, listed below)
15. https://docs.flutter.dev/deployment/linux
16. https://docs.flutter.dev/deployment/windows
17. https://docs.flutter.dev/deployment/macos
18. https://developer.apple.com/documentation/security/customizing-the-notarization-workflow (read via search summary)
19. https://docs.github.com/en/actions/reference/runners/github-hosted-runners
20. https://pub.dev/packages/basic_utils
21. https://pub.dev/packages/mobile_scanner
22. https://pub.dev/packages/bonsoir
23. https://developer.android.com/reference/android/net/wifi/WifiManager.MulticastLock
24. https://developer.android.com/topic/performance/power/power-details (via search summary)
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

pub.dev package pages checked for the table in section 1.4 (all at `https://pub.dev/packages/<name>`):
`path_provider`, `file_picker`, `image_picker`, `printing`, `share_plus`, `record`, `audioplayers`, `dynamic_color`,
`material_ui`.

Reference that came only from search (not read in full): https://docs.syncthing.net/dev/device-ids
