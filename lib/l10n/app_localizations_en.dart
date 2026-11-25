// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class LEn extends L {
  LEn([String locale = 'en']) : super(locale);

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonDone => 'Listo';

  @override
  String get commonCreate => 'Crear';

  @override
  String get commonDelete => 'Borrar';

  @override
  String get commonClose => 'Cerrar';

  @override
  String get commonLater => 'Después';

  @override
  String get commonNotNow => 'Ahora no';

  @override
  String get paperLined => 'Rayado';

  @override
  String get paperGrid => 'Cuadriculado';

  @override
  String get paperDots => 'Puntos';

  @override
  String get paperMm => 'Milimetrado';

  @override
  String get paperAxes => 'Ejes cartesianos';

  @override
  String get paperBlank => 'Liso';

  @override
  String get paperCornell => 'Cornell';

  @override
  String get paperTodo => 'Lista de tareas';

  @override
  String get paperStaff => 'Pentagrama';

  @override
  String get paperWeekly => 'Agenda semanal';

  @override
  String get paperMonthly => 'Calendario mensual';

  @override
  String get shortcutBold => 'Negrita';

  @override
  String get shortcutItalic => 'Cursiva';

  @override
  String get shortcutUnderline => 'Subrayado';

  @override
  String get shortcutStrike => 'Tachado';

  @override
  String get shortcutHighlight => 'Resaltado (poner / sacar)';

  @override
  String get shortcutFontUp => 'Agrandar letra';

  @override
  String get shortcutFontDown => 'Achicar letra';

  @override
  String get shortcutBullets => 'Viñetas';

  @override
  String get shortcutNumbered => 'Lista numerada';

  @override
  String get shortcutTodo => 'Lista de tareas';

  @override
  String get shortcutAlignLeft => 'Alinear a la izquierda';

  @override
  String get shortcutCenter => 'Centrar';

  @override
  String get shortcutAlignRight => 'Alinear a la derecha';

  @override
  String get shortcutJustify => 'Justificar';

  @override
  String get shortcutIndent => 'Más sangría';

  @override
  String get shortcutOutdent => 'Menos sangría';

  @override
  String get shortcutUndo => 'Deshacer';

  @override
  String get shortcutRedo => 'Rehacer';

  @override
  String get shortcutPencil => 'Lápiz';

  @override
  String get shortcutHighlighter => 'Resaltador';

  @override
  String get shortcutText => 'Texto (abre un bloque)';

  @override
  String get shortcutSelect => 'Seleccionar';

  @override
  String get shortcutZoom => 'Zoom';

  @override
  String get shortcutHelp => 'Ver estos atajos';

  @override
  String get shortcutZoomKeys => 'Ctrl + rueda del mouse';

  @override
  String get shortcutsTitle => 'Atajos de teclado';

  @override
  String get shortcutsTyping => 'Escribiendo';

  @override
  String get shortcutsSheet => 'En la hoja';

  @override
  String get newNotebookHint => 'Ej: Análisis II';

  @override
  String get newNotebookTitle => 'Nuevo cuaderno';

  @override
  String get newNotebookSheets => 'Hojas';

  @override
  String get newNotebookCanvas => 'Lienzo infinito';

  @override
  String get newNotebookCanvasHint =>
      'Sin cortes, crece mientras escribís. Para mapas conceptuales y diagramas';

  @override
  String deleteNotebookTitle(String name) {
    return 'Borrar \"$name\"';
  }

  @override
  String deleteNotebookBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hojas',
      one: '1 hoja',
    );
    return 'Se borran sus $_temp0. No se puede deshacer.';
  }

  @override
  String get pinHint => 'PIN';

  @override
  String get updateAvailableTitle => 'Hay una versión nueva de Vynote';

  @override
  String updateNewVersion(String version) {
    return 'Versión nueva: $version';
  }

  @override
  String updateVersions(String installed, String version) {
    return 'Tenés la $installed  →  nueva $version';
  }

  @override
  String get updateNotesTitle => 'Novedades';

  @override
  String get updateNotesDefault => 'Mejoras y arreglos varios.';

  @override
  String get updateSourceInfo =>
      'Se baja de la página oficial del proyecto en GitHub. Tus cuadernos no se tocan: solo se actualiza la app.';

  @override
  String get updateSkip => 'Omitir esta versión';

  @override
  String get updateInstall => 'Actualizar';

  @override
  String get updateDownloading => 'Bajando la versión nueva';

  @override
  String get updateConnecting => 'Conectando…';

  @override
  String get updateDownloadFailed =>
      'No pudimos bajar la actualización. Probá de nuevo en un rato.';

  @override
  String get updateStepTitle => 'Un paso más';

  @override
  String get updatePermissionBody =>
      'Android pide que le des permiso a Vynote para instalar su propia actualización. Es una sola vez. Te llevamos a los ajustes: activá \"Permitir de esta fuente\", volvé y tocá Actualizar de nuevo.';

  @override
  String get updateGoToSettings => 'Ir a ajustes';

  @override
  String get updateDoneTitle => 'Vynote se actualizó';

  @override
  String updateDoneBody(String version) {
    return 'Ya quedó instalada la $version. Reiniciá la app para usarla.';
  }

  @override
  String get updateRestartNow => 'Reiniciar ahora';

  @override
  String get updateCancelled => 'Actualización cancelada.';

  @override
  String get updateManualTitle => 'Instalala a mano';

  @override
  String get updateManualBody =>
      'No encontramos cómo pedir permisos de administrador. Abrí una terminal y corré:';

  @override
  String get updateCommandCopied => 'Comando copiado';

  @override
  String get commonCopy => 'Copiar';

  @override
  String get updateInstallerFailed =>
      'No pudimos abrir el instalador. Probá de nuevo en un rato.';

  @override
  String get updateInstallFailed =>
      'No se pudo instalar la actualización. Probá de nuevo en un rato.';

  @override
  String exportPdfSaved(String name) {
    return 'PDF de \"$name\" guardado';
  }

  @override
  String get exportPdfGenerating => 'Generando PDF';

  @override
  String exportSheetProgress(int done, int total) {
    return 'Hoja $done de $total';
  }

  @override
  String exportPdfFailed(String error) {
    return 'No se pudo generar el PDF: $error';
  }

  @override
  String get exportImagesGenerating => 'Generando imágenes';

  @override
  String exportImagesFailed(String error) {
    return 'No se pudieron generar las imágenes: $error';
  }

  @override
  String get exportImagesSaved => 'Imágenes guardadas';

  @override
  String get exportImageSaved => 'Imagen guardada';

  @override
  String get exportFolderTitle => 'Exportando carpeta';

  @override
  String exportFolderProgress(int done, int total) {
    return 'Cuaderno $done de $total';
  }

  @override
  String get exportFolderDone => 'Carpeta exportada';

  @override
  String exportFolderFailed(String error) {
    return 'No se pudo exportar la carpeta: $error';
  }

  @override
  String get errImportNotReadable =>
      'El archivo no es un cuaderno de Vynote (no se puede leer).';

  @override
  String get errImportNotVynote => 'El archivo no es un cuaderno de Vynote.';

  @override
  String get errImportNewerVersion =>
      'El archivo es de una versión más nueva de Vynote. Actualizá la app para abrirlo.';

  @override
  String get errImportBrokenSheetList => 'La lista de hojas está rota.';

  @override
  String get errImportNoSheets => 'El cuaderno no tiene hojas.';

  @override
  String get errImportBrokenSheetAny => 'Una hoja del archivo está rota.';

  @override
  String get errImportInvalidNames => 'El archivo tiene nombres no válidos.';

  @override
  String get errImportNotZip => 'El archivo no es un .zip.';

  @override
  String get errImportNoNotebooks =>
      'El .zip no tiene cuadernos de Vynote. ¿Lo exportaste en PDF o PNG?';

  @override
  String errImportMissingFile(String name) {
    return 'Al archivo le falta $name: está roto o no es de Vynote.';
  }

  @override
  String errImportBrokenFile(String name) {
    return '$name está roto.';
  }

  @override
  String errImportBrokenSheet(String name) {
    return 'La hoja $name está rota.';
  }

  @override
  String get libraryTitle => 'Cuadernos';

  @override
  String get libraryHome => 'Inicio';

  @override
  String get libraryNew => 'Nuevo';

  @override
  String get libraryNewNotebook => 'Cuaderno nuevo';

  @override
  String get libraryNewFolder => 'Carpeta nueva';

  @override
  String get libraryImportNotebook => 'Importar cuaderno .vynote';

  @override
  String get libraryImportFolder => 'Importar carpeta (.zip)';

  @override
  String get libraryMenuTooltip => 'Más opciones';

  @override
  String get libraryUpTooltip => 'Subir una carpeta';

  @override
  String get librarySearchHint => 'Buscar cuadernos y carpetas';

  @override
  String get librarySearchClear => 'Borrar búsqueda';

  @override
  String get libraryEmptyNoResults => 'Sin resultados';

  @override
  String get libraryEmptyNone => 'Todavía no hay cuadernos';

  @override
  String get libraryEmptyFolder => 'Esta carpeta está vacía';

  @override
  String libraryNotebookCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cuadernos',
      one: '$count cuaderno',
    );
    return '$_temp0';
  }

  @override
  String libraryFolderCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count carpetas',
      one: '$count carpeta',
    );
    return '$_temp0';
  }

  @override
  String get libraryHeaderFirst => 'Creá el primero para empezar';

  @override
  String libraryHeaderHint(String parts) {
    return '$parts · mantené uno apretado para opciones o arrastralo a una carpeta';
  }

  @override
  String get libraryResultsEverywhere => 'Resultados en todas las carpetas';

  @override
  String get libraryNotebookDeleted => 'Cuaderno borrado';

  @override
  String get libraryNotebookGone => 'El cuaderno ya no existe';

  @override
  String get libraryLockedNotebook => 'Este cuaderno está bloqueado';

  @override
  String get libraryWrongPin => 'PIN incorrecto';

  @override
  String libraryImportedAs(String name) {
    return 'Importado como \"$name\"';
  }

  @override
  String libraryImportFailed(String error) {
    return 'No se pudo importar: $error';
  }

  @override
  String get libraryImportingFolder => 'Importando carpeta';

  @override
  String get libraryImportCancelled => 'Importación cancelada';

  @override
  String libraryImportUnreadable(int count) {
    return ' ($count no se pudieron leer)';
  }

  @override
  String libraryImportedMany(int count, String fail) {
    return 'Importados $count cuadernos$fail';
  }

  @override
  String libraryImportedFolder(String name, int count, String fail) {
    return 'Carpeta \"$name\" importada: $count cuadernos$fail';
  }

  @override
  String libraryExportDone(String name) {
    return 'Cuaderno \"$name\" guardado';
  }

  @override
  String libraryExportFailed(String error) {
    return 'No se pudo exportar: $error';
  }

  @override
  String get libraryFolderHint => 'Ej: Facultad';

  @override
  String get libraryRenameNotebook => 'Renombrar cuaderno';

  @override
  String get libraryRenameFolder => 'Renombrar carpeta';

  @override
  String libraryCopySuffix(String name) {
    return '$name (copia)';
  }

  @override
  String get libraryDuplicated => 'Cuaderno duplicado';

  @override
  String get libraryFolderEmptyExport => 'La carpeta está vacía';

  @override
  String libraryMoveTitle(String name) {
    return 'Mover \"$name\" a…';
  }

  @override
  String libraryMovedTo(String path) {
    return 'Movido a $path';
  }

  @override
  String libraryMovedFolderTo(String path) {
    return 'Movida a $path';
  }

  @override
  String get libraryUndo => 'Deshacer';

  @override
  String get libraryFolderEmptyBody => 'La carpeta está vacía.';

  @override
  String get libraryDeleteAllTitle => 'Borrar todo';

  @override
  String libraryDeleteAllBody(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cuadernos',
      one: '1 cuaderno',
    );
    return 'Se borran la carpeta \"$name\", sus subcarpetas y $_temp0 con todas sus hojas. No se puede deshacer.';
  }

  @override
  String get libraryFolderWhatToDo => '¿Qué hacemos con lo que tiene adentro?';

  @override
  String libraryFolderKeep(String parent) {
    return 'Sacar los cuadernos a $parent';
  }

  @override
  String get libraryOptRename => 'Renombrar';

  @override
  String get libraryOptMove => 'Mover a…';

  @override
  String get libraryOptExport => 'Exportar';

  @override
  String get libraryOptDelete => 'Borrar';

  @override
  String get libraryOptOpen => 'Abrir';

  @override
  String get libraryOptDuplicate => 'Duplicar';

  @override
  String librarySheetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hojas',
      one: '$count hoja',
    );
    return '$_temp0';
  }

  @override
  String get moveHere => 'acá';

  @override
  String get syncIndicatorSynced => 'Sincronizado';

  @override
  String get syncIndicatorSyncing => 'Sincronizando';

  @override
  String get syncIndicatorPending => 'Cambios por subir';

  @override
  String get syncIndicatorOffline => 'Sin conexión';

  @override
  String get syncIndicatorError => 'Error de sincronización';

  @override
  String dateToday(String time) {
    return 'hoy $time';
  }

  @override
  String dateYesterday(String time) {
    return 'ayer $time';
  }

  @override
  String get datePatternTime => 'HH:mm';

  @override
  String get datePatternDayMonth => 'dd/MM';

  @override
  String get datePatternDayMonthYear => 'dd/MM/yyyy';

  @override
  String get syncErrOffline => 'Sin conexión';

  @override
  String get syncErrAuthExpired =>
      'La sesión de Google venció. Volvé a conectar.';

  @override
  String get syncErrConflict =>
      'El archivo cambió en la nube mientras se subía; se reintenta';

  @override
  String get syncErrNotFound => 'No existe en la nube';

  @override
  String get syncErrVaultChanged =>
      'Cambió la configuración de cifrado de la nube';

  @override
  String get syncErrCryptoLocked =>
      'La nube está cifrada: ingresá la frase en Sincronización > Cifrado';

  @override
  String get syncErrWrongPassphrase => 'La frase de cifrado es incorrecta';

  @override
  String get syncErrCryptoOtherDevice =>
      'Otro dispositivo activó el cifrado al mismo tiempo. Ingresá su frase.';

  @override
  String get syncErrCloudNotEncrypted => 'La nube no está cifrada';

  @override
  String get syncErrConnectFirst => 'Conectá con Google primero';

  @override
  String get syncErrBackgroundBusy =>
      'Hay una sincronización en segundo plano en curso; probá de nuevo en unos segundos';

  @override
  String syncErrFilesFailed(String count) {
    return '$count archivo(s) no se pudieron sincronizar; se reintenta en la próxima pasada';
  }

  @override
  String syncErrCouldNotSync(String detail) {
    return 'No se pudo sincronizar: $detail';
  }

  @override
  String get syncAgoNow => 'hace un momento';

  @override
  String syncAgoMinutes(int count) {
    return 'hace $count min';
  }

  @override
  String syncAgoHours(int count) {
    return 'hace $count h';
  }

  @override
  String syncAgoDays(int count) {
    return 'hace $count d';
  }

  @override
  String syncNotConfigured(String missing) {
    return 'Esta versión no tiene configurado el acceso a Google (falta: $missing). Las notas siguen guardándose en este dispositivo.';
  }

  @override
  String get syncDisconnectedStatus =>
      'Sin conectar. Los cuadernos se guardan solo en este dispositivo.';

  @override
  String get syncConnecting => 'Conectando con Google…';

  @override
  String get syncSyncing => 'Sincronizando…';

  @override
  String syncConnectedAs(String account, String last) {
    return 'Conectado como $account\n$last';
  }

  @override
  String get syncNever => 'Todavía no se sincronizó';

  @override
  String syncLast(String ago) {
    return 'Última sincronización: $ago';
  }

  @override
  String get syncTitle => 'Sincronización con Google Drive';

  @override
  String syncConflicts(int count) {
    return 'Hubo $count conflicto(s): buscá las hojas \"(conflicto)\" y quedate con la que sirva.';
  }

  @override
  String get syncBackgroundTitle => 'Sincronizar en segundo plano';

  @override
  String get syncBackgroundSubtitle =>
      'Cada 15 minutos con red, aunque la app esté cerrada.';

  @override
  String get syncConnect => 'Conectar con Google';

  @override
  String get syncNow => 'Sincronizar ahora';

  @override
  String get syncDisconnect => 'Desconectar';

  @override
  String get cryptoStatusUnknown =>
      'Todavía no se sabe: se ve en la próxima sincronización.';

  @override
  String get cryptoStatusOff =>
      'Desactivado: Google puede leer lo que se sube a tu Drive.';

  @override
  String get cryptoStatusOn =>
      'Activado: en Drive solo hay archivos cifrados con tu frase.';

  @override
  String get cryptoStatusLocked =>
      'La nube está cifrada. Ingresá la frase para poder sincronizar.';

  @override
  String get cryptoTitle => 'Cifrado';

  @override
  String get cryptoWarning =>
      'Si olvidás la frase no hay forma de recuperar lo que está en la nube (lo de este dispositivo no se pierde). Los nombres de archivo en Drive son códigos al azar y siguen a la vista.';

  @override
  String get cryptoEnable => 'Activar cifrado';

  @override
  String get cryptoEnterPass => 'Ingresar frase';

  @override
  String get cryptoDisableTitle => '¿Desactivar el cifrado?';

  @override
  String get cryptoDisableBody =>
      'Se vuelve a subir todo sin cifrar y se borra lo cifrado de Drive. Puede tardar si hay muchos archivos.';

  @override
  String get cryptoDisableConfirm => 'Desactivar';

  @override
  String get cryptoDisable => 'Desactivar cifrado';

  @override
  String get cryptoPassTitle => 'Frase de cifrado';

  @override
  String get cryptoPassIntro =>
      'Elegí una frase y anotala en un lugar seguro. Si la olvidás no hay forma de recuperar lo que está en la nube (lo de este dispositivo no se pierde). Se va a subir todo cifrado y borrar lo anterior de Drive.';

  @override
  String get cryptoPassLabel => 'Frase';

  @override
  String get cryptoPassRepeat => 'Repetí la frase';

  @override
  String get cryptoPassMismatch => 'Las dos frases no coinciden.';

  @override
  String get cryptoActivate => 'Activar';

  @override
  String get cryptoUnlock => 'Desbloquear';

  @override
  String cryptoPassShort(int min) {
    return 'La frase tiene que tener al menos $min caracteres.';
  }

  @override
  String get cryptoStepDeriving =>
      'Derivando la clave (puede tardar unos segundos)…';

  @override
  String get cryptoStepSyncBeforeEncrypt => 'Sincronizando antes de cifrar…';

  @override
  String get cryptoStepSyncBeforeDecrypt => 'Sincronizando antes de descifrar…';

  @override
  String cryptoStepEncrypting(int done, int total) {
    return 'Cifrando $done/$total…';
  }

  @override
  String cryptoStepDecrypting(int done, int total) {
    return 'Descifrando $done/$total…';
  }

  @override
  String get commonRename => 'Renombrar';

  @override
  String get commonExport => 'Exportar';

  @override
  String get commonSave => 'Guardar';

  @override
  String get commonUpdate => 'Actualizar';

  @override
  String get commonSearch => 'Buscar';

  @override
  String sheetLabel(int n) {
    return 'Hoja $n';
  }

  @override
  String sheetLabelTitled(int n, String title) {
    return 'Hoja $n · $title';
  }

  @override
  String sheetCountPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hojas',
      one: '$count hoja',
    );
    return '$_temp0';
  }

  @override
  String get menuInsertPdf => 'PDF';

  @override
  String get menuInsertVoice => 'Grabación de voz';

  @override
  String get menuInsertImage => 'Imagen';

  @override
  String get menuInsertCamera => 'Cámara';

  @override
  String get menuInsertAudio => 'Archivo de audio';

  @override
  String get menuInsertSticky => 'Nota adhesiva';

  @override
  String get menuInsertSheet => 'Hoja nueva';

  @override
  String get menuMoreReadingExit => 'Salir del modo lectura';

  @override
  String get menuMoreReading => 'Modo lectura';

  @override
  String get menuMoreBookmarkRemove => 'Quitar marcador';

  @override
  String get menuMoreBookmarkAdd => 'Marcar esta hoja';

  @override
  String get menuMoreFullscreen => 'Pantalla completa';

  @override
  String get menuMoreStyle => 'Estilo de hoja';

  @override
  String get menuMorePaperColor => 'Color del papel';

  @override
  String get menuMoreShortcuts => 'Atajos de teclado';

  @override
  String get menuMoreFavoriteRemove => 'Quitar de favoritos';

  @override
  String get menuMoreFavoriteAdd => 'Favorito';

  @override
  String get menuMoreLockRemove => 'Quitar bloqueo';

  @override
  String get menuMoreLockAdd => 'Bloquear con PIN';

  @override
  String get menuMoreShare => 'Compartir';

  @override
  String get menuMorePrint => 'Imprimir';

  @override
  String get menuMoreDeleteNotebook => 'Borrar cuaderno';

  @override
  String get menuExportFolderTitle => 'Exportar carpeta';

  @override
  String get menuExportFolderPdf => 'Un PDF por cuaderno';

  @override
  String get menuExportFolderPng =>
      'Una carpeta por cuaderno con una imagen por hoja';

  @override
  String get menuExportFolderVynote =>
      'Un .vynote por cuaderno, para pasarlo a otro dispositivo';

  @override
  String get menuExportFormatPdf => 'PDF';

  @override
  String get menuExportFormatPng => 'Imágenes (PNG)';

  @override
  String get menuExportFormatVynote => 'Vynote';

  @override
  String get menuExportBackground => 'Incluir el fondo de la hoja';

  @override
  String get menuExportBackgroundOff =>
      'Apagado: solo lo escrito, sobre blanco';

  @override
  String get menuExportAllPdf => 'Todo el cuaderno';

  @override
  String get menuExportAllPng => 'Todas las hojas, en un .zip';

  @override
  String get menuExportVynoteTitle => 'Cuaderno de Vynote (.vynote)';

  @override
  String get menuExportVynoteHint =>
      'Para pasarlo a otro dispositivo o hacer copia';

  @override
  String get menuExportSheetPdf => 'PDF de esta hoja';

  @override
  String get menuExportSheetPng => 'Imagen de esta hoja (PNG)';

  @override
  String get sectionNew => 'Nueva sección';

  @override
  String get sectionOptions => 'Opciones de la sección';

  @override
  String get sectionUp => 'Subir';

  @override
  String get sectionDown => 'Bajar';

  @override
  String get sectionExportTitle => '¿Qué secciones exportar?';

  @override
  String get sectionAll => 'Todas';

  @override
  String get indexTitle => 'Índice';

  @override
  String get indexEmpty =>
      'Todavía no hay títulos.\nUsá la herramienta Título de la barra para marcar lo que escribiste.';

  @override
  String indexLevelUp(int level) {
    return 'Pasar a Título $level';
  }

  @override
  String indexLevelDown(int level) {
    return 'Pasar a Título $level';
  }

  @override
  String get indexRemove => 'Quitar del índice';

  @override
  String get indexRenameTitle => 'Renombrar título';

  @override
  String get searchHint =>
      'Buscá en los textos, notas adhesivas y títulos de hojas';

  @override
  String searchNone(String query) {
    return 'Sin resultados para \"$query\"';
  }

  @override
  String searchTitleSnippet(String title) {
    return 'Título: $title';
  }

  @override
  String get paperColorIvory => 'Marfil';

  @override
  String get paperColorWhite => 'Blanco';

  @override
  String get paperColorCream => 'Crema';

  @override
  String get paperColorGray => 'Gris';

  @override
  String get paperColorLightBlue => 'Celeste';

  @override
  String get paperColorGreen => 'Verde';

  @override
  String styleDeleteTemplate(String name) {
    return '¿Borrar la plantilla «$name»?';
  }

  @override
  String get styleSize => 'Tamaño';

  @override
  String get styleBackground => 'Fondo';

  @override
  String get styleTemplates => 'Plantillas';

  @override
  String get styleMyTemplates => 'Mis plantillas';

  @override
  String get styleFromImage => 'Desde una imagen…';

  @override
  String get styleSpacingLined => 'Interlineado';

  @override
  String get styleSpacingGrid => 'Cuadrícula';

  @override
  String get styleApplyTo => 'Aplicar a';

  @override
  String get styleThisSheet => 'Esta hoja';

  @override
  String get styleWholeNotebook => 'Todo el cuaderno';

  @override
  String get styleTitleNew => 'Hoja nueva';

  @override
  String get styleTitle => 'Estilo de hoja';

  @override
  String get styleApply => 'Aplicar';

  @override
  String get pagesAll => 'Ver todas';

  @override
  String get pagesOnlyBookmarked => 'Solo marcadas';

  @override
  String get pagesNewAfter => 'Hoja nueva después de la actual';

  @override
  String get pagesNoBookmarks => 'No hay hojas marcadas';

  @override
  String get pagesNoBookmarksHint =>
      'No hay hojas marcadas. Usá el marcador de arriba para marcar la hoja que estás viendo.';

  @override
  String get pagesBookmark => 'Marcar';

  @override
  String get pagesDragToMove => 'Arrastrar para mover';

  @override
  String get pagesNewAfterMenu => 'Hoja nueva después';

  @override
  String get pagesNewWithTemplate => 'Hoja nueva con plantilla…';

  @override
  String get pagesDuplicate => 'Duplicar';

  @override
  String get pagesSaveTemplate => 'Guardar como plantilla';

  @override
  String get pagesMoveBefore => 'Mover antes';

  @override
  String get pagesMoveAfter => 'Mover después';

  @override
  String notebookTemplateDefault(int n) {
    return 'Plantilla $n';
  }

  @override
  String notebookTemplateFailed(String error) {
    return 'No se pudo guardar la plantilla: $error';
  }

  @override
  String get notebookTemplateSaved => 'Plantilla guardada';

  @override
  String get notebookTemplateName => 'Nombre';

  @override
  String notebookSheetNameTitle(int n) {
    return 'Nombre de la hoja $n';
  }

  @override
  String get notebookOptional => 'Opcional';

  @override
  String get notebookLastSheet =>
      'No se puede borrar la única hoja del cuaderno';

  @override
  String notebookDeleteSheetTitle(int n) {
    return 'Borrar la hoja $n';
  }

  @override
  String get notebookDeleteSheetBody =>
      'Se borra la hoja con todo lo que tiene (se puede deshacer).';

  @override
  String notebookSheetReadFailed(String error) {
    return 'No se pudo leer la hoja: $error';
  }

  @override
  String get notebookBookmarkTitle => 'Marcador';

  @override
  String get notebookBookmarkHint => 'Nombre (opcional)';

  @override
  String get notebookBookmarkNoName => 'Sin nombre';

  @override
  String notebookSectionOpenFailed(String error) {
    return 'No se pudo abrir la sección: $error';
  }

  @override
  String notebookSectionDefault(int n) {
    return 'Sección $n';
  }

  @override
  String get notebookSectionHint => 'Ej: Práctica';

  @override
  String get notebookSectionRename => 'Renombrar sección';

  @override
  String get notebookLastSection =>
      'No se puede borrar la única sección del cuaderno';

  @override
  String notebookDeleteSectionTitle(String name) {
    return 'Borrar la sección \"$name\"';
  }

  @override
  String notebookDeleteSectionBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: 'borran $count hojas con todo lo que tienen',
      one: 'borra 1 hoja con todo lo que tiene',
    );
    return 'Se $_temp0. No se puede deshacer.';
  }

  @override
  String notebookInsertFailed(String error) {
    return 'No se pudo insertar: $error';
  }

  @override
  String get notebookRecordingBusy => 'Ya hay una grabación en curso';

  @override
  String get notebookImportingPdf => 'Importando PDF';

  @override
  String get notebookPickFile => 'Elegí el archivo…';

  @override
  String notebookSheetsImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count hojas importadas',
      one: '$count hoja importada',
    );
    return '$_temp0';
  }

  @override
  String get notebookFavoriteAdded => 'Agregado a favoritos';

  @override
  String get notebookFavoriteRemoved => 'Quitado de favoritos';

  @override
  String get notebookUnlockTitle => 'Quitar bloqueo';

  @override
  String get notebookUnlockHint => 'Ingresá el PIN actual';

  @override
  String get notebookUnlocked => 'Cuaderno desbloqueado';

  @override
  String get notebookLockTitle => 'Bloquear cuaderno';

  @override
  String get notebookLockHint => 'Elegí un PIN de 4 o más números';

  @override
  String get notebookPinShort => 'El PIN tiene que tener al menos 4 números';

  @override
  String get notebookPinRepeat => 'Repetí el PIN';

  @override
  String get notebookPinMismatch => 'Los PIN no coinciden';

  @override
  String get notebookLocked => 'Cuaderno bloqueado: se pide el PIN al abrirlo';

  @override
  String get notebookSaved => 'Cuaderno guardado';

  @override
  String notebookExportFailed(String error) {
    return 'No se pudo exportar: $error';
  }

  @override
  String notebookSheetFileName(String name, int n) {
    return '$name - hoja $n';
  }

  @override
  String get notebookImageSaved => 'Imagen guardada';

  @override
  String get notebookFullscreenExit => 'Salir de pantalla completa';

  @override
  String get notebookRecording => 'Grabando';

  @override
  String notebookRecordingNamed(String name) {
    return 'Grabando · $name';
  }

  @override
  String get notebookRecordingStop => 'Parar y guardar';

  @override
  String get notebookRecordingCancel => 'Cancelar y descartar';

  @override
  String get notebookLinkFailed => 'No se pudo abrir el link';

  @override
  String get notebookSheetGone => 'La hoja ya no existe';

  @override
  String get notebookBack => 'Volver a los cuadernos';

  @override
  String get notebookSearchClose => 'Cerrar búsqueda';

  @override
  String get notebookInsert => 'Insertar';

  @override
  String get notebookIndexTooltip => 'Índice';

  @override
  String get notebookSections => 'Secciones';

  @override
  String get notebookPages => 'Hojas';

  @override
  String get notebookMore => 'Más opciones';

  @override
  String get notebookRemoteChanges => 'Hay cambios de otro dispositivo';

  @override
  String notebookSearchIn(String name) {
    return 'Buscar en \"$name\"';
  }

  @override
  String notebookSheetCounter(String title, int n, int total) {
    return '$title$n / $total';
  }

  @override
  String get audioPrefix => 'Audio';

  @override
  String get errVoiceBusy => 'Ya hay una grabación en curso';

  @override
  String get errVoiceNoPermission => 'Sin permiso para usar el micrófono';

  @override
  String errVoiceFailed(String detail) {
    return 'No se pudo grabar: $detail';
  }

  @override
  String get headingTitle => 'Agregar al índice';

  @override
  String get headingFailed => 'No se pudo leer: escribí el nombre';

  @override
  String get headingHint => 'Nombre';

  @override
  String get headingDownloading =>
      'Bajando el reconocimiento de letra, solo la primera vez (podés escribir el nombre mientras tanto)…';

  @override
  String get headingReading =>
      'Leyendo la letra… (podés escribir el nombre mientras tanto)';

  @override
  String get headingMoreImportant => 'Más importante';

  @override
  String get headingLessImportant => 'Menos importante';

  @override
  String headingLevel(int level) {
    return 'Título $level';
  }

  @override
  String get headingAdd => 'Agregar';

  @override
  String get formatBold => 'Negrita (Ctrl+B)';

  @override
  String get formatItalic => 'Cursiva (Ctrl+I)';

  @override
  String get formatUnderline => 'Subrayado (Ctrl+U)';

  @override
  String get formatStrike => 'Tachado (Alt+Shift+5)';

  @override
  String get formatColor => 'Color del texto';

  @override
  String get formatHighlight => 'Resaltado (Ctrl+Shift+H)';

  @override
  String get formatNormal => 'Normal';

  @override
  String get formatTitle => 'Título';

  @override
  String get formatSubtitle => 'Subtítulo';

  @override
  String get formatBullets => 'Viñetas (Ctrl+Shift+8)';

  @override
  String get formatNumbered => 'Numerada (Ctrl+Shift+7)';

  @override
  String get formatTodo => 'Lista de tareas (Ctrl+Shift+9)';

  @override
  String get formatOutdent => 'Menos sangría (Shift+Tab)';

  @override
  String get formatIndent => 'Más sangría (Tab)';

  @override
  String get formatAlignLeft => 'Alinear a la izquierda (Ctrl+L)';

  @override
  String get formatCenter => 'Centrar (Ctrl+E)';

  @override
  String get formatAlignRight => 'Alinear a la derecha (Ctrl+R)';

  @override
  String get formatJustify => 'Justificar (Ctrl+J)';

  @override
  String get formatSizeDown => 'Achicar letra (Ctrl+[)';

  @override
  String get formatSizeUp => 'Agrandar letra (Ctrl+])';

  @override
  String get formatSizeAuto => 'Automático';

  @override
  String get formatCopy => 'Copiar';

  @override
  String get formatCut => 'Cortar';

  @override
  String get pullDone => 'Hoja agregada';

  @override
  String get pullHold => 'Mantené para agregar una hoja';

  @override
  String get toolPen => 'Lápiz · tocá de nuevo para opciones';

  @override
  String get toolHighlighter => 'Resaltador · tocá de nuevo para opciones';

  @override
  String get toolPaint => 'Decorador · tocá de nuevo para opciones';

  @override
  String get toolShapes => 'Formas · tocá de nuevo para opciones';

  @override
  String get toolText => 'Texto con teclado';

  @override
  String get toolSelect => 'Seleccionar';

  @override
  String get toolTitle => 'Título para el índice';

  @override
  String get toolUndo => 'Deshacer';

  @override
  String get toolRedo => 'Rehacer';

  @override
  String toolZoomLocked(int percent) {
    return 'Zoom fijo ($percent%) · tocá para soltarlo';
  }

  @override
  String get toolZoomLock => 'Fijar el zoom';

  @override
  String get toolMoreColors => 'Más colores';

  @override
  String get toolPenOptions => 'Punta, grosor y opacidad';

  @override
  String get toolDragBar => 'Arrastrá para mover la barra';

  @override
  String zoomIndicator(int percent) {
    return '$percent%';
  }

  @override
  String zoomIndicatorLocked(int percent) {
    return '$percent% · fijo';
  }

  @override
  String get selOrder => 'Orden';

  @override
  String get selFront => 'Traer al frente';

  @override
  String get selUp => 'Subir uno';

  @override
  String get selDown => 'Bajar uno';

  @override
  String get selBack => 'Enviar al fondo';

  @override
  String get selDuplicate => 'Duplicar';

  @override
  String get selLink => 'Link';

  @override
  String get selEditLink => 'Editar link';

  @override
  String get selRemoveLink => 'Quitar link';

  @override
  String get selStraighten => 'Enderezar';

  @override
  String get selDelete => 'Eliminar';

  @override
  String get selDeselect => 'Deseleccionar';

  @override
  String get sheetMenuPaste => 'Pegar acá';

  @override
  String get linkTitle => 'Link';

  @override
  String get linkTitleEdit => 'Editar link';

  @override
  String get linkKindWeb => 'Página web';

  @override
  String get linkKindSheet => 'Hoja';

  @override
  String get linkKindNotebook => 'Cuaderno';

  @override
  String get linkUrlHint => 'dirección, ej. es.wikipedia.org';

  @override
  String get linkNoSheets => 'No hay hojas.';

  @override
  String get linkNoNotebooks => 'No hay otros cuadernos.';

  @override
  String get stickyHint => 'Nota…';

  @override
  String get editorLinkMissingPage => 'Esa página no está en el cuaderno';

  @override
  String get editorRenameAudio => 'Renombrar audio';

  @override
  String get editorPullHint =>
      'Al final, deslizá hacia arriba y mantené para agregar una hoja';

  @override
  String editorScrollerLabel(int n, int total) {
    return 'Hoja $n de $total';
  }

  @override
  String get editorCopied => 'Copiado';

  @override
  String editorLoadingSheet(int n) {
    return 'Cargando la hoja $n…';
  }

  @override
  String get tipPen => 'Bolígrafo';

  @override
  String get tipFountain => 'Pluma';

  @override
  String get tipPencil => 'Lápiz';

  @override
  String get tipFine => 'Fibra';

  @override
  String get tipCalligraphy => 'Caligrafía';

  @override
  String get paintStyleBrush => 'Pincel';

  @override
  String get paintStyleHighlighter => 'Resaltador';

  @override
  String get paintStyleMarker => 'Fibra';

  @override
  String get paintShapeStars => 'Estrellas';

  @override
  String get paintShapeHearts => 'Corazones';

  @override
  String get paintShapeSparkles => 'Destellos';

  @override
  String get paintShapeMoons => 'Lunas';

  @override
  String get paintShapeDots => 'Puntos';

  @override
  String get paintShapeCircles => 'Círculos';

  @override
  String get paintShapeExclamations => 'Exclamaciones';

  @override
  String get paintShapeBolts => 'Rayos';

  @override
  String get paintShapeTicks => 'Ticks';

  @override
  String get paintShapeCrosses => 'Cruces';

  @override
  String get paintShapeClouds => 'Nubes';

  @override
  String get paintShapeBubbles => 'Globos';

  @override
  String get paintShapeLeaves => 'Hojas';

  @override
  String get paintShapePaws => 'Huellas';

  @override
  String get paintShapeTriangles => 'Triángulos';

  @override
  String get paintShapeSquares => 'Cuadrados';

  @override
  String get paintShapeDiamonds => 'Rombos';

  @override
  String get paintShapeFlowers => 'Flores';

  @override
  String get paintShapeNotes => 'Notas';

  @override
  String get shapeKindLine => 'Recta';

  @override
  String get shapeKindArrow => 'Flecha';

  @override
  String get shapeKindRectangle => 'Rectángulo';

  @override
  String get shapeKindCircle => 'Círculo';

  @override
  String get shapeKindEllipse => 'Elipse';

  @override
  String get shapeKindTriangle => 'Triángulo';

  @override
  String get penFavorites => 'Favoritos';

  @override
  String get penFavEdit => 'Cambiar';

  @override
  String get penFavHelpEditing =>
      'Elegí un color de la paleta o del selector: se guarda en el favorito marcado.';

  @override
  String get penFavHelp =>
      'Tocá «Cambiar» o mantené apretado un favorito para elegir su color.';

  @override
  String get penPanelHighlighter => 'Resaltador';

  @override
  String get penPanelPencil => 'Lápiz';

  @override
  String get penTip => 'Punta';

  @override
  String get penWidth => 'Grosor';

  @override
  String get penOpacity => 'Opacidad';

  @override
  String get penSmartShapes => 'Figuras inteligentes';

  @override
  String get penSmartShapesHint =>
      'Mantené el lápiz quieto al terminar una forma';

  @override
  String get penColor => 'Color';

  @override
  String get penCustomColor => 'Color personalizado';

  @override
  String get penEraser => 'Goma (apretá el botón del lápiz)';

  @override
  String get penEraserSmall => 'Chica';

  @override
  String get penEraserMedium => 'Mediana';

  @override
  String get penEraserLarge => 'Grande';

  @override
  String get shapesTitle => 'Formas';

  @override
  String get shapesBorder => 'Borde';

  @override
  String get shapesBorderHint => 'El borde usa el color y el grosor del lápiz.';

  @override
  String get shapesFill => 'Relleno';

  @override
  String get shapesNoFill => 'La recta y la flecha no se rellenan.';

  @override
  String get shapesSnapGrid => 'Pegar a la cuadrícula';

  @override
  String get shapesSnapGridHint =>
      'En hojas cuadriculadas, milimetradas, de puntos o con ejes';

  @override
  String get paintPanelTitle => 'Decorador';

  @override
  String get paintStroke => 'Trazo';

  @override
  String get paintWidth => 'Ancho';

  @override
  String get paintBackground => 'Fondo';

  @override
  String get paintGlitter => 'Brillo';

  @override
  String get paintAmount => 'Cantidad';

  @override
  String get paintAuto => 'Auto';

  @override
  String get paintSize => 'Tamaño';

  @override
  String shapeMeasureTriangle(String base, String height) {
    return 'base $base · alto $height mm';
  }

  @override
  String get librarySampleNotebook => 'Mi cuaderno';

  @override
  String get exportFileNotebook => 'Cuaderno';

  @override
  String get exportFileFolder => 'Carpeta';

  @override
  String get exportFileSection => 'Sección';

  @override
  String get exportFilePage => 'página';

  @override
  String get exportFileSheet => 'hoja';

  @override
  String get exportSavePdf => 'Guardar PDF';

  @override
  String get exportSaveImage => 'Guardar imagen';

  @override
  String get exportSaveImages => 'Guardar imágenes';

  @override
  String get exportSaveNotebook => 'Guardar cuaderno';

  @override
  String get exportSaveFolder => 'Guardar carpeta';

  @override
  String get settingsTitle => 'Ajustes';

  @override
  String get settingsSectionLanguage => 'Idioma';

  @override
  String get settingsAppLanguage => 'Idioma de la app';

  @override
  String get settingsInkLanguage => 'Idioma de la escritura a mano';

  @override
  String get settingsLanguageSystem => 'Como el sistema';

  @override
  String get settingsInkSameAsApp => 'Igual que la app';

  @override
  String get settingsInkHelp =>
      'Se usa para leer los títulos que escribís a mano. Al cambiarlo se baja el modelo nuevo (unos 20 MB) y se borra el anterior.';

  @override
  String get settingsSectionUpdates => 'Actualizaciones';

  @override
  String get settingsCheckUpdates => 'Buscar actualizaciones';

  @override
  String get settingsAutoUpdates => 'Buscar actualizaciones automáticamente';

  @override
  String get settingsSectionAbout => 'Acerca de';

  @override
  String get settingsVersion => 'Versión';

  @override
  String get settingsSource => 'Código fuente';

  @override
  String get settingsLicense => 'Licencia';

  @override
  String get settingsLicenseValue => 'GPL v3 o posterior';

  @override
  String get settingsPrivacy => 'Política de privacidad';

  @override
  String get updateChecking => 'Buscando actualizaciones…';

  @override
  String get updateCheckFailed => 'No se pudo buscar actualizaciones ahora';

  @override
  String get updateUpToDate => 'Ya tenés la última versión';
}
