// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for English (`en`).
class LEn extends L {
  LEn([String locale = 'en']) : super(locale);

  @override
  String get commonCancel => 'Cancel';

  @override
  String get commonDone => 'Done';

  @override
  String get commonCreate => 'Create';

  @override
  String get commonDelete => 'Delete';

  @override
  String get commonClose => 'Close';

  @override
  String get commonLater => 'Later';

  @override
  String get commonNotNow => 'Not now';

  @override
  String get paperLined => 'Lined';

  @override
  String get paperGrid => 'Grid';

  @override
  String get paperDots => 'Dots';

  @override
  String get paperMm => 'Millimeter';

  @override
  String get paperAxes => 'Cartesian axes';

  @override
  String get paperBlank => 'Blank';

  @override
  String get paperCornell => 'Cornell';

  @override
  String get paperTodo => 'To-do list';

  @override
  String get paperStaff => 'Staff';

  @override
  String get paperWeekly => 'Weekly agenda';

  @override
  String get paperMonthly => 'Monthly calendar';

  @override
  String get shortcutBold => 'Bold';

  @override
  String get shortcutItalic => 'Italic';

  @override
  String get shortcutUnderline => 'Underline';

  @override
  String get shortcutStrike => 'Strikethrough';

  @override
  String get shortcutHighlight => 'Highlight (apply / remove)';

  @override
  String get shortcutFontUp => 'Increase font size';

  @override
  String get shortcutFontDown => 'Decrease font size';

  @override
  String get shortcutBullets => 'Bulleted list';

  @override
  String get shortcutNumbered => 'Numbered list';

  @override
  String get shortcutTodo => 'To-do list';

  @override
  String get shortcutAlignLeft => 'Align left';

  @override
  String get shortcutCenter => 'Center';

  @override
  String get shortcutAlignRight => 'Align right';

  @override
  String get shortcutJustify => 'Justify';

  @override
  String get shortcutIndent => 'Increase indent';

  @override
  String get shortcutOutdent => 'Decrease indent';

  @override
  String get shortcutUndo => 'Undo';

  @override
  String get shortcutRedo => 'Redo';

  @override
  String get shortcutPencil => 'Pen';

  @override
  String get shortcutHighlighter => 'Highlighter';

  @override
  String get shortcutText => 'Text (opens a block)';

  @override
  String get shortcutSelect => 'Select';

  @override
  String get shortcutZoom => 'Zoom';

  @override
  String get shortcutHelp => 'Show these shortcuts';

  @override
  String get shortcutZoomKeys => 'Ctrl + mouse wheel';

  @override
  String get shortcutsTitle => 'Keyboard shortcuts';

  @override
  String get shortcutsTyping => 'Typing';

  @override
  String get shortcutsSheet => 'On the page';

  @override
  String get newNotebookHint => 'E.g.: Analysis II';

  @override
  String get newNotebookTitle => 'New notebook';

  @override
  String get newNotebookSheets => 'Pages';

  @override
  String get newNotebookCanvas => 'Infinite canvas';

  @override
  String get newNotebookCanvasHint =>
      'No breaks, it grows as you write. For concept maps and diagrams';

  @override
  String deleteNotebookTitle(String name) {
    return 'Delete \"$name\"';
  }

