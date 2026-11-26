import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:intl/intl.dart' as intl;

import 'app_localizations_en.dart';
import 'app_localizations_es.dart';
import 'app_localizations_pt.dart';

// ignore_for_file: type=lint

/// Callers can lookup localized strings with an instance of L
/// returned by `L.of(context)`.
///
/// Applications need to include `L.delegate()` in their app's
/// `localizationDelegates` list, and the locales they support in the app's
/// `supportedLocales` list. For example:
///
/// ```dart
/// import 'l10n/app_localizations.dart';
///
/// return MaterialApp(
///   localizationsDelegates: L.localizationsDelegates,
///   supportedLocales: L.supportedLocales,
///   home: MyApplicationHome(),
/// );
/// ```
///
/// ## Update pubspec.yaml
///
/// Please make sure to update your pubspec.yaml to include the following
/// packages:
///
/// ```yaml
/// dependencies:
///   # Internationalization support.
///   flutter_localizations:
///     sdk: flutter
///   intl: any # Use the pinned version from flutter_localizations
///
///   # Rest of dependencies
/// ```
///
/// ## iOS Applications
///
/// iOS applications define key application metadata, including supported
/// locales, in an Info.plist file that is built into the application bundle.
/// To configure the locales supported by your app, you’ll need to edit this
/// file.
///
/// First, open your project’s ios/Runner.xcworkspace Xcode workspace file.
/// Then, in the Project Navigator, open the Info.plist file under the Runner
/// project’s Runner folder.
///
/// Next, select the Information Property List item, select Add Item from the
/// Editor menu, then select Localizations from the pop-up menu.
///
/// Select and expand the newly-created Localizations item then, for each
/// locale your application supports, add a new item and select the locale
/// you wish to add from the pop-up menu in the Value field. This list should
/// be consistent with the languages listed in the L.supportedLocales
/// property.
abstract class L {
  L(String locale)
    : localeName = intl.Intl.canonicalizedLocale(locale.toString());

  final String localeName;

  static L of(BuildContext context) {
    return Localizations.of<L>(context, L)!;
  }

  static const LocalizationsDelegate<L> delegate = _LDelegate();

  /// A list of this localizations delegate along with the default localizations
  /// delegates.
  ///
  /// Returns a list of localizations delegates containing this delegate along with
  /// GlobalMaterialLocalizations.delegate, GlobalCupertinoLocalizations.delegate,
  /// and GlobalWidgetsLocalizations.delegate.
  ///
  /// Additional delegates can be added by appending to this list in
  /// MaterialApp. This list does not have to be used at all if a custom list
  /// of delegates is preferred or required.
  static const List<LocalizationsDelegate<dynamic>> localizationsDelegates =
      <LocalizationsDelegate<dynamic>>[
        delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
      ];

  /// A list of this localizations delegate's supported locales.
  static const List<Locale> supportedLocales = <Locale>[
    Locale('en'),
    Locale('es'),
    Locale('pt'),
  ];

  /// Generic "Cancel" button in dialogs
  ///
  /// In es, this message translates to:
  /// **'Cancelar'**
  String get commonCancel;

  /// Generic "Done" button in dialogs
  ///
  /// In es, this message translates to:
  /// **'Listo'**
  String get commonDone;

  /// Generic "Create" button in dialogs
  ///
  /// In es, this message translates to:
  /// **'Crear'**
  String get commonCreate;

  /// Generic "Delete" button in dialogs
  ///
  /// In es, this message translates to:
  /// **'Borrar'**
  String get commonDelete;

  /// Generic "Close" button in dialogs
  ///
  /// In es, this message translates to:
  /// **'Cerrar'**
  String get commonClose;

  /// "Later" button in dialogs
  ///
  /// In es, this message translates to:
  /// **'Después'**
  String get commonLater;

  /// "Not now" button in dialogs
  ///
  /// In es, this message translates to:
  /// **'Ahora no'**
  String get commonNotNow;

  /// Lined paper name in the paper style dialog
  ///
  /// In es, this message translates to:
  /// **'Rayado'**
  String get paperLined;

  /// Grid paper name in the paper style dialog
  ///
  /// In es, this message translates to:
  /// **'Cuadriculado'**
  String get paperGrid;

  /// Dotted paper name in the paper style dialog
  ///
  /// In es, this message translates to:
  /// **'Puntos'**
  String get paperDots;

  /// Millimeter graph paper name in the paper style dialog
  ///
  /// In es, this message translates to:
  /// **'Milimetrado'**
  String get paperMm;

  /// Cartesian axes paper name in the paper style dialog
  ///
  /// In es, this message translates to:
  /// **'Ejes cartesianos'**
  String get paperAxes;

  /// Blank paper name in the paper style dialog
  ///
  /// In es, this message translates to:
  /// **'Liso'**
  String get paperBlank;

  /// Cornell note-taking template name in the paper style dialog
  ///
  /// In es, this message translates to:
  /// **'Cornell'**
  String get paperCornell;

  /// To-do list template name in the paper style dialog
  ///
  /// In es, this message translates to:
  /// **'Lista de tareas'**
  String get paperTodo;

  /// Music staff template name in the paper style dialog
  ///
  /// In es, this message translates to:
  /// **'Pentagrama'**
  String get paperStaff;

  /// Weekly planner template name in the paper style dialog
  ///
  /// In es, this message translates to:
  /// **'Agenda semanal'**
  String get paperWeekly;

  /// Monthly calendar template name in the paper style dialog
  ///
  /// In es, this message translates to:
  /// **'Calendario mensual'**
  String get paperMonthly;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Negrita'**
  String get shortcutBold;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Cursiva'**
  String get shortcutItalic;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Subrayado'**
  String get shortcutUnderline;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Tachado'**
  String get shortcutStrike;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Resaltado (poner / sacar)'**
  String get shortcutHighlight;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Agrandar letra'**
  String get shortcutFontUp;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Achicar letra'**
  String get shortcutFontDown;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Viñetas'**
  String get shortcutBullets;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Lista numerada'**
  String get shortcutNumbered;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Lista de tareas'**
  String get shortcutTodo;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Alinear a la izquierda'**
  String get shortcutAlignLeft;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Centrar'**
  String get shortcutCenter;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Alinear a la derecha'**
  String get shortcutAlignRight;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Justificar'**
  String get shortcutJustify;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Más sangría'**
  String get shortcutIndent;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Menos sangría'**
  String get shortcutOutdent;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Deshacer'**
  String get shortcutUndo;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Rehacer'**
  String get shortcutRedo;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Lápiz'**
  String get shortcutPencil;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Resaltador'**
  String get shortcutHighlighter;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Texto (abre un bloque)'**
  String get shortcutText;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Seleccionar'**
  String get shortcutSelect;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Zoom'**
  String get shortcutZoom;

  /// Keyboard shortcut description in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Ver estos atajos'**
  String get shortcutHelp;

  /// Keys to zoom the sheet in the shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Ctrl + rueda del mouse'**
  String get shortcutZoomKeys;

  /// Title of the keyboard shortcuts dialog
  ///
  /// In es, this message translates to:
  /// **'Atajos de teclado'**
  String get shortcutsTitle;

  /// Section title in the shortcuts dialog: shortcuts while typing in a text block
  ///
  /// In es, this message translates to:
  /// **'Escribiendo'**
  String get shortcutsTyping;

  /// Section title in the shortcuts dialog: shortcuts on the sheet
  ///
  /// In es, this message translates to:
  /// **'En la hoja'**
  String get shortcutsSheet;

  /// Example name hint in the new notebook dialog
  ///
  /// In es, this message translates to:
  /// **'Ej: Análisis II'**
  String get newNotebookHint;

  /// Title of the new notebook dialog
  ///
  /// In es, this message translates to:
  /// **'Nuevo cuaderno'**
  String get newNotebookTitle;

  /// New notebook dialog: option for a notebook made of sheets
  ///
  /// In es, this message translates to:
  /// **'Hojas'**
  String get newNotebookSheets;

  /// New notebook dialog: option for an infinite canvas notebook
  ///
  /// In es, this message translates to:
  /// **'Lienzo infinito'**
  String get newNotebookCanvas;

  /// New notebook dialog: description of the infinite canvas option
  ///
  /// In es, this message translates to:
  /// **'Sin cortes, crece mientras escribís. Para mapas conceptuales y diagramas'**
  String get newNotebookCanvasHint;

  /// Title of the confirmation dialog to delete a notebook or folder
  ///
  /// In es, this message translates to:
  /// **'Borrar \"{name}\"'**
  String deleteNotebookTitle(String name);

  /// Body of the confirmation dialog to delete a notebook
  ///
  /// In es, this message translates to:
  /// **'Se borran sus {count, plural, =1{1 hoja} other{{count} hojas}}. No se puede deshacer.'**
  String deleteNotebookBody(int count);

  /// Hint of the PIN field
  ///
  /// In es, this message translates to:
  /// **'PIN'**
  String get pinHint;

  /// Title of the dialog announcing a new app version
  ///
  /// In es, this message translates to:
  /// **'Hay una versión nueva de Vynote'**
  String get updateAvailableTitle;

  /// Update dialog: new version number when the installed one is unknown
  ///
  /// In es, this message translates to:
  /// **'Versión nueva: {version}'**
  String updateNewVersion(String version);

  /// Update dialog: installed version and new version
  ///
  /// In es, this message translates to:
  /// **'Tenés la {installed}  →  nueva {version}'**
  String updateVersions(String installed, String version);

  /// Update dialog: heading of the release notes
  ///
  /// In es, this message translates to:
  /// **'Novedades'**
  String get updateNotesTitle;

  /// Update dialog: release note shown when the release has none
  ///
  /// In es, this message translates to:
  /// **'Mejoras y arreglos varios.'**
  String get updateNotesDefault;

  /// Update dialog: where the update is downloaded from
  ///
  /// In es, this message translates to:
  /// **'Se baja de la página oficial del proyecto en GitHub. Tus cuadernos no se tocan: solo se actualiza la app.'**
  String get updateSourceInfo;

  /// Update dialog: button to skip this version
  ///
  /// In es, this message translates to:
  /// **'Omitir esta versión'**
  String get updateSkip;

  /// Update dialog: button to download and install
  ///
  /// In es, this message translates to:
  /// **'Actualizar'**
  String get updateInstall;

  /// Title of the download progress dialog
  ///
  /// In es, this message translates to:
  /// **'Bajando la versión nueva'**
  String get updateDownloading;

  /// Download progress dialog: shown before the first byte arrives
  ///
  /// In es, this message translates to:
  /// **'Conectando…'**
  String get updateConnecting;

  /// Snackbar when the update download fails
  ///
  /// In es, this message translates to:
  /// **'No pudimos bajar la actualización. Probá de nuevo en un rato.'**
  String get updateDownloadFailed;

  /// Title of the dialog that asks for the install-unknown-apps permission
  ///
  /// In es, this message translates to:
  /// **'Un paso más'**
  String get updateStepTitle;

  /// Body of the dialog that asks for the install permission on Android
  ///
  /// In es, this message translates to:
  /// **'Android pide que le des permiso a Vynote para instalar su propia actualización. Es una sola vez. Te llevamos a los ajustes: activá \"Permitir de esta fuente\", volvé y tocá Actualizar de nuevo.'**
  String get updatePermissionBody;

