# How to Contribute to Vynote

Thanks for pitching in! Every contribution counts: code, issues, ideas, documentation, tests on other tablets or translations.

## Getting Started

```sh
git clone https://github.com/<your-username>/Vynote   # your fork
cd Vynote
flutter pub get            # installs dependencies
flutter run                # runs the app on a connected tablet or emulator
flutter test               # pure-logic tests, on the PC
```

You need Flutter on the *stable* channel. To build for the tablet you also need the Android SDK and JDK 21
(with `JAVA_HOME` pointing to it).

## Branches

- **`main`**: what gets published. Every push builds and makes a release (APK, `.deb` and `.exe`), so it only receives
  merges from `dev`.
- **`dev`**: features already tested on the tablet. When a few of them are ready together, `dev` is merged into `main`.
- **Working branches** (`feat/…`, `fix/…`): branch off `dev` and merge back into `dev`. **PRs target `dev`**, not
  `main`. Once merged, they get deleted.

## Before Sending a PR

- `flutter analyze` with no new warnings. If your change adds a warning, fix it before asking for review.
- `flutter test` has to be green.
- **Don't run `dart format`.** The repo is written at about 120 columns and doesn't use a formatter: running it reformats
  whole files and dirties the diff. Keep the style of the code around yours.
- One PR per topic. If it's a big change (a new feature, or something that touches a lot of the architecture), it's
  best to open an issue first to talk it through.
- If you touch the UI or the pen, test on a real tablet and say so in the PR. The PR template has a checklist for that.

## Tablet Tests

```sh
./run_tests.sh             # integration suite on the tablet connected via adb
BACKUP=1 ./run_tests.sh    # same, but also downloads a copy of your real notebooks
```

`./run_tests.sh` installs a separate app, **"Vynote Test"** (`io.github.santiagofr1.vynote.test`), with its own data.
It never touches the real app or your notebooks: at the end, it checks that the real app and its files are still the same.

`INTEGRACION=1 ./test_pc.sh` (on top of the usual unit tests) runs the full integration suite (`app_test.dart` and
`layout_sizes_test.dart`) in the Linux app, simulating the tablet screen; whatever needs the real pen, ML Kit or the
background sync still needs a device. The app runs on a virtual display (Xvfb) so no window pops up; use `VER=1` to see it.

Rule for new features: **every new feature adds a case to `integration_test/app_test.dart`.** If needed, also add a
pure-logic test in `test/`.

## Google Drive Sync

The sync uses a Google Cloud project owned by the repository owner. Its client IDs **are not in the repo**: the release
workflow passes them in from secrets. If you fork it and want to test the sync (or publish your own version), you need
**your own Google Cloud project**: the steps are in [docs/SYNC.md](docs/SYNC.md), "Set up Google Cloud". Copy
`google_config.example.json` to `google_config.json` (it's in `.gitignore`) and run with
`--dart-define-from-file=google_config.json`. Without that data, the app still builds and works the same, except that
**"Conectar con Google"** (Connect with Google) warns that it needs to be configured. The sync tests (`test/sync/`) use
an in-memory fake remote and don't need anything from Google.

## Performance

If your change could affect speed or memory (drawing, loading, saving, scrolling), measure it:

- `tool/perf.sh`: measures notebooks of 50, 100, 200 and 400 pages on the tablet (takes about 15–25 minutes).
  `SIZES=100,200 tool/perf.sh` runs only those sizes.

Paste the numbers from before and after into the PR.

## Where Everything Lives

```
lib/domain/      pure data without Flutter: pages, strokes, notebooks, folders, tools (with tests)
lib/sync/        Google Drive sync: engine, fake remote, Drive, login
lib/data/        storage (Storage), binary format, migration, PDF/PNG export, import
lib/rendering/   stroke drawing (meshes), paper, full pages, editor layers
lib/editor/      page-strip editor, pen input, selection, undo, zoom, toolbar
lib/screens/     library and open notebook
lib/widgets/     shared dialogs
lib/theme/       theme and colors
```

Each layer only uses the ones above it. If a piece of logic can go in `lib/domain/` without depending on Flutter,
put it there and cover it with tests.

## Style

- Comments and interface texts are written in **Spanish**.
- Follow the rules in `analysis_options.yaml`.
- Small, focused changes: one PR, one topic.

## Reporting a Bug

Use the [bug report template](https://github.com/santiagofr1/Vynote/issues/new/choose). Include:

- **Tablet model** (for example, Galaxy Tab S6 Lite SM-P620) and **pen** (S Pen, USI or other).
- **Android version**.
- **Vynote version**: the release tag (for example, `v1.0.42`) or the commit if you built it yourself.
- What you did, what you expected and what happened. If it crashed, tell us whether it happened when opening a notebook
  or while writing.

## License

By contributing, you agree that your contribution will be published under the project's
[GPL v3 or later](LICENSE) license.
