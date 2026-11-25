# Vynote Releases

Every push to `main` builds, tests and automatically publishes a signed APK to GitHub Releases.
Pushes that only touch documentation (`**.md`, `docs/**` or `.github/ISSUE_TEMPLATE/**`) do not
trigger a release. It can also be started by hand from **Actions → Release → Run workflow**.

## How it works

The `.github/workflows/release.yml` workflow:

1. Runs `flutter pub get`, `flutter analyze --no-fatal-infos` and `flutter test`.
2. Computes the version from the GitHub Actions run number:
   - `versionName`: `1.0.<run_number>` (for example, `1.0.42`).
   - `versionCode`: `<run_number> + 100` (for example, `142`), always greater than the local `1`.
3. Signs the APK with the release key stored in the repository secrets.
4. Publishes the APK as `Vynote-v1.0.<run_number>.apk` in a GitHub Release tagged
   `v1.0.<run_number>`, using the commit subjects since the previous `v*` tag as the release notes.
5. Marks that release as the latest (`make_latest`).

Then the `linux` job runs (Ubuntu 24.04, `needs: release`): it runs `flutter build linux --release`, builds
`vynote_<version>_amd64.deb` with `tool/build_deb.sh` (same version `1.0.<run_number>`, with the Google IDs
from the same secrets) and uploads it to the same release with `gh release upload`. If that job fails, the APK
and the Android update notice keep working (the app only picks the `.apk` asset). The release notes include
the installation instructions for Linux. At the end it notifies the apt repo (`santiagofr1/apt`) with a
`repository_dispatch` event of type `publish`, which downloads the `.deb` from the Releases and republishes the
index. The `APT_DISPATCH_TOKEN` secret is optional (a fine-grained token with *Contents: read and write* on
`santiagofr1/apt`): without it the job does not fail, and the apt repo's hourly cron job picks the release up
anyway. For apt to pick it up, `santiagofr1/Vynote` must be listed in that repo's `apps.txt`.

The `windows` job (`windows-latest`, `needs: release`) follows the same pattern: it runs
`flutter build windows --release` (`--build-name=1.0.<run_number>`, `--build-number=<run_number> + 100`, with the
Google IDs from the same secrets), builds the installer with Inno Setup (`windows/installer/vynote.iss`, version
passed via `/DAppVersion=`; it uses `iscc` and, if that is missing, runs `choco install innosetup`) and uploads
`Vynote-v<version>-windows-setup.exe` to the same release with `softprops/action-gh-release@v2`. The installer's
`AppId` is fixed, so a new version installs over the previous one. If the job fails, the APK and the .deb are not
affected. The installer is not signed (SmartScreen will warn). The release notes mention the Windows asset.

If the keystore secret is missing, the job fails on purpose. A signed release is never published with the
debug key.

## Cleaning up old releases

At the end of the job, the "Podar releases viejos" step runs `tool/podar_releases.sh`, which keeps only the
latest 2 releases (`KEEP=2` in the step) and deletes the rest with `gh release delete <tag> --cleanup-tag --yes`
(this also deletes the tag). Rules:

- It only touches tags matching `^v1\.0\.[0-9]+$`; it ignores drafts, prereleases and any other tag.
- It sorts by creation date and never deletes the release marked Latest or the one just published (`CURRENT_TAG`).
- It only runs if the publish succeeded. If a deletion fails, it emits a warning and moves on to the rest;
  the step is `continue-on-error`, so it does not fail the workflow.
- It uses `GH_TOKEN` (`github.token`) and the `contents: write` permission the workflow already has.
- The app only checks the latest release, so the update notice is not affected.

To test the selection without deleting anything:
`gh release list --json tagName,createdAt,isLatest,isDraft,isPrerelease --limit 200 | DRY_RUN=1 tool/podar_releases.sh`

## Repository secrets

These four secrets must be set in **Settings → Secrets and variables → Actions → New
repository secret**:

| Secret | Content |
| --- | --- |
| `ANDROID_KEYSTORE_BASE64` | The `release.jks` file encoded in base64. |
| `ANDROID_KEYSTORE_PASSWORD` | The keystore password. |
| `ANDROID_KEY_ALIAS` | The key alias (for example, `vynote`). |
| `ANDROID_KEY_PASSWORD` | The key password. |

### 1. Create the keystore (first time only)

With JDK 21:

```bash
~/Android/jdk21/bin/keytool -genkey -v \
  -keystore release.jks \
  -keyalg RSA \
  -keysize 4096 \
  -validity 10000 \
  -alias opennote
```

`keytool` asks for the keystore password, the certificate details and the key password.
You can use the same password for both, but it is best to save both.

### 2. Encode the keystore in base64

```bash
base64 -w0 release.jks > release.jks.base64
```

The resulting file is one long line. That is the value for `ANDROID_KEYSTORE_BASE64`.

### 3. Load the secrets with the GitHub CLI

```bash
gh secret set ANDROID_KEYSTORE_BASE64 < release.jks.base64
gh secret set ANDROID_KEYSTORE_PASSWORD
gh secret set ANDROID_KEY_ALIAS
gh secret set ANDROID_KEY_PASSWORD
```

The last three commands prompt for the value interactively, so it does not end up in the shell history.
They can also be set from the GitHub web interface.

## Keystore backup

**Keep a private, secure copy of `release.jks`, its alias and its passwords.** If the key is lost:

- You cannot publish an update that Android will accept over the app already installed.
- You would have to publish a new app with a different `applicationId`, and users would lose the
  continuity of updates.

Do not upload the keystore or `android/key.properties` to the repository: they are already in `.gitignore`.
The GitHub secret is the copy CI uses; the private backup is the recovery copy.

## First install of a signed release

The release app installs over a previous installation **only if both are signed with the same key**. If the
tablet has a version signed with the debug key (for example, installed with `./build_install.sh`), Android
rejects the first release signed with the new key.

Before installing that first release:

1. Back up the notebooks from the app.
2. Uninstall Vynote on the tablet.
3. Install the release APK.

Uninstalling deletes the app's local data, which is why the backup is mandatory. After this one-time
migration, later releases update normally without uninstalling.

## Testing the signing locally

To build a local release with the real key, create `android/key.properties` (it is not versioned):

```properties
storeFile=/absolute/path/to/release.jks
storePassword=...
keyAlias=opennote
keyPassword=...
```

If the file does not exist, `android/app/build.gradle.kts` uses the debug signing so that
`./build_install.sh` and `flutter run --release` keep working in development.