  /// Button that opens the Android settings
  ///
  /// In es, this message translates to:
  /// **'Ir a ajustes'**
  String get updateGoToSettings;

  /// Title of the dialog shown after the update installed
  ///
  /// In es, this message translates to:
  /// **'Vynote se actualizó'**
  String get updateDoneTitle;

  /// Body of the dialog shown after the update installed
  ///
  /// In es, this message translates to:
  /// **'Ya quedó instalada la {version}. Reiniciá la app para usarla.'**
  String updateDoneBody(String version);

  /// Button to restart the app after updating
  ///
  /// In es, this message translates to:
  /// **'Reiniciar ahora'**
  String get updateRestartNow;

  /// Snackbar when the user cancels the update
  ///
  /// In es, this message translates to:
  /// **'Actualización cancelada.'**
  String get updateCancelled;

  /// Title of the dialog that shows a terminal command to install the update
  ///
  /// In es, this message translates to:
  /// **'Instalala a mano'**
  String get updateManualTitle;

  /// Body of the manual install dialog
  ///
  /// In es, this message translates to:
  /// **'No encontramos cómo pedir permisos de administrador. Abrí una terminal y corré:'**
  String get updateManualBody;

  /// Snackbar after copying the install command
  ///
  /// In es, this message translates to:
  /// **'Comando copiado'**
  String get updateCommandCopied;

  /// Generic "Copy" button
  ///
  /// In es, this message translates to:
  /// **'Copiar'**
  String get commonCopy;

  /// Snackbar when Android cannot open the installer
  ///
  /// In es, this message translates to:
  /// **'No pudimos abrir el instalador. Probá de nuevo en un rato.'**
  String get updateInstallerFailed;

  /// Snackbar when the update cannot be installed on desktop
  ///
  /// In es, this message translates to:
  /// **'No se pudo instalar la actualización. Probá de nuevo en un rato.'**
  String get updateInstallFailed;

  /// Snackbar after saving a notebook PDF
  ///
  /// In es, this message translates to:
  /// **'PDF de \"{name}\" guardado'**
  String exportPdfSaved(String name);

  /// Title of the PDF generation progress dialog
  ///
  /// In es, this message translates to:
  /// **'Generando PDF'**
  String get exportPdfGenerating;

  /// Export progress: current sheet out of total
  ///
  /// In es, this message translates to:
  /// **'Hoja {done} de {total}'**
  String exportSheetProgress(int done, int total);

  /// Snackbar when the PDF could not be generated
  ///
  /// In es, this message translates to:
  /// **'No se pudo generar el PDF: {error}'**
  String exportPdfFailed(String error);

  /// Title of the image export progress dialog
  ///
  /// In es, this message translates to:
  /// **'Generando imágenes'**
  String get exportImagesGenerating;

  /// Snackbar when the images could not be generated
  ///
  /// In es, this message translates to:
  /// **'No se pudieron generar las imágenes: {error}'**
  String exportImagesFailed(String error);

  /// Snackbar after saving several images
  ///
  /// In es, this message translates to:
  /// **'Imágenes guardadas'**
  String get exportImagesSaved;

  /// Snackbar after saving a single image
  ///
  /// In es, this message translates to:
  /// **'Imagen guardada'**
  String get exportImageSaved;

  /// Title of the folder export progress dialog
  ///
  /// In es, this message translates to:
  /// **'Exportando carpeta'**
  String get exportFolderTitle;

  /// Folder export or import progress: current notebook out of total
  ///
  /// In es, this message translates to:
  /// **'Cuaderno {done} de {total}'**
  String exportFolderProgress(int done, int total);

  /// Snackbar after exporting a folder
  ///
  /// In es, this message translates to:
  /// **'Carpeta exportada'**
  String get exportFolderDone;

  /// Snackbar when the folder could not be exported
  ///
  /// In es, this message translates to:
  /// **'No se pudo exportar la carpeta: {error}'**
  String exportFolderFailed(String error);

  /// Import error: the file is not readable as a notebook
  ///
  /// In es, this message translates to:
  /// **'El archivo no es un cuaderno de Vynote (no se puede leer).'**
  String get errImportNotReadable;

  /// Import error: the file is not a Vynote notebook
  ///
  /// In es, this message translates to:
  /// **'El archivo no es un cuaderno de Vynote.'**
  String get errImportNotVynote;

  /// Import error: the file comes from a newer app version
  ///
  /// In es, this message translates to:
  /// **'El archivo es de una versión más nueva de Vynote. Actualizá la app para abrirlo.'**
  String get errImportNewerVersion;

  /// Import error: the sheet list inside the file is corrupt
  ///
  /// In es, this message translates to:
  /// **'La lista de hojas está rota.'**
  String get errImportBrokenSheetList;

  /// Import error: the notebook has no sheets
  ///
  /// In es, this message translates to:
  /// **'El cuaderno no tiene hojas.'**
  String get errImportNoSheets;

  /// Import error: one sheet is corrupt
  ///
  /// In es, this message translates to:
  /// **'Una hoja del archivo está rota.'**
  String get errImportBrokenSheetAny;

  /// Import error: the file has invalid file names
  ///
  /// In es, this message translates to:
  /// **'El archivo tiene nombres no válidos.'**
  String get errImportInvalidNames;

  /// Import error: the file is not a zip
  ///
  /// In es, this message translates to:
  /// **'El archivo no es un .zip.'**
  String get errImportNotZip;

  /// Import error: the zip has no Vynote notebooks
  ///
  /// In es, this message translates to:
  /// **'El .zip no tiene cuadernos de Vynote. ¿Lo exportaste en PDF o PNG?'**
  String get errImportNoNotebooks;

  /// Import error: a required file is missing inside the notebook file
  ///
  /// In es, this message translates to:
  /// **'Al archivo le falta {name}: está roto o no es de Vynote.'**
  String errImportMissingFile(String name);

  /// Import error: a file inside the notebook file is corrupt
  ///
  /// In es, this message translates to:
  /// **'{name} está roto.'**
  String errImportBrokenFile(String name);

  /// Import error: a given sheet is corrupt
  ///
  /// In es, this message translates to:
  /// **'La hoja {name} está rota.'**
  String errImportBrokenSheet(String name);

  /// Title at the top of the library when no folder is open
  ///
  /// In es, this message translates to:
  /// **'Cuadernos'**
  String get libraryTitle;

  /// Name of the root of the library (home): breadcrumb, move dialog and path labels
  ///
  /// In es, this message translates to:
  /// **'Inicio'**
  String get libraryHome;

  /// Label of the floating button that creates a notebook or folder
  ///
  /// In es, this message translates to:
  /// **'Nuevo'**
  String get libraryNew;

  /// Library new menu: create a notebook
  ///
  /// In es, this message translates to:
  /// **'Cuaderno nuevo'**
  String get libraryNewNotebook;

  /// Library new menu and dialog title: create a folder
  ///
  /// In es, this message translates to:
  /// **'Carpeta nueva'**
  String get libraryNewFolder;

  /// Library new menu: import a .vynote notebook file
  ///
  /// In es, this message translates to:
  /// **'Importar cuaderno .vynote'**
  String get libraryImportNotebook;

  /// Library new menu: import a folder from a zip
  ///
  /// In es, this message translates to:
  /// **'Importar carpeta (.zip)'**
  String get libraryImportFolder;

  /// Tooltip of the library overflow button
  ///
  /// In es, this message translates to:
  /// **'Más opciones'**
  String get libraryMenuTooltip;

  /// Tooltip of the back arrow that goes up one folder
  ///
  /// In es, this message translates to:
  /// **'Subir una carpeta'**
  String get libraryUpTooltip;

  /// Hint of the library search field
  ///
  /// In es, this message translates to:
  /// **'Buscar cuadernos y carpetas'**
  String get librarySearchHint;

  /// Tooltip of the button that clears the library search
  ///
  /// In es, this message translates to:
  /// **'Borrar búsqueda'**
  String get librarySearchClear;

  /// Library empty state when the search finds nothing
  ///
  /// In es, this message translates to:
  /// **'Sin resultados'**
  String get libraryEmptyNoResults;

  /// Library empty state when there are no notebooks at all
  ///
  /// In es, this message translates to:
  /// **'Todavía no hay cuadernos'**
  String get libraryEmptyNone;

  /// Library empty state inside an empty folder
  ///
  /// In es, this message translates to:
  /// **'Esta carpeta está vacía'**
  String get libraryEmptyFolder;

