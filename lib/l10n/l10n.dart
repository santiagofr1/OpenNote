import 'package:flutter/widgets.dart';

import '../data/vynote_file.dart';
import '../editor/voice_recorder.dart';
import '../sync/remote_store.dart';
import '../sync/sync_crypto.dart';
import 'app_localizations.dart';

export 'app_localizations.dart';

/// `context.l10n.clave`: los textos de la app en el idioma elegido.
extension L10nX on BuildContext {
  L get l10n => L.of(this);
}

/// Texto de un error para mostrárselo al usuario en el idioma de la app. Los errores propios (con tipo) se traducen;
/// el resto se muestra como vienen.
String errText(L l, Object e) {
  if (e is VynoteException) {
    final a = e.arg ?? '';
    return switch (e.kind) {
      VynoteError.notReadable => l.errImportNotReadable,
      VynoteError.missingFile => l.errImportMissingFile(a),
      VynoteError.brokenFile => l.errImportBrokenFile(a),
      VynoteError.notVynote => l.errImportNotVynote,
      VynoteError.newerVersion => l.errImportNewerVersion,
      VynoteError.brokenSheetList => l.errImportBrokenSheetList,
      VynoteError.noSheets => l.errImportNoSheets,
      VynoteError.brokenSheet => l.errImportBrokenSheet(a),
      VynoteError.brokenSheetAny => l.errImportBrokenSheetAny,
      VynoteError.invalidNames => l.errImportInvalidNames,
      VynoteError.notZip => l.errImportNotZip,
      VynoteError.noNotebooks => l.errImportNoNotebooks,
      VynoteError.other => e.message,
    };
  }
  if (e is VoiceException) {
    return switch (e.kind) {
      VoiceError.busy => l.errVoiceBusy,
      VoiceError.noPermission => l.errVoiceNoPermission,
      VoiceError.failed => l.errVoiceFailed(e.detail ?? ''),
    };
  }
  return '$e';
}

/// Texto de un error de sincronización ([SyncError]) en el idioma de la app. [fallback] es el mensaje en español que
/// trae el error (para los que no tienen traducción).
String syncErrorText(L l, SyncError? kind, String? arg, String fallback) => switch (kind) {
      null || SyncError.other => fallback,
      SyncError.offline => l.syncErrOffline,
      SyncError.authExpired => l.syncErrAuthExpired,
      SyncError.conflict => l.syncErrConflict,
      SyncError.notFound => l.syncErrNotFound,
      SyncError.vaultChanged => l.syncErrVaultChanged,
      SyncError.cryptoLocked => l.syncErrCryptoLocked,
      SyncError.wrongPassphrase => l.syncErrWrongPassphrase,
      SyncError.cryptoOtherDevice => l.syncErrCryptoOtherDevice,
      SyncError.cloudNotEncrypted => l.syncErrCloudNotEncrypted,
      SyncError.filesFailed => l.syncErrFilesFailed(arg ?? ''),
      SyncError.couldNotSync => l.syncErrCouldNotSync(arg ?? ''),
      SyncError.connectFirst => l.syncErrConnectFirst,
      SyncError.backgroundBusy => l.syncErrBackgroundBusy,
    };

/// Texto del paso de cifrado en curso ([SyncCrypto.step]) en el idioma de la app.
String cryptoStepText(L l, SyncCrypto c) => switch (c.step) {
      null => c.progress ?? '',
      CryptoStep.deriving => l.cryptoStepDeriving,
      CryptoStep.syncBeforeEncrypt => l.cryptoStepSyncBeforeEncrypt,
      CryptoStep.syncBeforeDecrypt => l.cryptoStepSyncBeforeDecrypt,
      CryptoStep.encrypting => l.cryptoStepEncrypting(c.stepDone, c.stepTotal),
      CryptoStep.decrypting => l.cryptoStepDecrypting(c.stepDone, c.stepTotal),
    };