  @override
  String deleteNotebookBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '1 page',
    );
    return 'Its $_temp0 will be deleted. This can\'t be undone.';
  }

  @override
  String get pinHint => 'PIN';

  @override
  String get updateAvailableTitle => 'A new version of Vynote is available';

  @override
  String updateNewVersion(String version) {
    return 'New version: $version';
  }

  @override
  String updateVersions(String installed, String version) {
    return 'You have $installed  →  new $version';
  }

  @override
  String get updateNotesTitle => 'What\'s new';

  @override
  String get updateNotesDefault => 'Improvements and miscellaneous fixes.';

  @override
  String get updateSourceInfo =>
      'It\'s downloaded from the project\'s official page on GitHub. Your notebooks aren\'t touched: only the app is updated.';

  @override
  String get updateSkip => 'Skip this version';

  @override
  String get updateInstall => 'Update';

  @override
  String get updateDownloading => 'Downloading the new version';

  @override
  String get updateConnecting => 'Connecting…';

  @override
  String get updateDownloadFailed =>
      'We couldn\'t download the update. Try again in a while.';

  @override
  String get updateStepTitle => 'One more step';

  @override
  String get updatePermissionBody =>
      'Android needs you to allow Vynote to install its own update. It\'s only needed once. We\'ll take you to settings: turn on \"Allow from this source\", come back and tap Update again.';

  @override
  String get updateGoToSettings => 'Go to settings';

  @override
  String get updateDoneTitle => 'Vynote was updated';

  @override
  String updateDoneBody(String version) {
    return 'Version $version is installed. Restart the app to use it.';
  }

  @override
  String get updateRestartNow => 'Restart now';

  @override
  String get updateCancelled => 'Update cancelled.';

  @override
  String get updateManualTitle => 'Install it manually';

  @override
  String get updateManualBody =>
      'We couldn\'t find a way to request administrator permissions. Open a terminal and run:';

  @override
  String get updateCommandCopied => 'Command copied';

  @override
  String get commonCopy => 'Copy';

  @override
  String get updateInstallerFailed =>
      'We couldn\'t open the installer. Try again in a while.';

  @override
  String get updateInstallFailed =>
      'The update couldn\'t be installed. Try again in a while.';

  @override
  String exportPdfSaved(String name) {
    return 'PDF of \"$name\" saved';
  }

  @override
  String get exportPdfGenerating => 'Generating PDF';

  @override
  String exportSheetProgress(int done, int total) {
    return 'Page $done of $total';
  }

  @override
  String exportPdfFailed(String error) {
    return 'The PDF couldn\'t be generated: $error';
  }

  @override
  String get exportImagesGenerating => 'Generating images';

  @override
  String exportImagesFailed(String error) {
    return 'The images couldn\'t be generated: $error';
  }

  @override
  String get exportImagesSaved => 'Images saved';

  @override
  String get exportImageSaved => 'Image saved';

  @override
  String get exportFolderTitle => 'Exporting folder';

  @override
  String exportFolderProgress(int done, int total) {
    return 'Notebook $done of $total';
  }

  @override
  String get exportFolderDone => 'Folder exported';

  @override
  String exportFolderFailed(String error) {
    return 'The folder couldn\'t be exported: $error';
  }

  @override
  String get errImportNotReadable =>
      'The file isn\'t a Vynote notebook (it can\'t be read).';

  @override
  String get errImportNotVynote => 'The file isn\'t a Vynote notebook.';

  @override
  String get errImportNewerVersion =>
      'The file is from a newer version of Vynote. Update the app to open it.';

  @override
  String get errImportBrokenSheetList => 'The page list is broken.';

  @override
  String get errImportNoSheets => 'The notebook has no pages.';

  @override
  String get errImportBrokenSheetAny => 'A page in the file is broken.';

  @override
  String get errImportInvalidNames => 'The file has invalid names.';

  @override
  String get errImportNotZip => 'The file isn\'t a .zip.';

  @override
  String get errImportNoNotebooks =>
      'The .zip has no Vynote notebooks. Did you export it as PDF or PNG?';

  @override
  String errImportMissingFile(String name) {
    return 'The file is missing $name: it\'s broken or isn\'t from Vynote.';
  }

  @override
  String errImportBrokenFile(String name) {
    return '$name is broken.';
  }

  @override
  String errImportBrokenSheet(String name) {
    return 'The page $name is broken.';
  }

  @override
  String get libraryTitle => 'Notebooks';

  @override
  String get libraryHome => 'Home';

  @override
  String get libraryNew => 'New';

  @override
  String get libraryNewNotebook => 'New notebook';

  @override
  String get libraryNewFolder => 'New folder';

  @override
  String get libraryImportNotebook => 'Import .vynote notebook';

  @override
  String get libraryImportFolder => 'Import folder (.zip)';

  @override
  String get libraryMenuTooltip => 'More options';

  @override
  String get libraryUpTooltip => 'Go up one folder';

  @override
  String get librarySearchHint => 'Search notebooks and folders';

  @override
  String get librarySearchClear => 'Clear search';

  @override
  String get libraryEmptyNoResults => 'No results';

  @override
  String get libraryEmptyNone => 'There are no notebooks yet';

  @override
  String get libraryEmptyFolder => 'This folder is empty';

  @override
  String libraryNotebookCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notebooks',
      one: '$count notebook',
    );
    return '$_temp0';
  }

  @override
  String libraryFolderCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count folders',
      one: '$count folder',
    );
    return '$_temp0';
  }

  @override
  String get libraryHeaderFirst => 'Create the first one to get started';

  @override
  String libraryHeaderHint(String parts) {
    return '$parts · press and hold one for options, or drag it into a folder';
  }

  @override
  String get libraryResultsEverywhere => 'Results from all folders';

  @override
  String get libraryNotebookDeleted => 'Notebook deleted';

  @override
  String get libraryNotebookGone => 'The notebook no longer exists';

  @override
  String get libraryLockedNotebook => 'This notebook is locked';

  @override
  String get libraryWrongPin => 'Wrong PIN';

  @override
  String libraryImportedAs(String name) {
    return 'Imported as \"$name\"';
  }

  @override
  String libraryImportFailed(String error) {
    return 'Couldn\'t import: $error';
  }

  @override
  String get libraryImportingFolder => 'Importing folder';

  @override
  String get libraryImportCancelled => 'Import cancelled';

  @override
  String libraryImportUnreadable(int count) {
    return ' ($count couldn\'t be read)';
  }

  @override
  String libraryImportedMany(int count, String fail) {
    return '$count notebooks imported$fail';
  }

  @override
  String libraryImportedFolder(String name, int count, String fail) {
    return 'Folder \"$name\" imported: $count notebooks$fail';
  }

  @override
  String libraryExportDone(String name) {
    return 'Notebook \"$name\" saved';
  }

  @override
  String libraryExportFailed(String error) {
    return 'Couldn\'t export: $error';
  }

  @override
  String get libraryFolderHint => 'E.g.: University';

  @override
  String get libraryRenameNotebook => 'Rename notebook';

  @override
  String get libraryRenameFolder => 'Rename folder';

  @override
  String libraryCopySuffix(String name) {
    return '$name (copy)';
  }

  @override
  String get libraryDuplicated => 'Notebook duplicated';

  @override
  String get libraryFolderEmptyExport => 'The folder is empty';

  @override
  String libraryMoveTitle(String name) {
    return 'Move \"$name\" to…';
  }

  @override
  String libraryMovedTo(String path) {
    return 'Moved to $path';
  }

  @override
  String libraryMovedFolderTo(String path) {
    return 'Moved to $path';
  }

  @override
  String get libraryUndo => 'Undo';

  @override
  String get libraryFolderEmptyBody => 'The folder is empty.';

  @override
  String get libraryDeleteAllTitle => 'Delete everything';

  @override
  String libraryDeleteAllBody(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count notebooks',
      one: '1 notebook',
    );
    return 'The folder \"$name\", its subfolders and $_temp0 with all their pages will be deleted. This can\'t be undone.';
  }

  @override
  String get libraryFolderWhatToDo => 'What should we do with what\'s inside?';

  @override
  String libraryFolderKeep(String parent) {
    return 'Move the notebooks to $parent';
  }

  @override
  String get libraryOptRename => 'Rename';

  @override
  String get libraryOptMove => 'Move to…';

  @override
  String get libraryOptExport => 'Export';

  @override
  String get libraryOptDelete => 'Delete';

  @override
  String get libraryOptOpen => 'Open';

  @override
  String get libraryOptDuplicate => 'Duplicate';

  @override
  String librarySheetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return '$_temp0';
  }

  @override
  String get moveHere => 'here';

  @override
  String get syncIndicatorSynced => 'Synced';

  @override
  String get syncIndicatorSyncing => 'Syncing';

  @override
  String get syncIndicatorPending => 'Changes to upload';

  @override
  String get syncIndicatorOffline => 'No connection';

  @override
  String get syncIndicatorError => 'Sync error';

  @override
  String dateToday(String time) {
    return 'Today $time';
  }

  @override
  String dateYesterday(String time) {
    return 'Yesterday $time';
  }

  @override
  String get datePatternTime => 'h:mm a';

  @override
  String get datePatternDayMonth => 'MMM d';

  @override
  String get datePatternDayMonthYear => 'MMM d, y';

  @override
  String get syncErrOffline => 'No connection';

  @override
  String get syncErrAuthExpired =>
      'Your Google session expired. Connect again.';

  @override
  String get syncErrConflict =>
      'The file changed in the cloud while it was uploading; it will be retried';

  @override
  String get syncErrNotFound => 'It doesn\'t exist in the cloud';

  @override
  String get syncErrVaultChanged => 'The cloud encryption settings changed';

  @override
  String get syncErrCryptoLocked =>
      'The cloud is encrypted: enter the passphrase in Sync > Encryption';

  @override
  String get syncErrWrongPassphrase => 'The passphrase is wrong';

  @override
  String get syncErrCryptoOtherDevice =>
      'Another device turned on encryption at the same time. Enter its passphrase.';

  @override
  String get syncErrCloudNotEncrypted => 'The cloud isn\'t encrypted';

  @override
  String get syncErrConnectFirst => 'Connect with Google first';

  @override
  String get syncErrBackgroundBusy =>
      'A background sync is in progress; try again in a few seconds';

  @override
  String syncErrFilesFailed(String count) {
    return '$count file(s) couldn\'t be synced; it will be retried on the next pass';
  }

  @override
  String syncErrCouldNotSync(String detail) {
    return 'Couldn\'t sync: $detail';
  }

  @override
  String get syncAgoNow => 'just now';

  @override
  String syncAgoMinutes(int count) {
    return '$count min ago';
  }

  @override
  String syncAgoHours(int count) {
    return '$count h ago';
  }

  @override
  String syncAgoDays(int count) {
    return '$count d ago';
  }

  @override
  String syncNotConfigured(String missing) {
    return 'This version doesn\'t have Google access configured (missing: $missing). Notes are still saved on this device.';
  }

  @override
  String get syncDisconnectedStatus =>
      'Not connected. Notebooks are saved only on this device.';

  @override
  String get syncConnecting => 'Connecting to Google…';

  @override
  String get syncSyncing => 'Syncing…';

  @override
  String syncConnectedAs(String account, String last) {
    return 'Connected as $account\n$last';
  }

  @override
  String get syncNever => 'Not synced yet';

  @override
  String syncLast(String ago) {
    return 'Last sync: $ago';
  }

  @override
  String get syncTitle => 'Sync with Google Drive';

  @override
  String syncConflicts(int count) {
    return 'There were $count conflict(s): look for the pages \"(conflict)\" and keep the one that works.';
  }

  @override
  String get syncBackgroundTitle => 'Sync in the background';

  @override
  String get syncBackgroundSubtitle =>
      'Every 15 minutes when there\'s a connection, even if the app is closed.';

  @override
  String get syncConnect => 'Connect with Google';

  @override
  String get syncNow => 'Sync now';

  @override
  String get syncDisconnect => 'Disconnect';

  @override
  String get cryptoStatusUnknown =>
      'Not known yet: it will show at the next sync.';

  @override
  String get cryptoStatusOff =>
      'Off: Google can read what is uploaded to your Drive.';

  @override
  String get cryptoStatusOn =>
      'On: the Drive only holds files encrypted with your passphrase.';

  @override
  String get cryptoStatusLocked =>
      'The cloud is encrypted. Enter the passphrase to sync.';

  @override
  String get cryptoTitle => 'Encryption';

  @override
  String get cryptoWarning =>
      'If you forget the passphrase, there\'s no way to recover what\'s in the cloud (what\'s on this device is not lost). File names on Drive are random codes and stay visible.';

  @override
  String get cryptoEnable => 'Turn on encryption';

  @override
  String get cryptoEnterPass => 'Enter passphrase';

  @override
  String get cryptoDisableTitle => 'Turn off encryption?';

  @override
  String get cryptoDisableBody =>
      'Everything is uploaded again unencrypted and the encrypted data is deleted from Drive. It may take a while if there are many files.';

  @override
  String get cryptoDisableConfirm => 'Turn off';

  @override
  String get cryptoDisable => 'Turn off encryption';

  @override
  String get cryptoPassTitle => 'Passphrase';

  @override
  String get cryptoPassIntro =>
      'Choose a passphrase and write it down somewhere safe. If you forget it, there\'s no way to recover what\'s in the cloud (what\'s on this device is not lost). Everything will be uploaded encrypted and the previous data deleted from Drive.';

  @override
  String get cryptoPassLabel => 'Passphrase';

  @override
  String get cryptoPassRepeat => 'Repeat the passphrase';

  @override
  String get cryptoPassMismatch => 'The two passphrases don\'t match.';

  @override
  String get cryptoActivate => 'Turn on';

  @override
  String get cryptoUnlock => 'Unlock';

  @override
  String cryptoPassShort(int min) {
    return 'The passphrase must be at least $min characters long.';
  }

  @override
  String get cryptoStepDeriving =>
      'Deriving the key (this may take a few seconds)…';

  @override
  String get cryptoStepSyncBeforeEncrypt => 'Syncing before encrypting…';

  @override
  String get cryptoStepSyncBeforeDecrypt => 'Syncing before decrypting…';

  @override
  String cryptoStepEncrypting(int done, int total) {
    return 'Encrypting $done/$total…';
  }

  @override
  String cryptoStepDecrypting(int done, int total) {
    return 'Decrypting $done/$total…';
  }

  @override
  String get commonRename => 'Rename';

  @override
  String get commonExport => 'Export';

  @override
  String get commonSave => 'Save';

  @override
  String get commonUpdate => 'Update';

  @override
  String get commonSearch => 'Search';

  @override
  String sheetLabel(int n) {
    return 'Page $n';
  }

  @override
  String sheetLabelTitled(int n, String title) {
    return 'Page $n · $title';
  }

  @override
  String sheetCountPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages',
      one: '$count page',
    );
    return '$_temp0';
  }

  @override
  String get menuInsertPdf => 'PDF';

  @override
  String get menuInsertVoice => 'Voice recording';

  @override
  String get menuInsertImage => 'Image';

  @override
  String get menuInsertCamera => 'Camera';

  @override
  String get menuInsertAudio => 'Audio file';

  @override
  String get menuInsertSticky => 'Sticky note';

  @override
  String get menuInsertSheet => 'New page';

  @override
  String get menuMoreReadingExit => 'Exit reading mode';

  @override
  String get menuMoreReading => 'Reading mode';

  @override
  String get menuMoreBookmarkRemove => 'Remove bookmark';

  @override
  String get menuMoreBookmarkAdd => 'Bookmark this page';

  @override
  String get menuMoreFullscreen => 'Full screen';

  @override
  String get menuMoreStyle => 'Page style';

  @override
  String get menuMorePaperColor => 'Paper color';

  @override
  String get menuMoreShortcuts => 'Keyboard shortcuts';

  @override
  String get menuMoreFavoriteRemove => 'Remove from favorites';

  @override
  String get menuMoreFavoriteAdd => 'Favorite';

  @override
  String get menuMoreLockRemove => 'Remove lock';

  @override
  String get menuMoreLockAdd => 'Lock with PIN';

  @override
  String get menuMoreShare => 'Share';

  @override
  String get menuMorePrint => 'Print';

  @override
  String get menuMoreDeleteNotebook => 'Delete notebook';

  @override
  String get menuExportFolderTitle => 'Export folder';

  @override
  String get menuExportFolderPdf => 'One PDF per notebook';

  @override
  String get menuExportFolderPng =>
      'One folder per notebook, with one image per page';

  @override
  String get menuExportFolderVynote =>
      'One .vynote per notebook, to move to another device';

  @override
  String get menuExportFormatPdf => 'PDF';

  @override
  String get menuExportFormatPng => 'Images (PNG)';

  @override
  String get menuExportFormatVynote => 'Vynote';

  @override
  String get menuExportBackground => 'Include the page background';

  @override
  String get menuExportBackgroundOff => 'Off: only what\'s written, on white';

  @override
  String get menuExportAllPdf => 'Whole notebook';

  @override
  String get menuExportAllPng => 'All pages, in a .zip';

  @override
  String get menuExportVynoteTitle => 'Vynote notebook (.vynote)';

  @override
  String get menuExportVynoteHint =>
      'To move to another device or make a backup';

  @override
  String get menuExportSheetPdf => 'PDF of this page';

  @override
  String get menuExportSheetPng => 'Image of this page (PNG)';

  @override
  String get sectionNew => 'New section';

  @override
  String get sectionOptions => 'Section options';

  @override
  String get sectionUp => 'Up';

  @override
  String get sectionDown => 'Down';

  @override
  String get sectionExportTitle => 'Which sections to export?';

  @override
  String get sectionAll => 'All';

  @override
  String get indexTitle => 'Index';

  @override
  String get indexEmpty =>
      'There are no titles yet.\nUse the Title tool in the toolbar to mark what you wrote.';

  @override
  String indexLevelUp(int level) {
    return 'Change to Title $level';
  }

  @override
  String indexLevelDown(int level) {
    return 'Change to Title $level';
  }

  @override
  String get indexRemove => 'Remove from index';

  @override
  String get indexRenameTitle => 'Rename title';

  @override
  String get searchHint => 'Search texts, sticky notes and page titles';

  @override
  String searchNone(String query) {
    return 'No results for \"$query\"';
  }

  @override
  String searchTitleSnippet(String title) {
    return 'Title: $title';
  }

  @override
  String get paperColorIvory => 'Ivory';

  @override
  String get paperColorWhite => 'White';

  @override
  String get paperColorCream => 'Cream';

  @override
  String get paperColorGray => 'Gray';

  @override
  String get paperColorLightBlue => 'Light blue';

  @override
  String get paperColorGreen => 'Green';

  @override
  String styleDeleteTemplate(String name) {
    return 'Delete the template «$name»?';
  }

  @override
  String get styleSize => 'Size';

  @override
  String get styleBackground => 'Background';

  @override
  String get styleTemplates => 'Templates';

  @override
  String get styleMyTemplates => 'My templates';

  @override
  String get styleFromImage => 'From an image…';

  @override
  String get styleSpacingLined => 'Line spacing';

  @override
  String get styleSpacingGrid => 'Grid';

  @override
  String get styleApplyTo => 'Apply to';

  @override
  String get styleThisSheet => 'This page';

  @override
  String get styleWholeNotebook => 'Whole notebook';

  @override
  String get styleTitleNew => 'New page';

  @override
  String get styleTitle => 'Page style';

  @override
  String get styleApply => 'Apply';

  @override
  String get pagesAll => 'See all';

  @override
  String get pagesOnlyBookmarked => 'Bookmarked only';

  @override
  String get pagesNewAfter => 'New page after the current one';

  @override
  String get pagesNoBookmarks => 'There are no bookmarked pages';

  @override
  String get pagesNoBookmarksHint =>
      'There are no bookmarked pages. Use the bookmark button above to mark the page you\'re viewing.';

  @override
  String get pagesBookmark => 'Bookmark';

  @override
  String get pagesDragToMove => 'Drag to move';

  @override
  String get pagesNewAfterMenu => 'New page after';

  @override
  String get pagesNewWithTemplate => 'New page with template…';

  @override
  String get pagesDuplicate => 'Duplicate';

  @override
  String get pagesSaveTemplate => 'Save as template';

  @override
  String get pagesMoveBefore => 'Move before';

  @override
  String get pagesMoveAfter => 'Move after';

  @override
  String notebookTemplateDefault(int n) {
    return 'Template $n';
  }

  @override
  String notebookTemplateFailed(String error) {
    return 'The template couldn\'t be saved: $error';
  }

  @override
  String get notebookTemplateSaved => 'Template saved';

  @override
  String get notebookTemplateName => 'Name';

  @override
  String notebookSheetNameTitle(int n) {
    return 'Name of page $n';
  }

  @override
  String get notebookOptional => 'Optional';

  @override
  String get notebookLastSheet => 'The notebook\'s only page can\'t be deleted';

  @override
  String notebookDeleteSheetTitle(int n) {
    return 'Delete page $n';
  }

  @override
  String get notebookDeleteSheetBody =>
      'The page is deleted with everything on it (this can be undone).';

  @override
  String notebookSheetReadFailed(String error) {
    return 'The page couldn\'t be read: $error';
  }

  @override
  String get notebookBookmarkTitle => 'Bookmark';

  @override
  String get notebookBookmarkHint => 'Name (optional)';

  @override
  String get notebookBookmarkNoName => 'Untitled';

  @override
  String notebookSectionOpenFailed(String error) {
    return 'The section couldn\'t be opened: $error';
  }

  @override
  String notebookSectionDefault(int n) {
    return 'Section $n';
  }

  @override
  String get notebookSectionHint => 'E.g.: Practice';

  @override
  String get notebookSectionRename => 'Rename section';

  @override
  String get notebookLastSection =>
      'The notebook\'s only section can\'t be deleted';

  @override
  String notebookDeleteSectionTitle(String name) {
    return 'Delete section \"$name\"';
  }

  @override
  String notebookDeleteSectionBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages with everything on them will be deleted',
      one: '1 page with everything on it will be deleted',
    );
    return '$_temp0. This can\'t be undone.';
  }

  @override
  String notebookInsertFailed(String error) {
    return 'Couldn\'t insert: $error';
  }

  @override
  String get notebookRecordingBusy => 'A recording is already in progress';

  @override
  String get notebookImportingPdf => 'Importing PDF';

  @override
  String get notebookPickFile => 'Choose the file…';

  @override
  String notebookSheetsImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pages imported',
      one: '$count page imported',
    );
    return '$_temp0';
  }

  @override
  String get notebookFavoriteAdded => 'Added to favorites';

  @override
  String get notebookFavoriteRemoved => 'Removed from favorites';

  @override
  String get notebookUnlockTitle => 'Remove lock';

  @override
  String get notebookUnlockHint => 'Enter the current PIN';

  @override
  String get notebookUnlocked => 'Notebook unlocked';

  @override
  String get notebookLockTitle => 'Lock notebook';

  @override
  String get notebookLockHint => 'Choose a PIN of 4 or more digits';

  @override
  String get notebookPinShort => 'The PIN must have at least 4 digits';

  @override
  String get notebookPinRepeat => 'Repeat the PIN';

  @override
  String get notebookPinMismatch => 'The PINs don\'t match';

  @override
  String get notebookLocked =>
      'Notebook locked: the PIN is asked for when it\'s opened';

  @override
  String get notebookSaved => 'Notebook saved';

  @override
  String notebookExportFailed(String error) {
    return 'Couldn\'t export: $error';
  }

  @override
  String notebookSheetFileName(String name, int n) {
    return '$name - page $n';
  }

  @override
  String get notebookImageSaved => 'Image saved';

  @override
  String get notebookFullscreenExit => 'Exit full screen';

  @override
  String get notebookRecording => 'Recording';

  @override
  String notebookRecordingNamed(String name) {
    return 'Recording · $name';
  }

  @override
  String get notebookRecordingStop => 'Stop and save';

  @override
  String get notebookRecordingCancel => 'Cancel and discard';

  @override
  String get notebookLinkFailed => 'The link couldn\'t be opened';

  @override
  String get notebookSheetGone => 'The page no longer exists';

  @override
  String get notebookBack => 'Back to notebooks';

  @override
  String get notebookSearchClose => 'Close search';

  @override
  String get notebookInsert => 'Insert';

  @override
  String get notebookIndexTooltip => 'Index';

  @override
  String get notebookSections => 'Sections';

  @override
  String get notebookPages => 'Pages';

  @override
  String get notebookMore => 'More options';

  @override
  String get notebookRemoteChanges => 'There are changes from another device';

  @override
  String notebookSearchIn(String name) {
    return 'Search in \"$name\"';
  }

  @override
  String notebookSheetCounter(int n, int total) {
    return '$n / $total';
  }

  @override
  String get audioPrefix => 'Audio';

  @override
  String get errVoiceBusy => 'A recording is already in progress';

  @override
  String get errVoiceNoPermission => 'No permission to use the microphone';

  @override
  String errVoiceFailed(String detail) {
    return 'Couldn\'t record: $detail';
  }

  @override
  String get headingTitle => 'Add to index';

  @override
  String get headingFailed => 'Couldn\'t read it: type the name';

  @override
  String get headingHint => 'Name';

  @override
  String get headingDownloading =>
      'Downloading the handwriting recognizer, only the first time (you can type the name in the meantime)…';

  @override
  String get headingReading =>
      'Reading the handwriting… (you can type the name in the meantime)';

  @override
  String get headingMoreImportant => 'More important';

  @override
  String get headingLessImportant => 'Less important';

  @override
  String headingLevel(int level) {
    return 'Title $level';
  }

  @override
  String get headingAdd => 'Add';

  @override
  String get formatBold => 'Bold (Ctrl+B)';

  @override
  String get formatItalic => 'Italic (Ctrl+I)';

  @override
  String get formatUnderline => 'Underline (Ctrl+U)';

  @override
  String get formatStrike => 'Strikethrough (Alt+Shift+5)';

  @override
  String get formatColor => 'Text color';

  @override
  String get formatHighlight => 'Highlight (Ctrl+Shift+H)';

  @override
  String get formatNormal => 'Normal';

  @override
  String get formatTitle => 'Title';

  @override
  String get formatSubtitle => 'Subtitle';

  @override
  String get formatBullets => 'Bulleted (Ctrl+Shift+8)';

  @override
  String get formatNumbered => 'Numbered (Ctrl+Shift+7)';

  @override
  String get formatTodo => 'To-do list (Ctrl+Shift+9)';

  @override
  String get formatOutdent => 'Decrease indent (Shift+Tab)';

  @override
  String get formatIndent => 'Increase indent (Tab)';

  @override
  String get formatAlignLeft => 'Align left (Ctrl+L)';

  @override
  String get formatCenter => 'Center (Ctrl+E)';

  @override
  String get formatAlignRight => 'Align right (Ctrl+R)';

  @override
  String get formatJustify => 'Justify (Ctrl+J)';

  @override
  String get formatSizeDown => 'Decrease font size (Ctrl+[)';

  @override
  String get formatSizeUp => 'Increase font size (Ctrl+])';

  @override
  String get formatSizeAuto => 'Automatic';

  @override
  String get formatCut => 'Cut';

  @override
  String get pullDone => 'Page added';

  @override
  String get pullHold => 'Hold to add a page';

  @override
  String get toolPen => 'Pen · tap again for options';

  @override
  String get toolHighlighter => 'Highlighter · tap again for options';

  @override
  String get toolPaint => 'Decorator · tap again for options';

  @override
  String get toolShapes => 'Shapes · tap again for options';

  @override
  String get toolText => 'Text with keyboard';

  @override
  String get toolSelect => 'Select';

  @override
  String get toolTitle => 'Title for the index';

  @override
  String get toolUndo => 'Undo';

  @override
  String get toolRedo => 'Redo';

  @override
  String toolZoomLocked(int percent) {
    return 'Zoom locked ($percent%) · tap to release';
  }

  @override
  String get toolZoomLock => 'Lock zoom';

  @override
  String get toolMoreColors => 'More colors';

  @override
  String get toolPenOptions => 'Tip, width and opacity';

  @override
  String get toolDragBar => 'Drag to move the bar';

  @override
  String zoomIndicator(int percent) {
    return '$percent%';
  }

  @override
  String zoomIndicatorLocked(int percent) {
    return '$percent% · locked';
  }

  @override
  String get selOrder => 'Order';

  @override
  String get selFront => 'Bring to front';

  @override
  String get selUp => 'Move up one';

  @override
  String get selDown => 'Move down one';

  @override
  String get selBack => 'Send to back';

  @override
  String get selDuplicate => 'Duplicate';

  @override
  String get selLink => 'Link';

  @override
  String get selEditLink => 'Edit link';

  @override
  String get selRemoveLink => 'Remove link';

  @override
  String get selStraighten => 'Straighten';

  @override
  String get selDelete => 'Delete';

  @override
  String get selDeselect => 'Deselect';

  @override
  String get sheetMenuPaste => 'Paste here';

  @override
  String get linkTitle => 'Link';

  @override
  String get linkTitleEdit => 'Edit link';

  @override
  String get linkKindWeb => 'Web page';

  @override
  String get linkKindSheet => 'Page';

  @override
  String get linkKindNotebook => 'Notebook';

  @override
  String get linkUrlHint => 'address, e.g. en.wikipedia.org';

  @override
  String get linkNoSheets => 'There are no pages.';

  @override
  String get linkNoNotebooks => 'There are no other notebooks.';

  @override
  String get stickyHint => 'Note…';

  @override
  String get editorLinkMissingPage => 'That page isn\'t in the notebook';

  @override
  String get editorRenameAudio => 'Rename audio';

  @override
  String get editorPullHint => 'At the end, swipe up and hold to add a page';

  @override
  String editorScrollerLabel(int n, int total) {
    return 'Page $n of $total';
  }

  @override
  String get editorCopied => 'Copied';

  @override
  String editorLoadingSheet(int n) {
    return 'Loading page $n…';
  }

  @override
  String get tipPen => 'Ballpoint';

  @override
  String get tipFountain => 'Fountain pen';

  @override
  String get tipPencil => 'Pencil';

  @override
  String get tipFine => 'Fineliner';

  @override
  String get tipCalligraphy => 'Calligraphy';

  @override
  String get paintStyleBrush => 'Brush';

  @override
  String get paintStyleHighlighter => 'Highlighter';

  @override
  String get paintStyleMarker => 'Marker';

  @override
  String get paintShapeStars => 'Stars';

  @override
  String get paintShapeHearts => 'Hearts';

  @override
  String get paintShapeSparkles => 'Sparkles';

  @override
  String get paintShapeMoons => 'Moons';

  @override
  String get paintShapeDots => 'Dots';

  @override
  String get paintShapeCircles => 'Circles';

  @override
  String get paintShapeExclamations => 'Exclamation marks';

  @override
  String get paintShapeBolts => 'Lightning bolts';

  @override
  String get paintShapeTicks => 'Checkmarks';

  @override
  String get paintShapeCrosses => 'Crosses';

  @override
  String get paintShapeClouds => 'Clouds';

  @override
  String get paintShapeBubbles => 'Bubbles';

  @override
  String get paintShapeLeaves => 'Leaves';

  @override
  String get paintShapePaws => 'Paw prints';

  @override
  String get paintShapeTriangles => 'Triangles';

  @override
  String get paintShapeSquares => 'Squares';

  @override
  String get paintShapeDiamonds => 'Diamonds';

  @override
  String get paintShapeFlowers => 'Flowers';

  @override
  String get paintShapeNotes => 'Music notes';

  @override
  String get shapeKindLine => 'Line';

  @override
  String get shapeKindArrow => 'Arrow';

  @override
  String get shapeKindRectangle => 'Rectangle';

  @override
  String get shapeKindCircle => 'Circle';

  @override
  String get shapeKindEllipse => 'Ellipse';

  @override
  String get shapeKindTriangle => 'Triangle';

  @override
  String get penFavorites => 'Favorites';

  @override
  String get penFavHelp =>
      'Tap a favorite and change its color with the wheel. Press and hold it to delete it.';

  @override
  String get penFavAdd => 'Add color';

  @override
  String get penFavDelete => 'Delete color';

  @override
  String get penPanelHighlighter => 'Highlighter';

  @override
  String get penPanelPencil => 'Pen';

  @override
  String get penTip => 'Tip';

  @override
  String get penWidth => 'Width';

  @override
  String get penOpacity => 'Opacity';

  @override
  String get penSmartShapes => 'Smart shapes';

  @override
  String get penSmartShapesHint => 'Hold the pen still at the end of a shape';

  @override
  String get penColor => 'Color';

  @override
  String get penEraser => 'Eraser (press the pen button)';

  @override
  String get penEraserSmall => 'Small';

  @override
  String get penEraserMedium => 'Medium';

  @override
  String get penEraserLarge => 'Large';

  @override
  String get shapesTitle => 'Shapes';

  @override
  String get shapesBorder => 'Border';

  @override
  String get shapesBorderHint => 'The border uses the pen\'s color and width.';

  @override
  String get shapesFill => 'Fill';

  @override
  String get shapesNoFill => 'Lines and arrows aren\'t filled.';

  @override
  String get shapesSnapGrid => 'Snap to grid';

  @override
  String get shapesSnapGridHint => 'On grid, millimeter, dot or axis pages';

  @override
  String get paintPanelTitle => 'Decorator';

  @override
  String get paintStroke => 'Stroke';

  @override
  String get paintWidth => 'Width';

  @override
  String get paintBackground => 'Background';

  @override
  String get paintGlitter => 'Shine';

  @override
  String get paintAmount => 'Amount';

  @override
  String get paintAuto => 'Auto';

  @override
  String get paintSize => 'Size';

  @override
  String shapeMeasureTriangle(String base, String height) {
    return 'base $base · height $height mm';
  }

  @override
  String get librarySampleNotebook => 'My notebook';

  @override
  String libraryRecoveredNotebook(int n) {
    return 'Recovered notebook $n';
  }

  @override
  String get exportFileNotebook => 'Notebook';

  @override
  String get exportFileFolder => 'Folder';

  @override
  String get exportFileSection => 'Section';

  @override
  String get exportFilePage => 'page';

  @override
  String get exportFileSheet => 'page';

  @override
  String get exportSavePdf => 'Save PDF';

  @override
  String get exportSaveImage => 'Save image';

  @override
  String get exportSaveImages => 'Save images';

  @override
  String get exportSaveNotebook => 'Save notebook';

  @override
  String get exportSaveFolder => 'Save folder';

  @override
  String get settingsTitle => 'Settings';

  @override
  String get settingsSectionLanguage => 'Language';

  @override
  String get settingsAppLanguage => 'App language';

  @override
  String get settingsInkLanguage => 'Handwriting language';

  @override
  String get settingsLanguageSystem => 'Same as system';

  @override
  String get settingsInkSameAsApp => 'Same as app';

  @override
  String get settingsInkHelp =>
      'It\'s used to read the titles you write by hand. When you change it, the new model is downloaded (about 20 MB) and the previous one is deleted.';

  @override
  String get settingsSectionUpdates => 'Updates';

  @override
  String get settingsCheckUpdates => 'Check for updates';

  @override
  String get settingsAutoUpdates => 'Check for updates automatically';

  @override
  String get settingsSectionAbout => 'About';

  @override
  String get settingsVersion => 'Version';

  @override
  String get settingsSource => 'Source code';

  @override
  String get settingsLicense => 'License';

  @override
  String get settingsLicenseValue => 'GPL v3 or later';

  @override
  String get settingsPrivacy => 'Privacy policy';

  @override
  String get updateChecking => 'Checking for updates…';

  @override
  String get updateCheckFailed => 'Couldn\'t check for updates right now';

  @override
  String get updateUpToDate => 'You have the latest version';

  @override
  String get colorEyedropper => 'Eyedropper';

  @override
  String get eyedropperHint => 'Tap the page to pick a color';

  @override
  String get eyedropperCancel => 'Cancel eyedropper';
}