  /// Number of notebooks (library header and folder card)
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{{count} cuaderno} other{{count} cuadernos}}'**
  String libraryNotebookCount(int count);

  /// Number of folders in the library header
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{{count} carpeta} other{{count} carpetas}}'**
  String libraryFolderCount(int count);

  /// Library header subtitle when there is nothing yet
  ///
  /// In es, this message translates to:
  /// **'Creá el primero para empezar'**
  String get libraryHeaderFirst;

  /// Library header subtitle: counts followed by a usage hint
  ///
  /// In es, this message translates to:
  /// **'{parts} · mantené uno apretado para opciones o arrastralo a una carpeta'**
  String libraryHeaderHint(String parts);

  /// Library header subtitle while searching
  ///
  /// In es, this message translates to:
  /// **'Resultados en todas las carpetas'**
  String get libraryResultsEverywhere;

  /// Snackbar when the open notebook was deleted from inside
  ///
  /// In es, this message translates to:
  /// **'Cuaderno borrado'**
  String get libraryNotebookDeleted;

  /// Snackbar when a link points to a notebook that does not exist anymore
  ///
  /// In es, this message translates to:
  /// **'El cuaderno ya no existe'**
  String get libraryNotebookGone;

  /// Subtitle of the PIN dialog when opening a locked notebook
  ///
  /// In es, this message translates to:
  /// **'Este cuaderno está bloqueado'**
  String get libraryLockedNotebook;

  /// Snackbar when the PIN is wrong
  ///
  /// In es, this message translates to:
  /// **'PIN incorrecto'**
  String get libraryWrongPin;

  /// Snackbar after importing a notebook
  ///
  /// In es, this message translates to:
  /// **'Importado como \"{name}\"'**
  String libraryImportedAs(String name);

  /// Snackbar when an import failed
  ///
  /// In es, this message translates to:
  /// **'No se pudo importar: {error}'**
  String libraryImportFailed(String error);

  /// Title of the folder import progress dialog
  ///
  /// In es, this message translates to:
  /// **'Importando carpeta'**
  String get libraryImportingFolder;

  /// Snackbar when the user cancels a folder import
  ///
  /// In es, this message translates to:
  /// **'Importación cancelada'**
  String get libraryImportCancelled;

  /// Suffix of the import result when some notebooks could not be read
  ///
  /// In es, this message translates to:
  /// **' ({count} no se pudieron leer)'**
  String libraryImportUnreadable(int count);

  /// Snackbar after importing notebooks into the current folder
  ///
  /// In es, this message translates to:
  /// **'Importados {count} cuadernos{fail}'**
  String libraryImportedMany(int count, String fail);

  /// Snackbar after importing a folder
  ///
  /// In es, this message translates to:
  /// **'Carpeta \"{name}\" importada: {count} cuadernos{fail}'**
  String libraryImportedFolder(String name, int count, String fail);

  /// Snackbar after exporting a notebook as .vynote
  ///
  /// In es, this message translates to:
  /// **'Cuaderno \"{name}\" guardado'**
  String libraryExportDone(String name);

  /// Snackbar when the export failed
  ///
  /// In es, this message translates to:
  /// **'No se pudo exportar: {error}'**
  String libraryExportFailed(String error);

  /// Hint of the new folder name field
  ///
  /// In es, this message translates to:
  /// **'Ej: Facultad'**
  String get libraryFolderHint;

  /// Title of the rename notebook dialog
  ///
  /// In es, this message translates to:
  /// **'Renombrar cuaderno'**
  String get libraryRenameNotebook;

  /// Title of the rename folder dialog
  ///
  /// In es, this message translates to:
  /// **'Renombrar carpeta'**
  String get libraryRenameFolder;

  /// Name given to a duplicated notebook
  ///
  /// In es, this message translates to:
  /// **'{name} (copia)'**
  String libraryCopySuffix(String name);

  /// Snackbar after duplicating a notebook
  ///
  /// In es, this message translates to:
  /// **'Cuaderno duplicado'**
  String get libraryDuplicated;

  /// Snackbar when trying to export an empty folder
  ///
  /// In es, this message translates to:
  /// **'La carpeta está vacía'**
  String get libraryFolderEmptyExport;

  /// Title of the move dialog
  ///
  /// In es, this message translates to:
  /// **'Mover \"{name}\" a…'**
  String libraryMoveTitle(String name);

  /// Snackbar after moving a notebook
  ///
  /// In es, this message translates to:
  /// **'Movido a {path}'**
  String libraryMovedTo(String path);

  /// Snackbar after moving a folder
  ///
  /// In es, this message translates to:
  /// **'Movida a {path}'**
  String libraryMovedFolderTo(String path);

  /// Snackbar action that undoes a move
  ///
  /// In es, this message translates to:
  /// **'Deshacer'**
  String get libraryUndo;

  /// Body of the delete confirmation for an empty folder
  ///
  /// In es, this message translates to:
  /// **'La carpeta está vacía.'**
  String get libraryFolderEmptyBody;

  /// Title of the confirmation to delete a folder with everything in it
  ///
  /// In es, this message translates to:
  /// **'Borrar todo'**
  String get libraryDeleteAllTitle;

  /// Body of the confirmation to delete a folder and its contents
  ///
  /// In es, this message translates to:
  /// **'Se borran la carpeta \"{name}\", sus subcarpetas y {count, plural, =1{1 cuaderno} other{{count} cuadernos}} con todas sus hojas. No se puede deshacer.'**
  String libraryDeleteAllBody(String name, int count);

  /// Body of the dialog that asks what to do with a folder content when deleting it
  ///
  /// In es, this message translates to:
  /// **'¿Qué hacemos con lo que tiene adentro?'**
  String get libraryFolderWhatToDo;

  /// Button that moves the notebooks out of the folder being deleted
  ///
  /// In es, this message translates to:
  /// **'Sacar los cuadernos a {parent}'**
  String libraryFolderKeep(String parent);

  /// Context menu item: rename
  ///
  /// In es, this message translates to:
  /// **'Renombrar'**
  String get libraryOptRename;

  /// Context menu item: move to another folder
  ///
  /// In es, this message translates to:
  /// **'Mover a…'**
  String get libraryOptMove;

  /// Context menu item: export
  ///
  /// In es, this message translates to:
  /// **'Exportar'**
  String get libraryOptExport;

  /// Context menu item: delete
  ///
  /// In es, this message translates to:
  /// **'Borrar'**
  String get libraryOptDelete;

  /// Context menu item: open a notebook
  ///
  /// In es, this message translates to:
  /// **'Abrir'**
  String get libraryOptOpen;

  /// Context menu item: duplicate a notebook
  ///
  /// In es, this message translates to:
  /// **'Duplicar'**
  String get libraryOptDuplicate;

  /// Number of sheets of a notebook (library card)
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{{count} hoja} other{{count} hojas}}'**
  String librarySheetCount(int count);

  /// Label next to the folder where the item currently is, in the move dialog
  ///
  /// In es, this message translates to:
  /// **'acá'**
  String get moveHere;

  /// Tooltip of the sync indicator: everything is synced
  ///
  /// In es, this message translates to:
  /// **'Sincronizado'**
  String get syncIndicatorSynced;

  /// Tooltip of the sync indicator: syncing now
  ///
  /// In es, this message translates to:
  /// **'Sincronizando'**
  String get syncIndicatorSyncing;

  /// Tooltip of the sync indicator: local changes waiting to upload
  ///
  /// In es, this message translates to:
  /// **'Cambios por subir'**
  String get syncIndicatorPending;

  /// Tooltip of the sync indicator: offline
  ///
  /// In es, this message translates to:
  /// **'Sin conexión'**
  String get syncIndicatorOffline;

  /// Tooltip of the sync indicator: sync error
  ///
  /// In es, this message translates to:
  /// **'Error de sincronización'**
  String get syncIndicatorError;

  /// Date of a notebook edited today, followed by the time
  ///
  /// In es, this message translates to:
  /// **'hoy {time}'**
  String dateToday(String time);

  /// Date of a notebook edited yesterday, followed by the time
  ///
  /// In es, this message translates to:
  /// **'ayer {time}'**
  String dateYesterday(String time);

  /// DateFormat pattern for the time of day (24 h in Spanish)
  ///
  /// In es, this message translates to:
  /// **'HH:mm'**
  String get datePatternTime;

  /// DateFormat pattern for day and month of a date in the current year
  ///
  /// In es, this message translates to:
  /// **'dd/MM'**
  String get datePatternDayMonth;

  /// DateFormat pattern for day, month and year of a date in another year
  ///
  /// In es, this message translates to:
  /// **'dd/MM/yyyy'**
  String get datePatternDayMonthYear;

  /// Sync error: no connection
  ///
  /// In es, this message translates to:
  /// **'Sin conexión'**
  String get syncErrOffline;

  /// Sync error: the Google session expired
  ///
  /// In es, this message translates to:
  /// **'La sesión de Google venció. Volvé a conectar.'**
  String get syncErrAuthExpired;

  /// Sync error: the file changed in the cloud while uploading
  ///
  /// In es, this message translates to:
  /// **'El archivo cambió en la nube mientras se subía; se reintenta'**
  String get syncErrConflict;

  /// Sync error: the file does not exist in the cloud
  ///
  /// In es, this message translates to:
  /// **'No existe en la nube'**
  String get syncErrNotFound;

  /// Sync error: the cloud encryption setup changed
  ///
  /// In es, this message translates to:
  /// **'Cambió la configuración de cifrado de la nube'**
  String get syncErrVaultChanged;

  /// Sync error: the cloud is encrypted and the passphrase is missing
  ///
  /// In es, this message translates to:
  /// **'La nube está cifrada: ingresá la frase en Sincronización > Cifrado'**
  String get syncErrCryptoLocked;

  /// Sync error: wrong encryption passphrase
  ///
  /// In es, this message translates to:
  /// **'La frase de cifrado es incorrecta'**
  String get syncErrWrongPassphrase;

  /// Sync error: another device enabled encryption at the same time
  ///
  /// In es, this message translates to:
  /// **'Otro dispositivo activó el cifrado al mismo tiempo. Ingresá su frase.'**
  String get syncErrCryptoOtherDevice;

  /// Sync error: the cloud is not encrypted
  ///
  /// In es, this message translates to:
  /// **'La nube no está cifrada'**
  String get syncErrCloudNotEncrypted;

  /// Sync error: not connected to Google yet
  ///
  /// In es, this message translates to:
  /// **'Conectá con Google primero'**
  String get syncErrConnectFirst;

  /// Sync error: a background sync is running
  ///
  /// In es, this message translates to:
  /// **'Hay una sincronización en segundo plano en curso; probá de nuevo en unos segundos'**
  String get syncErrBackgroundBusy;

  /// Sync error: some files could not be synced
  ///
  /// In es, this message translates to:
  /// **'{count} archivo(s) no se pudieron sincronizar; se reintenta en la próxima pasada'**
  String syncErrFilesFailed(String count);

  /// Sync error: generic failure with its technical detail
  ///
  /// In es, this message translates to:
  /// **'No se pudo sincronizar: {detail}'**
  String syncErrCouldNotSync(String detail);

  /// Relative time: just now
  ///
  /// In es, this message translates to:
  /// **'hace un momento'**
  String get syncAgoNow;

  /// Relative time: minutes ago
  ///
  /// In es, this message translates to:
  /// **'hace {count} min'**
  String syncAgoMinutes(int count);

  /// Relative time: hours ago
  ///
  /// In es, this message translates to:
  /// **'hace {count} h'**
  String syncAgoHours(int count);

  /// Relative time: days ago
  ///
  /// In es, this message translates to:
  /// **'hace {count} d'**
  String syncAgoDays(int count);

  /// Sync sheet status when the build has no Google credentials
  ///
  /// In es, this message translates to:
  /// **'Esta versión no tiene configurado el acceso a Google (falta: {missing}). Las notas siguen guardándose en este dispositivo.'**
  String syncNotConfigured(String missing);

  /// Sync sheet status when not connected
  ///
  /// In es, this message translates to:
  /// **'Sin conectar. Los cuadernos se guardan solo en este dispositivo.'**
  String get syncDisconnectedStatus;

  /// Sync sheet status while connecting
  ///
  /// In es, this message translates to:
  /// **'Conectando con Google…'**
  String get syncConnecting;

  /// Sync sheet status while syncing
  ///
  /// In es, this message translates to:
  /// **'Sincronizando…'**
  String get syncSyncing;

  /// Sync sheet status when connected: account and last sync line
  ///
  /// In es, this message translates to:
  /// **'Conectado como {account}\n{last}'**
  String syncConnectedAs(String account, String last);

  /// Sync sheet: the first sync did not happen yet
  ///
  /// In es, this message translates to:
  /// **'Todavía no se sincronizó'**
  String get syncNever;

  /// Sync sheet: when the last sync happened
  ///
  /// In es, this message translates to:
  /// **'Última sincronización: {ago}'**
  String syncLast(String ago);

  /// Title of the sync sheet and of the library menu item
  ///
  /// In es, this message translates to:
  /// **'Sincronización con Google Drive'**
  String get syncTitle;

  /// Sync sheet: warning about conflicting sheets
  ///
  /// In es, this message translates to:
  /// **'Hubo {count} conflicto(s): buscá las hojas \"(conflicto)\" y quedate con la que sirva.'**
  String syncConflicts(int count);

  /// Sync sheet switch title
  ///
  /// In es, this message translates to:
  /// **'Sincronizar en segundo plano'**
  String get syncBackgroundTitle;

  /// Sync sheet switch subtitle
  ///
  /// In es, this message translates to:
  /// **'Cada 15 minutos con red, aunque la app esté cerrada.'**
  String get syncBackgroundSubtitle;

  /// Sync sheet button to sign in with Google
  ///
  /// In es, this message translates to:
  /// **'Conectar con Google'**
  String get syncConnect;

  /// Sync sheet button to sync right now
  ///
  /// In es, this message translates to:
  /// **'Sincronizar ahora'**
  String get syncNow;

  /// Sync sheet button to disconnect the Google account
  ///
  /// In es, this message translates to:
  /// **'Desconectar'**
  String get syncDisconnect;

  /// Encryption status: unknown until the next sync
  ///
  /// In es, this message translates to:
  /// **'Todavía no se sabe: se ve en la próxima sincronización.'**
  String get cryptoStatusUnknown;

  /// Encryption status: off
  ///
  /// In es, this message translates to:
  /// **'Desactivado: Google puede leer lo que se sube a tu Drive.'**
  String get cryptoStatusOff;

  /// Encryption status: on
  ///
  /// In es, this message translates to:
  /// **'Activado: en Drive solo hay archivos cifrados con tu frase.'**
  String get cryptoStatusOn;

  /// Encryption status: the cloud is encrypted and needs the passphrase
  ///
  /// In es, this message translates to:
  /// **'La nube está cifrada. Ingresá la frase para poder sincronizar.'**
  String get cryptoStatusLocked;

  /// Title of the encryption section of the sync sheet
  ///
  /// In es, this message translates to:
  /// **'Cifrado'**
  String get cryptoTitle;

  /// Encryption section: warning about forgetting the passphrase
  ///
  /// In es, this message translates to:
  /// **'Si olvidás la frase no hay forma de recuperar lo que está en la nube (lo de este dispositivo no se pierde). Los nombres de archivo en Drive son códigos al azar y siguen a la vista.'**
  String get cryptoWarning;

  /// Button and dialog title to turn encryption on
  ///
  /// In es, this message translates to:
  /// **'Activar cifrado'**
  String get cryptoEnable;

  /// Button to enter the passphrase of an encrypted cloud
  ///
  /// In es, this message translates to:
  /// **'Ingresar frase'**
  String get cryptoEnterPass;

  /// Title of the confirmation to turn encryption off
  ///
  /// In es, this message translates to:
  /// **'¿Desactivar el cifrado?'**
  String get cryptoDisableTitle;

  /// Body of the confirmation to turn encryption off
  ///
  /// In es, this message translates to:
  /// **'Se vuelve a subir todo sin cifrar y se borra lo cifrado de Drive. Puede tardar si hay muchos archivos.'**
  String get cryptoDisableBody;

  /// Confirm button to turn encryption off
  ///
  /// In es, this message translates to:
  /// **'Desactivar'**
  String get cryptoDisableConfirm;

  /// Button to turn encryption off
  ///
  /// In es, this message translates to:
  /// **'Desactivar cifrado'**
  String get cryptoDisable;

  /// Title of the dialog that asks for the passphrase
  ///
  /// In es, this message translates to:
  /// **'Frase de cifrado'**
  String get cryptoPassTitle;

  /// Passphrase dialog: explanation when enabling encryption
  ///
  /// In es, this message translates to:
  /// **'Elegí una frase y anotala en un lugar seguro. Si la olvidás no hay forma de recuperar lo que está en la nube (lo de este dispositivo no se pierde). Se va a subir todo cifrado y borrar lo anterior de Drive.'**
  String get cryptoPassIntro;

  /// Label of the passphrase field
  ///
  /// In es, this message translates to:
  /// **'Frase'**
  String get cryptoPassLabel;

  /// Label of the repeat passphrase field
  ///
  /// In es, this message translates to:
  /// **'Repetí la frase'**
  String get cryptoPassRepeat;

  /// Passphrase dialog error: the two passphrases differ
  ///
  /// In es, this message translates to:
  /// **'Las dos frases no coinciden.'**
  String get cryptoPassMismatch;

  /// Passphrase dialog confirm button when enabling
  ///
  /// In es, this message translates to:
  /// **'Activar'**
  String get cryptoActivate;

  /// Passphrase dialog confirm button when unlocking
  ///
  /// In es, this message translates to:
  /// **'Desbloquear'**
  String get cryptoUnlock;

  /// Passphrase dialog error: passphrase too short
  ///
  /// In es, this message translates to:
  /// **'La frase tiene que tener al menos {min} caracteres.'**
  String cryptoPassShort(int min);

  /// Encryption progress: deriving the key
  ///
  /// In es, this message translates to:
  /// **'Derivando la clave (puede tardar unos segundos)…'**
  String get cryptoStepDeriving;

  /// Encryption progress: syncing before encrypting
  ///
  /// In es, this message translates to:
  /// **'Sincronizando antes de cifrar…'**
  String get cryptoStepSyncBeforeEncrypt;

  /// Encryption progress: syncing before decrypting
  ///
  /// In es, this message translates to:
  /// **'Sincronizando antes de descifrar…'**
  String get cryptoStepSyncBeforeDecrypt;

  /// Encryption progress: encrypting file n of total
  ///
  /// In es, this message translates to:
  /// **'Cifrando {done}/{total}…'**
  String cryptoStepEncrypting(int done, int total);

  /// Encryption progress: decrypting file n of total
  ///
  /// In es, this message translates to:
  /// **'Descifrando {done}/{total}…'**
  String cryptoStepDecrypting(int done, int total);

  /// Generic "Rename" menu item or button
  ///
  /// In es, this message translates to:
  /// **'Renombrar'**
  String get commonRename;

  /// Generic "Export" menu item, button or title
  ///
  /// In es, this message translates to:
  /// **'Exportar'**
  String get commonExport;

  /// Generic "Save" button
  ///
  /// In es, this message translates to:
  /// **'Guardar'**
  String get commonSave;

  /// Generic "Update"/"Refresh" button
  ///
  /// In es, this message translates to:
  /// **'Actualizar'**
  String get commonUpdate;

  /// Generic "Search" menu item or tooltip
  ///
  /// In es, this message translates to:
  /// **'Buscar'**
  String get commonSearch;

  /// Label of a sheet by its number
  ///
  /// In es, this message translates to:
  /// **'Hoja {n}'**
  String sheetLabel(int n);

  /// Label of a sheet with its number and title
  ///
  /// In es, this message translates to:
  /// **'Hoja {n} · {title}'**
  String sheetLabelTitled(int n, String title);

  /// Number of sheets (sections and export dialogs)
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{{count} hoja} other{{count} hojas}}'**
  String sheetCountPlural(int count);

  /// Insert menu: import a PDF
  ///
  /// In es, this message translates to:
  /// **'PDF'**
  String get menuInsertPdf;

  /// Insert menu: record voice
  ///
  /// In es, this message translates to:
  /// **'Grabación de voz'**
  String get menuInsertVoice;

  /// Insert menu: image from the gallery
  ///
  /// In es, this message translates to:
  /// **'Imagen'**
  String get menuInsertImage;

  /// Insert menu: take a photo
  ///
  /// In es, this message translates to:
  /// **'Cámara'**
  String get menuInsertCamera;

  /// Insert menu: audio file
  ///
  /// In es, this message translates to:
  /// **'Archivo de audio'**
  String get menuInsertAudio;

  /// Insert menu: sticky note
  ///
  /// In es, this message translates to:
  /// **'Nota adhesiva'**
  String get menuInsertSticky;

  /// Insert menu: new sheet
  ///
  /// In es, this message translates to:
  /// **'Hoja nueva'**
  String get menuInsertSheet;

  /// More menu: leave reading mode
  ///
  /// In es, this message translates to:
  /// **'Salir del modo lectura'**
  String get menuMoreReadingExit;

  /// More menu: enter reading mode
  ///
  /// In es, this message translates to:
  /// **'Modo lectura'**
  String get menuMoreReading;

  /// More menu and tooltip: remove the bookmark of the sheet
  ///
  /// In es, this message translates to:
  /// **'Quitar marcador'**
  String get menuMoreBookmarkRemove;

  /// More menu and tooltip: bookmark the current sheet
  ///
  /// In es, this message translates to:
  /// **'Marcar esta hoja'**
  String get menuMoreBookmarkAdd;

  /// More menu and toolbar: full screen
  ///
  /// In es, this message translates to:
  /// **'Pantalla completa'**
  String get menuMoreFullscreen;

  /// More menu: sheet style
  ///
  /// In es, this message translates to:
  /// **'Estilo de hoja'**
  String get menuMoreStyle;

  /// More menu: paper color of an infinite canvas, and dialog title
  ///
  /// In es, this message translates to:
  /// **'Color del papel'**
  String get menuMorePaperColor;

  /// More menu: keyboard shortcuts
  ///
  /// In es, this message translates to:
  /// **'Atajos de teclado'**
  String get menuMoreShortcuts;

  /// Tooltip: remove the notebook from favorites
  ///
  /// In es, this message translates to:
  /// **'Quitar de favoritos'**
  String get menuMoreFavoriteRemove;

  /// Tooltip: mark the notebook as favorite
  ///
  /// In es, this message translates to:
  /// **'Favorito'**
  String get menuMoreFavoriteAdd;

  /// Tooltip: remove the PIN lock
  ///
  /// In es, this message translates to:
  /// **'Quitar bloqueo'**
  String get menuMoreLockRemove;

  /// Tooltip: lock the notebook with a PIN
  ///
  /// In es, this message translates to:
  /// **'Bloquear con PIN'**
  String get menuMoreLockAdd;

  /// Tooltip: share the notebook as PDF
  ///
  /// In es, this message translates to:
  /// **'Compartir'**
  String get menuMoreShare;

  /// Tooltip: print the notebook
  ///
  /// In es, this message translates to:
  /// **'Imprimir'**
  String get menuMorePrint;

  /// Tooltip: delete the notebook
  ///
  /// In es, this message translates to:
  /// **'Borrar cuaderno'**
  String get menuMoreDeleteNotebook;

  /// Title of the folder export sheet
  ///
  /// In es, this message translates to:
  /// **'Exportar carpeta'**
  String get menuExportFolderTitle;

  /// Folder export: PDF option description
  ///
  /// In es, this message translates to:
  /// **'Un PDF por cuaderno'**
  String get menuExportFolderPdf;

  /// Folder export: PNG option description
  ///
  /// In es, this message translates to:
  /// **'Una carpeta por cuaderno con una imagen por hoja'**
  String get menuExportFolderPng;

  /// Folder export: .vynote option description
  ///
  /// In es, this message translates to:
  /// **'Un .vynote por cuaderno, para pasarlo a otro dispositivo'**
  String get menuExportFolderVynote;

  /// Export format name: PDF
  ///
  /// In es, this message translates to:
  /// **'PDF'**
  String get menuExportFormatPdf;

  /// Export format name: PNG images
  ///
  /// In es, this message translates to:
  /// **'Imágenes (PNG)'**
  String get menuExportFormatPng;

  /// Export format name: Vynote
  ///
  /// In es, this message translates to:
  /// **'Vynote'**
  String get menuExportFormatVynote;

  /// Export sheet switch: include the paper background
  ///
  /// In es, this message translates to:
  /// **'Incluir el fondo de la hoja'**
  String get menuExportBackground;

  /// Export sheet switch subtitle when off
  ///
  /// In es, this message translates to:
  /// **'Apagado: solo lo escrito, sobre blanco'**
  String get menuExportBackgroundOff;

  /// Export option description: whole notebook as PDF
  ///
  /// In es, this message translates to:
  /// **'Todo el cuaderno'**
  String get menuExportAllPdf;

  /// Export option description: all sheets as PNGs in a zip
  ///
  /// In es, this message translates to:
  /// **'Todas las hojas, en un .zip'**
  String get menuExportAllPng;

  /// Export option: notebook as a .vynote file
  ///
  /// In es, this message translates to:
  /// **'Cuaderno de Vynote (.vynote)'**
  String get menuExportVynoteTitle;

  /// Export option description: .vynote file
  ///
  /// In es, this message translates to:
  /// **'Para pasarlo a otro dispositivo o hacer copia'**
  String get menuExportVynoteHint;

  /// Export option: PDF of the current sheet
  ///
  /// In es, this message translates to:
  /// **'PDF de esta hoja'**
  String get menuExportSheetPdf;

  /// Export option: image of the current sheet
  ///
  /// In es, this message translates to:
  /// **'Imagen de esta hoja (PNG)'**
  String get menuExportSheetPng;

  /// Sections menu: create a section, and dialog title
  ///
  /// In es, this message translates to:
  /// **'Nueva sección'**
  String get sectionNew;

  /// Tooltip of the section options button
  ///
  /// In es, this message translates to:
  /// **'Opciones de la sección'**
  String get sectionOptions;

  /// Section menu: move the section up
  ///
  /// In es, this message translates to:
  /// **'Subir'**
  String get sectionUp;

  /// Section menu: move the section down
  ///
  /// In es, this message translates to:
  /// **'Bajar'**
  String get sectionDown;

  /// Title of the dialog that asks which sections to export
  ///
  /// In es, this message translates to:
  /// **'¿Qué secciones exportar?'**
  String get sectionExportTitle;

  /// Checkbox that selects all sections
  ///
  /// In es, this message translates to:
  /// **'Todas'**
  String get sectionAll;

  /// Title of the index (table of contents) panel
  ///
  /// In es, this message translates to:
  /// **'Índice'**
  String get indexTitle;

  /// Index panel empty state
  ///
  /// In es, this message translates to:
  /// **'Todavía no hay títulos.\nUsá la herramienta Título de la barra para marcar lo que escribiste.'**
  String get indexEmpty;

  /// Index entry menu: promote the heading to the given level
  ///
  /// In es, this message translates to:
  /// **'Pasar a Título {level}'**
  String indexLevelUp(int level);

  /// Index entry menu: demote the heading to the given level
  ///
  /// In es, this message translates to:
  /// **'Pasar a Título {level}'**
  String indexLevelDown(int level);

  /// Index entry menu: remove the heading from the index
  ///
  /// In es, this message translates to:
  /// **'Quitar del índice'**
  String get indexRemove;

  /// Dialog title to rename a heading
  ///
  /// In es, this message translates to:
  /// **'Renombrar título'**
  String get indexRenameTitle;

  /// Search results hint when the query is empty
  ///
  /// In es, this message translates to:
  /// **'Buscá en los textos, notas adhesivas y títulos de hojas'**
  String get searchHint;

  /// Search results message when nothing matches
  ///
  /// In es, this message translates to:
  /// **'Sin resultados para \"{query}\"'**
  String searchNone(String query);

  /// Search result snippet for a sheet title match
  ///
  /// In es, this message translates to:
  /// **'Título: {title}'**
  String searchTitleSnippet(String title);

  /// Ivory paper color name (also the tooltip of its swatch)
  ///
  /// In es, this message translates to:
  /// **'Marfil'**
  String get paperColorIvory;

  /// White paper color name (also the tooltip of its swatch)
  ///
  /// In es, this message translates to:
  /// **'Blanco'**
  String get paperColorWhite;

  /// Cream paper color name (also the tooltip of its swatch)
  ///
  /// In es, this message translates to:
  /// **'Crema'**
  String get paperColorCream;

  /// Gray paper color name (also the tooltip of its swatch)
  ///
  /// In es, this message translates to:
  /// **'Gris'**
  String get paperColorGray;

  /// Light blue paper color name (also the tooltip of its swatch)
  ///
  /// In es, this message translates to:
  /// **'Celeste'**
  String get paperColorLightBlue;

  /// Green paper color name (also the tooltip of its swatch)
  ///
  /// In es, this message translates to:
  /// **'Verde'**
  String get paperColorGreen;

  /// Title of the confirmation to delete a user template
  ///
  /// In es, this message translates to:
  /// **'¿Borrar la plantilla «{name}»?'**
  String styleDeleteTemplate(String name);

  /// Style dialog section: paper size
  ///
  /// In es, this message translates to:
  /// **'Tamaño'**
  String get styleSize;

  /// Style dialog section: paper background
  ///
  /// In es, this message translates to:
  /// **'Fondo'**
  String get styleBackground;

  /// Style dialog section: built-in templates
  ///
  /// In es, this message translates to:
  /// **'Plantillas'**
  String get styleTemplates;

  /// Style dialog section: user templates
  ///
  /// In es, this message translates to:
  /// **'Mis plantillas'**
  String get styleMyTemplates;

  /// Style dialog button: create a template from an image
  ///
  /// In es, this message translates to:
  /// **'Desde una imagen…'**
  String get styleFromImage;

  /// Style dialog section: line spacing for lined paper
  ///
  /// In es, this message translates to:
  /// **'Interlineado'**
  String get styleSpacingLined;

  /// Style dialog section: grid spacing
  ///
  /// In es, this message translates to:
  /// **'Cuadrícula'**
  String get styleSpacingGrid;

  /// Style dialog section: where to apply the style
  ///
  /// In es, this message translates to:
  /// **'Aplicar a'**
  String get styleApplyTo;

  /// Style dialog option: apply to this sheet only
  ///
  /// In es, this message translates to:
  /// **'Esta hoja'**
  String get styleThisSheet;

  /// Style dialog option: apply to the whole notebook
  ///
  /// In es, this message translates to:
  /// **'Todo el cuaderno'**
  String get styleWholeNotebook;

  /// Style dialog title when creating a new sheet
  ///
  /// In es, this message translates to:
  /// **'Hoja nueva'**
  String get styleTitleNew;

  /// Style dialog title
  ///
  /// In es, this message translates to:
  /// **'Estilo de hoja'**
  String get styleTitle;

  /// Style dialog confirm button
  ///
  /// In es, this message translates to:
  /// **'Aplicar'**
  String get styleApply;

  /// Tooltip of the pages panel button when the bookmark filter is on
  ///
  /// In es, this message translates to:
  /// **'Ver todas'**
  String get pagesAll;

  /// Tooltip of the pages panel button that filters bookmarked sheets
  ///
  /// In es, this message translates to:
  /// **'Solo marcadas'**
  String get pagesOnlyBookmarked;

  /// Tooltip of the button that adds a sheet after the current one
  ///
  /// In es, this message translates to:
  /// **'Hoja nueva después de la actual'**
  String get pagesNewAfter;

  /// Pages panel empty state with the bookmark filter on
  ///
  /// In es, this message translates to:
  /// **'No hay hojas marcadas'**
  String get pagesNoBookmarks;

  /// Pages panel hint when there are no bookmarked sheets
  ///
  /// In es, this message translates to:
  /// **'No hay hojas marcadas. Usá el marcador de arriba para marcar la hoja que estás viendo.'**
  String get pagesNoBookmarksHint;

  /// Tooltip of the thumbnail bookmark button
  ///
  /// In es, this message translates to:
  /// **'Marcar'**
  String get pagesBookmark;

  /// Tooltip of the thumbnail drag handle
  ///
  /// In es, this message translates to:
  /// **'Arrastrar para mover'**
  String get pagesDragToMove;

  /// Sheet menu: add a sheet after this one
  ///
  /// In es, this message translates to:
  /// **'Hoja nueva después'**
  String get pagesNewAfterMenu;

  /// Sheet menu: add a sheet using a template
  ///
  /// In es, this message translates to:
  /// **'Hoja nueva con plantilla…'**
  String get pagesNewWithTemplate;

  /// Sheet menu: duplicate the sheet
  ///
  /// In es, this message translates to:
  /// **'Duplicar'**
  String get pagesDuplicate;

  /// Sheet menu and dialog title: save the sheet as a template
  ///
  /// In es, this message translates to:
  /// **'Guardar como plantilla'**
  String get pagesSaveTemplate;

  /// Sheet menu: move the sheet earlier
  ///
  /// In es, this message translates to:
  /// **'Mover antes'**
  String get pagesMoveBefore;

  /// Sheet menu: move the sheet later
  ///
  /// In es, this message translates to:
  /// **'Mover después'**
  String get pagesMoveAfter;

  /// Default name suggested when saving a sheet as a template
  ///
  /// In es, this message translates to:
  /// **'Plantilla {n}'**
  String notebookTemplateDefault(int n);

  /// Snackbar when the template could not be saved
  ///
  /// In es, this message translates to:
  /// **'No se pudo guardar la plantilla: {error}'**
  String notebookTemplateFailed(String error);

  /// Snackbar after saving a template
  ///
  /// In es, this message translates to:
  /// **'Plantilla guardada'**
  String get notebookTemplateSaved;

  /// Label of the template name field
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get notebookTemplateName;

  /// Dialog title to rename a sheet
  ///
  /// In es, this message translates to:
  /// **'Nombre de la hoja {n}'**
  String notebookSheetNameTitle(int n);

  /// Hint of the optional sheet title field
  ///
  /// In es, this message translates to:
  /// **'Opcional'**
  String get notebookOptional;

  /// Snackbar when deleting the only sheet
  ///
  /// In es, this message translates to:
  /// **'No se puede borrar la única hoja del cuaderno'**
  String get notebookLastSheet;

  /// Title of the confirmation to delete a sheet
  ///
  /// In es, this message translates to:
  /// **'Borrar la hoja {n}'**
  String notebookDeleteSheetTitle(int n);

  /// Body of the confirmation to delete a sheet
  ///
  /// In es, this message translates to:
  /// **'Se borra la hoja con todo lo que tiene (se puede deshacer).'**
  String get notebookDeleteSheetBody;

  /// Snackbar when a sheet cannot be read from disk
  ///
  /// In es, this message translates to:
  /// **'No se pudo leer la hoja: {error}'**
  String notebookSheetReadFailed(String error);

  /// Title of the bookmark dialog
  ///
  /// In es, this message translates to:
  /// **'Marcador'**
  String get notebookBookmarkTitle;

  /// Hint of the bookmark name field
  ///
  /// In es, this message translates to:
  /// **'Nombre (opcional)'**
  String get notebookBookmarkHint;

  /// Bookmark dialog button: bookmark without a name
  ///
  /// In es, this message translates to:
  /// **'Sin nombre'**
  String get notebookBookmarkNoName;

  /// Snackbar when a section cannot be opened
  ///
  /// In es, this message translates to:
  /// **'No se pudo abrir la sección: {error}'**
  String notebookSectionOpenFailed(String error);

  /// Default name of a new section
  ///
  /// In es, this message translates to:
  /// **'Sección {n}'**
  String notebookSectionDefault(int n);

  /// Hint of the new section name field
  ///
  /// In es, this message translates to:
  /// **'Ej: Práctica'**
  String get notebookSectionHint;

  /// Title of the rename section dialog
  ///
  /// In es, this message translates to:
  /// **'Renombrar sección'**
  String get notebookSectionRename;

  /// Snackbar when deleting the only section
  ///
  /// In es, this message translates to:
  /// **'No se puede borrar la única sección del cuaderno'**
  String get notebookLastSection;

  /// Title of the confirmation to delete a section
  ///
  /// In es, this message translates to:
  /// **'Borrar la sección \"{name}\"'**
  String notebookDeleteSectionTitle(String name);

  /// Body of the confirmation to delete a section
  ///
  /// In es, this message translates to:
  /// **'Se {count, plural, =1{borra 1 hoja con todo lo que tiene} other{borran {count} hojas con todo lo que tienen}}. No se puede deshacer.'**
  String notebookDeleteSectionBody(int count);

  /// Snackbar when inserting something failed
  ///
  /// In es, this message translates to:
  /// **'No se pudo insertar: {error}'**
  String notebookInsertFailed(String error);

  /// Snackbar when a recording is already running
  ///
  /// In es, this message translates to:
  /// **'Ya hay una grabación en curso'**
  String get notebookRecordingBusy;

  /// Title of the PDF import progress dialog
  ///
  /// In es, this message translates to:
  /// **'Importando PDF'**
  String get notebookImportingPdf;

  /// PDF import dialog: shown while the user picks the file
  ///
  /// In es, this message translates to:
  /// **'Elegí el archivo…'**
  String get notebookPickFile;

  /// Snackbar after importing a PDF
  ///
  /// In es, this message translates to:
  /// **'{count, plural, =1{{count} hoja importada} other{{count} hojas importadas}}'**
  String notebookSheetsImported(int count);

  /// Snackbar after marking the notebook as favorite
  ///
  /// In es, this message translates to:
  /// **'Agregado a favoritos'**
  String get notebookFavoriteAdded;

  /// Snackbar after removing the notebook from favorites
  ///
  /// In es, this message translates to:
  /// **'Quitado de favoritos'**
  String get notebookFavoriteRemoved;

  /// Title of the PIN dialog to remove the lock
  ///
  /// In es, this message translates to:
  /// **'Quitar bloqueo'**
  String get notebookUnlockTitle;

  /// Subtitle of the PIN dialog to remove the lock
  ///
  /// In es, this message translates to:
  /// **'Ingresá el PIN actual'**
  String get notebookUnlockHint;

  /// Snackbar after removing the lock
  ///
  /// In es, this message translates to:
  /// **'Cuaderno desbloqueado'**
  String get notebookUnlocked;

  /// Title of the PIN dialog to lock the notebook
  ///
  /// In es, this message translates to:
  /// **'Bloquear cuaderno'**
  String get notebookLockTitle;

  /// Subtitle of the PIN dialog to lock the notebook
  ///
  /// In es, this message translates to:
  /// **'Elegí un PIN de 4 o más números'**
  String get notebookLockHint;

  /// Snackbar when the PIN is too short
  ///
  /// In es, this message translates to:
  /// **'El PIN tiene que tener al menos 4 números'**
  String get notebookPinShort;

  /// Title of the dialog that asks the PIN again
  ///
  /// In es, this message translates to:
  /// **'Repetí el PIN'**
  String get notebookPinRepeat;

  /// Snackbar when the two PINs differ
  ///
  /// In es, this message translates to:
  /// **'Los PIN no coinciden'**
  String get notebookPinMismatch;

  /// Snackbar after locking the notebook
  ///
  /// In es, this message translates to:
  /// **'Cuaderno bloqueado: se pide el PIN al abrirlo'**
  String get notebookLocked;

  /// Snackbar after exporting the notebook
  ///
  /// In es, this message translates to:
  /// **'Cuaderno guardado'**
  String get notebookSaved;

  /// Snackbar when the export failed
  ///
  /// In es, this message translates to:
  /// **'No se pudo exportar: {error}'**
  String notebookExportFailed(String error);

  /// Name used for the exported file of a single sheet
  ///
  /// In es, this message translates to:
  /// **'{name} - hoja {n}'**
  String notebookSheetFileName(String name, int n);

  /// Snackbar after saving the image of a sheet
  ///
  /// In es, this message translates to:
  /// **'Imagen guardada'**
  String get notebookImageSaved;

  /// Tooltip of the button that leaves full screen
  ///
  /// In es, this message translates to:
  /// **'Salir de pantalla completa'**
  String get notebookFullscreenExit;

  /// Recording indicator text
  ///
  /// In es, this message translates to:
  /// **'Grabando'**
  String get notebookRecording;

  /// Recording indicator text with the name of the audio
  ///
  /// In es, this message translates to:
  /// **'Grabando · {name}'**
  String notebookRecordingNamed(String name);

  /// Tooltip of the button that stops and saves the recording
  ///
  /// In es, this message translates to:
  /// **'Parar y guardar'**
  String get notebookRecordingStop;

  /// Tooltip of the button that cancels the recording
  ///
  /// In es, this message translates to:
  /// **'Cancelar y descartar'**
  String get notebookRecordingCancel;

  /// Snackbar when a web link cannot be opened
  ///
  /// In es, this message translates to:
  /// **'No se pudo abrir el link'**
  String get notebookLinkFailed;

  /// Snackbar when a link points to a sheet that does not exist anymore
  ///
  /// In es, this message translates to:
  /// **'La hoja ya no existe'**
  String get notebookSheetGone;

  /// Tooltip of the back arrow in the notebook
  ///
  /// In es, this message translates to:
  /// **'Volver a los cuadernos'**
  String get notebookBack;

  /// Tooltip of the button that closes the search
  ///
  /// In es, this message translates to:
  /// **'Cerrar búsqueda'**
  String get notebookSearchClose;

  /// Tooltip of the insert (+) button
  ///
  /// In es, this message translates to:
  /// **'Insertar'**
  String get notebookInsert;

  /// Tooltip of the index button
  ///
  /// In es, this message translates to:
  /// **'Índice'**
  String get notebookIndexTooltip;

  /// Tooltip of the sections button
  ///
  /// In es, this message translates to:
  /// **'Secciones'**
  String get notebookSections;

  /// Tooltip of the pages panel button
  ///
  /// In es, this message translates to:
  /// **'Hojas'**
  String get notebookPages;

  /// Tooltip of the notebook overflow button
  ///
  /// In es, this message translates to:
  /// **'Más opciones'**
  String get notebookMore;

  /// Banner shown when another device changed the open notebook
  ///
  /// In es, this message translates to:
  /// **'Hay cambios de otro dispositivo'**
  String get notebookRemoteChanges;

  /// Hint of the notebook search field
  ///
  /// In es, this message translates to:
  /// **'Buscar en \"{name}\"'**
  String notebookSearchIn(String name);

  /// Counter under the notebook title: optional sheet title prefix, current sheet and total
  ///
  /// In es, this message translates to:
  /// **'{title}{n} / {total}'**
  String notebookSheetCounter(String title, int n, int total);

  /// Prefix of the default name of audio recordings (followed by a number), and hint of the audio rename field
  ///
  /// In es, this message translates to:
  /// **'Audio'**
  String get audioPrefix;

  /// Error: a recording is already running
  ///
  /// In es, this message translates to:
  /// **'Ya hay una grabación en curso'**
  String get errVoiceBusy;

  /// Error: the microphone permission is missing
  ///
  /// In es, this message translates to:
  /// **'Sin permiso para usar el micrófono'**
  String get errVoiceNoPermission;

  /// Error: the recording could not start
  ///
  /// In es, this message translates to:
  /// **'No se pudo grabar: {detail}'**
  String errVoiceFailed(String detail);

  /// Title of the dialog that adds a heading to the index
  ///
  /// In es, this message translates to:
  /// **'Agregar al índice'**
  String get headingTitle;

  /// Hint of the heading name field when handwriting recognition failed
  ///
  /// In es, this message translates to:
  /// **'No se pudo leer: escribí el nombre'**
  String get headingFailed;

  /// Hint of the heading name field
  ///
  /// In es, this message translates to:
  /// **'Nombre'**
  String get headingHint;

  /// Heading dialog: the handwriting model is being downloaded
  ///
  /// In es, this message translates to:
  /// **'Bajando el reconocimiento de letra, solo la primera vez (podés escribir el nombre mientras tanto)…'**
  String get headingDownloading;

  /// Heading dialog: the handwriting is being recognized
  ///
  /// In es, this message translates to:
  /// **'Leyendo la letra… (podés escribir el nombre mientras tanto)'**
  String get headingReading;

  /// Tooltip of the button that lowers the heading level number
  ///
  /// In es, this message translates to:
  /// **'Más importante'**
  String get headingMoreImportant;

  /// Tooltip of the button that raises the heading level number
  ///
  /// In es, this message translates to:
  /// **'Menos importante'**
  String get headingLessImportant;

  /// Heading level label
  ///
  /// In es, this message translates to:
  /// **'Título {level}'**
  String headingLevel(int level);

  /// Heading dialog confirm button
  ///
  /// In es, this message translates to:
  /// **'Agregar'**
  String get headingAdd;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Negrita (Ctrl+B)'**
  String get formatBold;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Cursiva (Ctrl+I)'**
  String get formatItalic;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Subrayado (Ctrl+U)'**
  String get formatUnderline;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Tachado (Alt+Shift+5)'**
  String get formatStrike;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Color del texto'**
  String get formatColor;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Resaltado (Ctrl+Shift+H)'**
  String get formatHighlight;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Normal'**
  String get formatNormal;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Título'**
  String get formatTitle;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Subtítulo'**
  String get formatSubtitle;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Viñetas (Ctrl+Shift+8)'**
  String get formatBullets;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Numerada (Ctrl+Shift+7)'**
  String get formatNumbered;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Lista de tareas (Ctrl+Shift+9)'**
  String get formatTodo;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Menos sangría (Shift+Tab)'**
  String get formatOutdent;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Más sangría (Tab)'**
  String get formatIndent;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Alinear a la izquierda (Ctrl+L)'**
  String get formatAlignLeft;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Centrar (Ctrl+E)'**
  String get formatCenter;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Alinear a la derecha (Ctrl+R)'**
  String get formatAlignRight;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Justificar (Ctrl+J)'**
  String get formatJustify;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Achicar letra (Ctrl+[)'**
  String get formatSizeDown;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Agrandar letra (Ctrl+])'**
  String get formatSizeUp;

  /// Text formatting bar: tooltip or label (with its keyboard shortcut when it has one)
  ///
  /// In es, this message translates to:
  /// **'Automático'**
  String get formatSizeAuto;

  /// Bar over a selection that crosses paragraphs: cut
  ///
  /// In es, this message translates to:
  /// **'Cortar'**
  String get formatCut;

  /// Pull-to-add indicator: the sheet was added
  ///
  /// In es, this message translates to:
  /// **'Hoja agregada'**
  String get pullDone;

  /// Pull-to-add indicator: hold to add a sheet
  ///
  /// In es, this message translates to:
  /// **'Mantené para agregar una hoja'**
  String get pullHold;

  /// Tooltip of a tool in the toolbar
  ///
  /// In es, this message translates to:
  /// **'Lápiz · tocá de nuevo para opciones'**
  String get toolPen;

  /// Tooltip of a tool in the toolbar
  ///
  /// In es, this message translates to:
  /// **'Resaltador · tocá de nuevo para opciones'**
  String get toolHighlighter;

  /// Tooltip of a tool in the toolbar
  ///
  /// In es, this message translates to:
  /// **'Decorador · tocá de nuevo para opciones'**
  String get toolPaint;

  /// Tooltip of a tool in the toolbar
  ///
  /// In es, this message translates to:
  /// **'Formas · tocá de nuevo para opciones'**
  String get toolShapes;

  /// Tooltip of a tool in the toolbar
  ///
  /// In es, this message translates to:
  /// **'Texto con teclado'**
  String get toolText;

  /// Tooltip of a tool in the toolbar
  ///
  /// In es, this message translates to:
  /// **'Seleccionar'**
  String get toolSelect;

  /// Tooltip of a tool in the toolbar
  ///
  /// In es, this message translates to:
  /// **'Título para el índice'**
  String get toolTitle;

  /// Toolbar tooltip: undo
  ///
  /// In es, this message translates to:
  /// **'Deshacer'**
  String get toolUndo;

  /// Toolbar tooltip: redo
  ///
  /// In es, this message translates to:
  /// **'Rehacer'**
  String get toolRedo;

  /// Toolbar tooltip when the zoom is locked
  ///
  /// In es, this message translates to:
  /// **'Zoom fijo ({percent}%) · tocá para soltarlo'**
  String toolZoomLocked(int percent);

  /// Toolbar tooltip: lock the zoom
  ///
  /// In es, this message translates to:
  /// **'Fijar el zoom'**
  String get toolZoomLock;

  /// Toolbar tooltip: open the color panel
  ///
  /// In es, this message translates to:
  /// **'Más colores'**
  String get toolMoreColors;

  /// Toolbar tooltip: open the pen options
  ///
  /// In es, this message translates to:
  /// **'Punta, grosor y opacidad'**
  String get toolPenOptions;

  /// Tooltip of the toolbar drag handle
  ///
  /// In es, this message translates to:
  /// **'Arrastrá para mover la barra'**
  String get toolDragBar;

  /// Zoom indicator: percentage
  ///
  /// In es, this message translates to:
  /// **'{percent}%'**
  String zoomIndicator(int percent);

  /// Zoom indicator: percentage when the zoom is locked
  ///
  /// In es, this message translates to:
  /// **'{percent}% · fijo'**
  String zoomIndicatorLocked(int percent);

  /// Selection toolbar: button or menu item
  ///
  /// In es, this message translates to:
  /// **'Orden'**
  String get selOrder;

  /// Selection toolbar: button or menu item
  ///
  /// In es, this message translates to:
  /// **'Traer al frente'**
  String get selFront;

  /// Selection toolbar: button or menu item
  ///
  /// In es, this message translates to:
  /// **'Subir uno'**
  String get selUp;

  /// Selection toolbar: button or menu item
  ///
  /// In es, this message translates to:
  /// **'Bajar uno'**
  String get selDown;

  /// Selection toolbar: button or menu item
  ///
  /// In es, this message translates to:
  /// **'Enviar al fondo'**
  String get selBack;

  /// Selection toolbar: button or menu item
  ///
  /// In es, this message translates to:
  /// **'Duplicar'**
  String get selDuplicate;

  /// Selection toolbar: button or menu item
  ///
  /// In es, this message translates to:
  /// **'Link'**
  String get selLink;

  /// Selection toolbar: button or menu item
  ///
  /// In es, this message translates to:
  /// **'Editar link'**
  String get selEditLink;

  /// Selection toolbar: button or menu item
  ///
  /// In es, this message translates to:
  /// **'Quitar link'**
  String get selRemoveLink;

  /// Selection toolbar: button or menu item
  ///
  /// In es, this message translates to:
  /// **'Enderezar'**
  String get selStraighten;

  /// Selection toolbar: button or menu item
  ///
  /// In es, this message translates to:
  /// **'Eliminar'**
  String get selDelete;

  /// Selection toolbar: button or menu item
  ///
  /// In es, this message translates to:
  /// **'Deseleccionar'**
  String get selDeselect;

  /// Menu shown when long pressing the sheet: paste here
  ///
  /// In es, this message translates to:
  /// **'Pegar acá'**
  String get sheetMenuPaste;

  /// Title of the dialog that creates a link
  ///
  /// In es, this message translates to:
  /// **'Link'**
  String get linkTitle;

  /// Title of the dialog that edits a link
  ///
  /// In es, this message translates to:
  /// **'Editar link'**
  String get linkTitleEdit;

  /// Link dialog: web page option
  ///
  /// In es, this message translates to:
  /// **'Página web'**
  String get linkKindWeb;

  /// Link dialog: sheet option
  ///
  /// In es, this message translates to:
  /// **'Hoja'**
  String get linkKindSheet;

  /// Link dialog: notebook option
  ///
  /// In es, this message translates to:
  /// **'Cuaderno'**
  String get linkKindNotebook;

  /// Hint of the web address field of the link dialog
  ///
  /// In es, this message translates to:
  /// **'dirección, ej. es.wikipedia.org'**
  String get linkUrlHint;

  /// Link dialog: there are no sheets to link
  ///
  /// In es, this message translates to:
  /// **'No hay hojas.'**
  String get linkNoSheets;

  /// Link dialog: there are no other notebooks to link
  ///
  /// In es, this message translates to:
  /// **'No hay otros cuadernos.'**
  String get linkNoNotebooks;

  /// Hint of an empty sticky note
  ///
  /// In es, this message translates to:
  /// **'Nota…'**
  String get stickyHint;

  /// Snackbar when a PDF link points to a page that is not in the notebook
  ///
  /// In es, this message translates to:
  /// **'Esa página no está en el cuaderno'**
  String get editorLinkMissingPage;

  /// Title of the dialog that renames an audio
  ///
  /// In es, this message translates to:
  /// **'Renombrar audio'**
  String get editorRenameAudio;

  /// Hint shown under the last sheet
  ///
  /// In es, this message translates to:
  /// **'Al final, deslizá hacia arriba y mantené para agregar una hoja'**
  String get editorPullHint;

  /// Label of the fast scroller thumb: current sheet out of total
  ///
  /// In es, this message translates to:
  /// **'Hoja {n} de {total}'**
  String editorScrollerLabel(int n, int total);

  /// Snackbar after copying the selection
  ///
  /// In es, this message translates to:
  /// **'Copiado'**
  String get editorCopied;

  /// Placeholder text while a sheet is loading
  ///
  /// In es, this message translates to:
  /// **'Cargando la hoja {n}…'**
  String editorLoadingSheet(int n);

  /// Name of the pen tip "pen" in the pen panel
  ///
  /// In es, this message translates to:
  /// **'Bolígrafo'**
  String get tipPen;

  /// Name of the pen tip "fountain" in the pen panel
  ///
  /// In es, this message translates to:
  /// **'Pluma'**
  String get tipFountain;

  /// Name of the pen tip "pencil" in the pen panel
  ///
  /// In es, this message translates to:
  /// **'Lápiz'**
  String get tipPencil;

  /// Name of the pen tip "fine" in the pen panel
  ///
  /// In es, this message translates to:
  /// **'Fibra'**
  String get tipFine;

  /// Name of the pen tip "calli" in the pen panel
  ///
  /// In es, this message translates to:
  /// **'Caligrafía'**
  String get tipCalligraphy;

  /// Name of the decorator stroke style "brush"
  ///
  /// In es, this message translates to:
  /// **'Pincel'**
  String get paintStyleBrush;

  /// Name of the decorator stroke style "hl"
  ///
  /// In es, this message translates to:
  /// **'Resaltador'**
  String get paintStyleHighlighter;

  /// Name of the decorator stroke style "marker"
  ///
  /// In es, this message translates to:
  /// **'Fibra'**
  String get paintStyleMarker;

  /// Name of the decorator shape "stars"
  ///
  /// In es, this message translates to:
  /// **'Estrellas'**
  String get paintShapeStars;

  /// Name of the decorator shape "hearts"
  ///
  /// In es, this message translates to:
  /// **'Corazones'**
  String get paintShapeHearts;

  /// Name of the decorator shape "sparkles"
  ///
  /// In es, this message translates to:
  /// **'Destellos'**
  String get paintShapeSparkles;

  /// Name of the decorator shape "moons"
  ///
  /// In es, this message translates to:
  /// **'Lunas'**
  String get paintShapeMoons;

  /// Name of the decorator shape "dots"
  ///
  /// In es, this message translates to:
  /// **'Puntos'**
  String get paintShapeDots;

  /// Name of the decorator shape "circles"
  ///
  /// In es, this message translates to:
  /// **'Círculos'**
  String get paintShapeCircles;

  /// Name of the decorator shape "bangs"
  ///
  /// In es, this message translates to:
  /// **'Exclamaciones'**
  String get paintShapeExclamations;

  /// Name of the decorator shape "bolts"
  ///
  /// In es, this message translates to:
  /// **'Rayos'**
  String get paintShapeBolts;

  /// Name of the decorator shape "ticks"
  ///
  /// In es, this message translates to:
  /// **'Ticks'**
  String get paintShapeTicks;

  /// Name of the decorator shape "crosses"
  ///
  /// In es, this message translates to:
  /// **'Cruces'**
  String get paintShapeCrosses;

  /// Name of the decorator shape "clouds"
  ///
  /// In es, this message translates to:
  /// **'Nubes'**
  String get paintShapeClouds;

  /// Name of the decorator shape "bubbles"
  ///
  /// In es, this message translates to:
  /// **'Globos'**
  String get paintShapeBubbles;

  /// Name of the decorator shape "leaves"
  ///
  /// In es, this message translates to:
  /// **'Hojas'**
  String get paintShapeLeaves;

  /// Name of the decorator shape "paws"
  ///
  /// In es, this message translates to:
  /// **'Huellas'**
  String get paintShapePaws;

  /// Name of the decorator shape "triangles"
  ///
  /// In es, this message translates to:
  /// **'Triángulos'**
  String get paintShapeTriangles;

  /// Name of the decorator shape "squares"
  ///
  /// In es, this message translates to:
  /// **'Cuadrados'**
  String get paintShapeSquares;

  /// Name of the decorator shape "diamonds"
  ///
  /// In es, this message translates to:
  /// **'Rombos'**
  String get paintShapeDiamonds;

  /// Name of the decorator shape "flowers"
  ///
  /// In es, this message translates to:
  /// **'Flores'**
  String get paintShapeFlowers;

  /// Name of the decorator shape "notes"
  ///
  /// In es, this message translates to:
  /// **'Notas'**
  String get paintShapeNotes;

  /// Name of the exact shape "line" in the shapes panel
  ///
  /// In es, this message translates to:
  /// **'Recta'**
  String get shapeKindLine;

  /// Name of the exact shape "arrow" in the shapes panel
  ///
  /// In es, this message translates to:
  /// **'Flecha'**
  String get shapeKindArrow;

  /// Name of the exact shape "rect" in the shapes panel
  ///
  /// In es, this message translates to:
  /// **'Rectángulo'**
  String get shapeKindRectangle;

  /// Name of the exact shape "circle" in the shapes panel
  ///
  /// In es, this message translates to:
  /// **'Círculo'**
  String get shapeKindCircle;

  /// Name of the exact shape "ellipse" in the shapes panel
  ///
  /// In es, this message translates to:
  /// **'Elipse'**
  String get shapeKindEllipse;

  /// Name of the exact shape "triangle" in the shapes panel
  ///
  /// In es, this message translates to:
  /// **'Triángulo'**
  String get shapeKindTriangle;

  /// Pen panel: section title of the favorite colors
  ///
  /// In es, this message translates to:
  /// **'Favoritos'**
  String get penFavorites;

  /// Pen panel: help for the favorite colors
  ///
  /// In es, this message translates to:
  /// **'Mantené apretado un favorito para guardar ahí el color actual.'**
  String get penFavHelp;

  /// Pen panel title for the highlighter
  ///
  /// In es, this message translates to:
  /// **'Resaltador'**
  String get penPanelHighlighter;

  /// Pen panel title for the pen
  ///
  /// In es, this message translates to:
  /// **'Lápiz'**
  String get penPanelPencil;

  /// Pen panel: section title of the pen tips
  ///
  /// In es, this message translates to:
  /// **'Punta'**
  String get penTip;

  /// Pen panel: stroke width slider
  ///
  /// In es, this message translates to:
  /// **'Grosor'**
  String get penWidth;

  /// Pen panel: opacity slider
  ///
  /// In es, this message translates to:
  /// **'Opacidad'**
  String get penOpacity;

  /// Pen panel: switch that straightens shapes
  ///
  /// In es, this message translates to:
  /// **'Figuras inteligentes'**
  String get penSmartShapes;

  /// Pen panel: how the smart shapes work
  ///
  /// In es, this message translates to:
  /// **'Mantené el lápiz quieto al terminar una forma'**
  String get penSmartShapesHint;

  /// Pen panel: section title of the colors
  ///
  /// In es, this message translates to:
  /// **'Color'**
  String get penColor;

  /// Pen panel: section title of the eraser size
  ///
  /// In es, this message translates to:
  /// **'Goma (apretá el botón del lápiz)'**
  String get penEraser;

  /// Eraser size: small
  ///
  /// In es, this message translates to:
  /// **'Chica'**
  String get penEraserSmall;

  /// Eraser size: medium
  ///
  /// In es, this message translates to:
  /// **'Mediana'**
  String get penEraserMedium;

  /// Eraser size: large
  ///
  /// In es, this message translates to:
  /// **'Grande'**
  String get penEraserLarge;

  /// Shapes panel title, and decorator switch for shapes
  ///
  /// In es, this message translates to:
  /// **'Formas'**
  String get shapesTitle;

  /// Shapes panel: border section
  ///
  /// In es, this message translates to:
  /// **'Borde'**
  String get shapesBorder;

  /// Shapes panel: how the border is drawn
  ///
  /// In es, this message translates to:
  /// **'El borde usa el color y el grosor del lápiz.'**
  String get shapesBorderHint;

  /// Shapes panel: fill switch
  ///
  /// In es, this message translates to:
  /// **'Relleno'**
  String get shapesFill;

  /// Shapes panel: line and arrow cannot be filled
  ///
  /// In es, this message translates to:
  /// **'La recta y la flecha no se rellenan.'**
  String get shapesNoFill;

  /// Shapes panel: snap to the grid switch
  ///
  /// In es, this message translates to:
  /// **'Pegar a la cuadrícula'**
  String get shapesSnapGrid;

  /// Shapes panel: where snapping applies
  ///
  /// In es, this message translates to:
  /// **'En hojas cuadriculadas, milimetradas, de puntos o con ejes'**
  String get shapesSnapGridHint;

  /// Decorator panel title
  ///
  /// In es, this message translates to:
  /// **'Decorador'**
  String get paintPanelTitle;

  /// Decorator panel: stroke style section
  ///
  /// In es, this message translates to:
  /// **'Trazo'**
  String get paintStroke;

  /// Decorator panel: width slider
  ///
  /// In es, this message translates to:
  /// **'Ancho'**
  String get paintWidth;

  /// Decorator panel: background switch
  ///
  /// In es, this message translates to:
  /// **'Fondo'**
  String get paintBackground;

  /// Decorator panel: glitter switch
  ///
  /// In es, this message translates to:
  /// **'Brillo'**
  String get paintGlitter;

  /// Decorator panel: amount slider
  ///
  /// In es, this message translates to:
  /// **'Cantidad'**
  String get paintAmount;

  /// Decorator panel: automatic shape color
  ///
  /// In es, this message translates to:
  /// **'Auto'**
  String get paintAuto;

  /// Decorator panel: size slider
  ///
  /// In es, this message translates to:
  /// **'Tamaño'**
  String get paintSize;

  /// Measurement label drawn while making a triangle: base and height in millimeters
  ///
  /// In es, this message translates to:
  /// **'base {base} · alto {height} mm'**
  String shapeMeasureTriangle(String base, String height);

  /// Name of the sample notebook created on the first launch (also add the translation to kSampleNotebookNames in domain/notebook.dart)
  ///
  /// In es, this message translates to:
  /// **'Mi cuaderno'**
  String get librarySampleNotebook;

  /// Name given to a notebook found on disk whose own name was lost (library index unreadable); n is a counter
  ///
  /// In es, this message translates to:
  /// **'Cuaderno recuperado {n}'**
  String libraryRecoveredNotebook(int n);

  /// Fallback file name for a notebook without a name (exported files)
  ///
  /// In es, this message translates to:
  /// **'Cuaderno'**
  String get exportFileNotebook;

  /// Fallback file name for a folder without a name (exported files)
  ///
  /// In es, this message translates to:
  /// **'Carpeta'**
  String get exportFileFolder;

  /// Fallback name of a section without a name inside exported file names
  ///
  /// In es, this message translates to:
  /// **'Sección'**
  String get exportFileSection;

  /// Word for "page" inside exported image file names of infinite canvases (lowercase)
  ///
  /// In es, this message translates to:
  /// **'página'**
  String get exportFilePage;

  /// Word for "sheet" inside exported image file names (lowercase)
  ///
  /// In es, this message translates to:
  /// **'hoja'**
  String get exportFileSheet;

  /// Title of the system dialog that saves a PDF
  ///
  /// In es, this message translates to:
  /// **'Guardar PDF'**
  String get exportSavePdf;

  /// Title of the system dialog that saves an image
  ///
  /// In es, this message translates to:
  /// **'Guardar imagen'**
  String get exportSaveImage;

  /// Title of the system dialog that saves several images
  ///
  /// In es, this message translates to:
  /// **'Guardar imágenes'**
  String get exportSaveImages;

  /// Title of the system dialog that saves a notebook file
  ///
  /// In es, this message translates to:
  /// **'Guardar cuaderno'**
  String get exportSaveNotebook;

  /// Title of the system dialog that saves a folder zip
  ///
  /// In es, this message translates to:
  /// **'Guardar carpeta'**
  String get exportSaveFolder;

  /// Title of the settings screen and label of the library menu item that opens it
  ///
  /// In es, this message translates to:
  /// **'Ajustes'**
  String get settingsTitle;

  /// Settings section: languages
  ///
  /// In es, this message translates to:
  /// **'Idioma'**
  String get settingsSectionLanguage;

  /// Settings item: language of the app
  ///
  /// In es, this message translates to:
  /// **'Idioma de la app'**
  String get settingsAppLanguage;

  /// Settings item: language used to read handwriting
  ///
  /// In es, this message translates to:
  /// **'Idioma de la escritura a mano'**
  String get settingsInkLanguage;

  /// Language option: follow the system language
  ///
  /// In es, this message translates to:
  /// **'Como el sistema'**
  String get settingsLanguageSystem;

  /// Handwriting language option: same as the app language
  ///
  /// In es, this message translates to:
  /// **'Igual que la app'**
  String get settingsInkSameAsApp;

  /// Help text under the handwriting language setting
  ///
  /// In es, this message translates to:
  /// **'Se usa para leer los títulos que escribís a mano. Al cambiarlo se baja el modelo nuevo (unos 20 MB) y se borra el anterior.'**
  String get settingsInkHelp;

  /// Settings section: updates
  ///
  /// In es, this message translates to:
  /// **'Actualizaciones'**
  String get settingsSectionUpdates;

  /// Settings item: check for updates now
  ///
  /// In es, this message translates to:
  /// **'Buscar actualizaciones'**
  String get settingsCheckUpdates;

  /// Settings switch: check for updates automatically
  ///
  /// In es, this message translates to:
  /// **'Buscar actualizaciones automáticamente'**
  String get settingsAutoUpdates;

  /// Settings section: about the app
  ///
  /// In es, this message translates to:
  /// **'Acerca de'**
  String get settingsSectionAbout;

  /// Settings item: app version
  ///
  /// In es, this message translates to:
  /// **'Versión'**
  String get settingsVersion;

  /// Settings item: link to the source code
  ///
  /// In es, this message translates to:
  /// **'Código fuente'**
  String get settingsSource;

  /// Settings item: license
  ///
  /// In es, this message translates to:
  /// **'Licencia'**
  String get settingsLicense;

  /// License name shown under the license item
  ///
  /// In es, this message translates to:
  /// **'GPL v3 o posterior'**
  String get settingsLicenseValue;

  /// Settings item: link to the privacy policy
  ///
  /// In es, this message translates to:
  /// **'Política de privacidad'**
  String get settingsPrivacy;

  /// Snackbar while checking for updates
  ///
  /// In es, this message translates to:
  /// **'Buscando actualizaciones…'**
  String get updateChecking;

  /// Snackbar when the update check failed
  ///
  /// In es, this message translates to:
  /// **'No se pudo buscar actualizaciones ahora'**
  String get updateCheckFailed;

  /// Snackbar when the app is up to date
  ///
  /// In es, this message translates to:
  /// **'Ya tenés la última versión'**
  String get updateUpToDate;

  /// Color chooser: tooltip of the palette view button
  ///
  /// In es, this message translates to:
  /// **'Paleta'**
  String get colorViewPalette;

  /// Color chooser: tooltip of the color wheel view button
  ///
  /// In es, this message translates to:
  /// **'Rueda'**
  String get colorViewWheel;

  /// Color chooser: tooltip of the eyedropper button
  ///
  /// In es, this message translates to:
  /// **'Cuentagotas'**
  String get colorEyedropper;

  /// Banner shown over the page while the eyedropper is active
  ///
  /// In es, this message translates to:
  /// **'Tocá la hoja para tomar un color'**
  String get eyedropperHint;

  /// Tooltip of the button that cancels the eyedropper
  ///
  /// In es, this message translates to:
  /// **'Cancelar cuentagotas'**
  String get eyedropperCancel;

  /// Color chooser: caption of the row of recently used colors
  ///
  /// In es, this message translates to:
  /// **'Recientes'**
  String get colorRecent;
}

class _LDelegate extends LocalizationsDelegate<L> {
  const _LDelegate();

  @override
  Future<L> load(Locale locale) {
    return SynchronousFuture<L>(lookupL(locale));
  }

  @override
  bool isSupported(Locale locale) =>
      <String>['en', 'es', 'pt'].contains(locale.languageCode);

  @override
  bool shouldReload(_LDelegate old) => false;
}

L lookupL(Locale locale) {
  // Lookup logic when only language code is specified.
  switch (locale.languageCode) {
    case 'en':
      return LEn();
    case 'es':
      return LEs();
    case 'pt':
      return LPt();
  }

  throw FlutterError(
    'L.delegate failed to load unsupported locale "$locale". This is likely '
    'an issue with the localizations generation tool. Please file an issue '
    'on GitHub with a reproducible sample app and the gen-l10n configuration '
    'that was used.',
  );
}
