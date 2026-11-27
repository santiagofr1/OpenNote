// ignore: unused_import
import 'package:intl/intl.dart' as intl;

import 'app_localizations.dart';

// ignore_for_file: type=lint

/// The translations for Portuguese (`pt`).
class LPt extends L {
  LPt([String locale = 'pt']) : super(locale);

  @override
  String get commonCancel => 'Cancelar';

  @override
  String get commonDone => 'Concluído';

  @override
  String get commonCreate => 'Criar';

  @override
  String get commonDelete => 'Excluir';

  @override
  String get commonClose => 'Fechar';

  @override
  String get commonLater => 'Depois';

  @override
  String get commonNotNow => 'Agora não';

  @override
  String get paperLined => 'Pautado';

  @override
  String get paperGrid => 'Quadriculado';

  @override
  String get paperDots => 'Pontilhado';

  @override
  String get paperMm => 'Milimetrado';

  @override
  String get paperAxes => 'Eixos cartesianos';

  @override
  String get paperBlank => 'Liso';

  @override
  String get paperCornell => 'Cornell';

  @override
  String get paperTodo => 'Lista de tarefas';

  @override
  String get paperStaff => 'Pauta musical';

  @override
  String get paperWeekly => 'Agenda semanal';

  @override
  String get paperMonthly => 'Calendário mensal';

  @override
  String get shortcutBold => 'Negrito';

  @override
  String get shortcutItalic => 'Itálico';

  @override
  String get shortcutUnderline => 'Sublinhado';

  @override
  String get shortcutStrike => 'Tachado';

  @override
  String get shortcutHighlight => 'Destaque (aplicar / remover)';

  @override
  String get shortcutFontUp => 'Aumentar fonte';

  @override
  String get shortcutFontDown => 'Diminuir fonte';

  @override
  String get shortcutBullets => 'Lista com marcadores';

  @override
  String get shortcutNumbered => 'Lista numerada';

  @override
  String get shortcutTodo => 'Lista de tarefas';

  @override
  String get shortcutAlignLeft => 'Alinhar à esquerda';

  @override
  String get shortcutCenter => 'Centralizar';

  @override
  String get shortcutAlignRight => 'Alinhar à direita';

  @override
  String get shortcutJustify => 'Justificar';

  @override
  String get shortcutIndent => 'Aumentar recuo';

  @override
  String get shortcutOutdent => 'Diminuir recuo';

  @override
  String get shortcutUndo => 'Desfazer';

  @override
  String get shortcutRedo => 'Refazer';

  @override
  String get shortcutPencil => 'Caneta';

  @override
  String get shortcutHighlighter => 'Marca-texto';

  @override
  String get shortcutText => 'Texto (abre um bloco)';

  @override
  String get shortcutSelect => 'Selecionar';

  @override
  String get shortcutZoom => 'Zoom';

  @override
  String get shortcutHelp => 'Ver estes atalhos';

  @override
  String get shortcutZoomKeys => 'Ctrl + roda do mouse';

  @override
  String get shortcutsTitle => 'Atalhos de teclado';

  @override
  String get shortcutsTyping => 'Digitando';

  @override
  String get shortcutsSheet => 'Na página';

  @override
  String get newNotebookHint => 'Ex.: Análise II';

  @override
  String get newNotebookTitle => 'Novo caderno';

  @override
  String get newNotebookSheets => 'Páginas';

  @override
  String get newNotebookCanvas => 'Tela infinita';

  @override
  String get newNotebookCanvasHint =>
      'Sem quebras, cresce conforme você escreve. Para mapas conceituais e diagramas';

  @override
  String deleteNotebookTitle(String name) {
    return 'Excluir \"$name\"';
  }

  @override
  String deleteNotebookBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '1 página',
    );
    return 'Suas $_temp0 serão excluídas. Isso não pode ser desfeito.';
  }

  @override
  String get pinHint => 'PIN';

  @override
  String get updateAvailableTitle => 'Há uma nova versão do Vynote';

  @override
  String updateNewVersion(String version) {
    return 'Nova versão: $version';
  }

  @override
  String updateVersions(String installed, String version) {
    return 'Você tem a $installed  →  nova $version';
  }

  @override
  String get updateNotesTitle => 'Novidades';

  @override
  String get updateNotesDefault => 'Melhorias e correções diversas.';

  @override
  String get updateSourceInfo =>
      'Baixada da página oficial do projeto no GitHub. Seus cadernos não são alterados: só o app é atualizado.';

  @override
  String get updateSkip => 'Pular esta versão';

  @override
  String get updateInstall => 'Atualizar';

  @override
  String get updateDownloading => 'Baixando a nova versão';

  @override
  String get updateConnecting => 'Conectando…';

  @override
  String get updateDownloadFailed =>
      'Não foi possível baixar a atualização. Tente de novo daqui a pouco.';

  @override
  String get updateStepTitle => 'Mais um passo';

  @override
  String get updatePermissionBody =>
      'O Android precisa que você permita que o Vynote instale a própria atualização. Isso só é preciso uma vez. Vamos levar você às configurações: ative \"Permitir desta fonte\", volte e toque em Atualizar de novo.';

  @override
  String get updateGoToSettings => 'Ir para configurações';

  @override
  String get updateDoneTitle => 'O Vynote foi atualizado';

  @override
  String updateDoneBody(String version) {
    return 'A versão $version já está instalada. Reinicie o app para usá-la.';
  }

  @override
  String get updateRestartNow => 'Reiniciar agora';

  @override
  String get updateCancelled => 'Atualização cancelada.';

  @override
  String get updateManualTitle => 'Instale manualmente';

  @override
  String get updateManualBody =>
      'Não encontramos como pedir permissões de administrador. Abra um terminal e execute:';

  @override
  String get updateCommandCopied => 'Comando copiado';

  @override
  String get commonCopy => 'Copiar';

  @override
  String get updateInstallerFailed =>
      'Não foi possível abrir o instalador. Tente de novo daqui a pouco.';

  @override
  String get updateInstallFailed =>
      'Não foi possível instalar a atualização. Tente de novo daqui a pouco.';

  @override
  String exportPdfSaved(String name) {
    return 'PDF de \"$name\" salvo';
  }

  @override
  String get exportPdfGenerating => 'Gerando PDF';

  @override
  String exportSheetProgress(int done, int total) {
    return 'Página $done de $total';
  }

  @override
  String exportPdfFailed(String error) {
    return 'Não foi possível gerar o PDF: $error';
  }

  @override
  String get exportImagesGenerating => 'Gerando imagens';

  @override
  String exportImagesFailed(String error) {
    return 'Não foi possível gerar as imagens: $error';
  }

  @override
  String get exportImagesSaved => 'Imagens salvas';

  @override
  String get exportImageSaved => 'Imagem salva';

  @override
  String get exportFolderTitle => 'Exportando pasta';

  @override
  String exportFolderProgress(int done, int total) {
    return 'Caderno $done de $total';
  }

  @override
  String get exportFolderDone => 'Pasta exportada';

  @override
  String exportFolderFailed(String error) {
    return 'Não foi possível exportar a pasta: $error';
  }

  @override
  String get errImportNotReadable =>
      'O arquivo não é um caderno do Vynote (não é possível lê-lo).';

  @override
  String get errImportNotVynote => 'O arquivo não é um caderno do Vynote.';

  @override
  String get errImportNewerVersion =>
      'O arquivo é de uma versão mais nova do Vynote. Atualize o app para abri-lo.';

  @override
  String get errImportBrokenSheetList => 'A lista de páginas está corrompida.';

  @override
  String get errImportNoSheets => 'O caderno não tem páginas.';

  @override
  String get errImportBrokenSheetAny =>
      'Uma página do arquivo está corrompida.';

  @override
  String get errImportInvalidNames => 'O arquivo tem nomes inválidos.';

  @override
  String get errImportNotZip => 'O arquivo não é um .zip.';

  @override
  String get errImportNoNotebooks =>
      'O .zip não tem cadernos do Vynote. Você exportou como PDF ou PNG?';

  @override
  String errImportMissingFile(String name) {
    return 'Falta $name no arquivo: ele está corrompido ou não é do Vynote.';
  }

  @override
  String errImportBrokenFile(String name) {
    return '$name está corrompido.';
  }

  @override
  String errImportBrokenSheet(String name) {
    return 'A página $name está corrompida.';
  }

  @override
  String get libraryTitle => 'Cadernos';

  @override
  String get libraryHome => 'Início';

  @override
  String get libraryNew => 'Novo';

  @override
  String get libraryNewNotebook => 'Novo caderno';

  @override
  String get libraryNewFolder => 'Nova pasta';

  @override
  String get libraryImportNotebook => 'Importar caderno .vynote';

  @override
  String get libraryImportFolder => 'Importar pasta (.zip)';

  @override
  String get libraryMenuTooltip => 'Mais opções';

  @override
  String get libraryUpTooltip => 'Subir uma pasta';

  @override
  String get librarySearchHint => 'Pesquisar cadernos e pastas';

  @override
  String get librarySearchClear => 'Limpar pesquisa';

  @override
  String get libraryEmptyNoResults => 'Nenhum resultado';

  @override
  String get libraryEmptyNone => 'Ainda não há cadernos';

  @override
  String get libraryEmptyFolder => 'Esta pasta está vazia';

  @override
  String libraryNotebookCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cadernos',
      one: '$count caderno',
    );
    return '$_temp0';
  }

  @override
  String libraryFolderCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count pastas',
      one: '$count pasta',
    );
    return '$_temp0';
  }

  @override
  String get libraryHeaderFirst => 'Crie o primeiro para começar';

  @override
  String libraryHeaderHint(String parts) {
    return '$parts · mantenha um pressionado para ver opções ou arraste-o para uma pasta';
  }

  @override
  String get libraryResultsEverywhere => 'Resultados de todas as pastas';

  @override
  String get libraryNotebookDeleted => 'Caderno excluído';

  @override
  String get libraryNotebookGone => 'O caderno não existe mais';

  @override
  String get libraryLockedNotebook => 'Este caderno está bloqueado';

  @override
  String get libraryWrongPin => 'PIN incorreto';

  @override
  String libraryImportedAs(String name) {
    return 'Importado como \"$name\"';
  }

  @override
  String libraryImportFailed(String error) {
    return 'Não foi possível importar: $error';
  }

  @override
  String get libraryImportingFolder => 'Importando pasta';

  @override
  String get libraryImportCancelled => 'Importação cancelada';

  @override
  String libraryImportUnreadable(int count) {
    return ' ($count não puderam ser lidos)';
  }

  @override
  String libraryImportedMany(int count, String fail) {
    return '$count cadernos importados$fail';
  }

  @override
  String libraryImportedFolder(String name, int count, String fail) {
    return 'Pasta \"$name\" importada: $count cadernos$fail';
  }

  @override
  String libraryExportDone(String name) {
    return 'Caderno \"$name\" salvo';
  }

  @override
  String libraryExportFailed(String error) {
    return 'Não foi possível exportar: $error';
  }

  @override
  String get libraryFolderHint => 'Ex.: Faculdade';

  @override
  String get libraryRenameNotebook => 'Renomear caderno';

  @override
  String get libraryRenameFolder => 'Renomear pasta';

  @override
  String libraryCopySuffix(String name) {
    return '$name (cópia)';
  }

  @override
  String get libraryDuplicated => 'Caderno duplicado';

  @override
  String get libraryFolderEmptyExport => 'A pasta está vazia';

  @override
  String libraryMoveTitle(String name) {
    return 'Mover \"$name\" para…';
  }

  @override
  String libraryMovedTo(String path) {
    return 'Movido para $path';
  }

  @override
  String libraryMovedFolderTo(String path) {
    return 'Movida para $path';
  }

  @override
  String get libraryUndo => 'Desfazer';

  @override
  String get libraryFolderEmptyBody => 'A pasta está vazia.';

  @override
  String get libraryDeleteAllTitle => 'Excluir tudo';

  @override
  String libraryDeleteAllBody(String name, int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count cadernos',
      one: '1 caderno',
    );
    return 'Serão excluídos a pasta \"$name\", suas subpastas e $_temp0 com todas as páginas. Isso não pode ser desfeito.';
  }

  @override
  String get libraryFolderWhatToDo => 'O que fazemos com o que está dentro?';

  @override
  String libraryFolderKeep(String parent) {
    return 'Mover os cadernos para $parent';
  }

  @override
  String get libraryOptRename => 'Renomear';

  @override
  String get libraryOptMove => 'Mover para…';

  @override
  String get libraryOptExport => 'Exportar';

  @override
  String get libraryOptDelete => 'Excluir';

  @override
  String get libraryOptOpen => 'Abrir';

  @override
  String get libraryOptDuplicate => 'Duplicar';

  @override
  String librarySheetCount(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '$count página',
    );
    return '$_temp0';
  }

  @override
  String get moveHere => 'aqui';

  @override
  String get syncIndicatorSynced => 'Sincronizado';

  @override
  String get syncIndicatorSyncing => 'Sincronizando';

  @override
  String get syncIndicatorPending => 'Alterações para enviar';

  @override
  String get syncIndicatorOffline => 'Sem conexão';

  @override
  String get syncIndicatorError => 'Erro de sincronização';

  @override
  String dateToday(String time) {
    return 'Hoje $time';
  }

  @override
  String dateYesterday(String time) {
    return 'Ontem $time';
  }

  @override
  String get datePatternTime => 'HH:mm';

  @override
  String get datePatternDayMonth => 'd \'de\' MMM';

  @override
  String get datePatternDayMonthYear => 'dd/MM/yyyy';

  @override
  String get syncErrOffline => 'Sem conexão';

  @override
  String get syncErrAuthExpired =>
      'A sessão do Google expirou. Conecte de novo.';

  @override
  String get syncErrConflict =>
      'O arquivo mudou na nuvem durante o envio; será tentado de novo';

  @override
  String get syncErrNotFound => 'Não existe na nuvem';

  @override
  String get syncErrVaultChanged =>
      'A configuração de criptografia da nuvem mudou';

  @override
  String get syncErrCryptoLocked =>
      'A nuvem está criptografada: digite a frase-senha em Sincronização > Criptografia';

  @override
  String get syncErrWrongPassphrase => 'A frase-senha está incorreta';

  @override
  String get syncErrCryptoOtherDevice =>
      'Outro dispositivo ativou a criptografia ao mesmo tempo. Digite a frase-senha dele.';

  @override
  String get syncErrCloudNotEncrypted => 'A nuvem não está criptografada';

  @override
  String get syncErrConnectFirst => 'Conecte-se ao Google primeiro';

  @override
  String get syncErrBackgroundBusy =>
      'Há uma sincronização em segundo plano em andamento; tente de novo em alguns segundos';

  @override
  String syncErrFilesFailed(String count) {
    return '$count arquivo(s) não puderam ser sincronizados; serão tentados de novo na próxima vez';
  }

  @override
  String syncErrCouldNotSync(String detail) {
    return 'Não foi possível sincronizar: $detail';
  }

  @override
  String get syncAgoNow => 'agora mesmo';

  @override
  String syncAgoMinutes(int count) {
    return 'há $count min';
  }

  @override
  String syncAgoHours(int count) {
    return 'há $count h';
  }

  @override
  String syncAgoDays(int count) {
    return 'há $count d';
  }

  @override
  String syncNotConfigured(String missing) {
    return 'Esta versão não tem o acesso ao Google configurado (falta: $missing). As notas continuam sendo salvas neste dispositivo.';
  }

  @override
  String get syncDisconnectedStatus =>
      'Não conectado. Os cadernos são salvos somente neste dispositivo.';

  @override
  String get syncConnecting => 'Conectando ao Google…';

  @override
  String get syncSyncing => 'Sincronizando…';

  @override
  String syncConnectedAs(String account, String last) {
    return 'Conectado como $account\n$last';
  }

  @override
  String get syncNever => 'Ainda não sincronizado';

  @override
  String syncLast(String ago) {
    return 'Última sincronização: $ago';
  }

  @override
  String get syncTitle => 'Sincronização com o Google Drive';

  @override
  String syncConflicts(int count) {
    return 'Houve $count conflito(s): procure as páginas \"(conflito)\" e fique com a que funciona.';
  }

  @override
  String get syncBackgroundTitle => 'Sincronizar em segundo plano';

  @override
  String get syncBackgroundSubtitle =>
      'A cada 15 minutos com conexão, mesmo com o app fechado.';

  @override
  String get syncConnect => 'Conectar com o Google';

  @override
  String get syncNow => 'Sincronizar agora';

  @override
  String get syncDisconnect => 'Desconectar';

  @override
  String get cryptoStatusUnknown =>
      'Ainda não se sabe: aparece na próxima sincronização.';

  @override
  String get cryptoStatusOff =>
      'Desativada: o Google pode ler o que é enviado para o seu Drive.';

  @override
  String get cryptoStatusOn =>
      'Ativada: no Drive há somente arquivos criptografados com a sua frase-senha.';

  @override
  String get cryptoStatusLocked =>
      'A nuvem está criptografada. Digite a frase-senha para sincronizar.';

  @override
  String get cryptoTitle => 'Criptografia';

  @override
  String get cryptoWarning =>
      'Se você esquecer a frase-senha, não há como recuperar o que está na nuvem (o que está neste dispositivo não se perde). Os nomes dos arquivos no Drive são códigos aleatórios e continuam visíveis.';

  @override
  String get cryptoEnable => 'Ativar criptografia';

  @override
  String get cryptoEnterPass => 'Digitar frase-senha';

  @override
  String get cryptoDisableTitle => 'Desativar a criptografia?';

  @override
  String get cryptoDisableBody =>
      'Tudo será enviado de novo sem criptografia e os dados criptografados serão apagados do Drive. Pode demorar se houver muitos arquivos.';

  @override
  String get cryptoDisableConfirm => 'Desativar';

  @override
  String get cryptoDisable => 'Desativar criptografia';

  @override
  String get cryptoPassTitle => 'Frase-senha';

  @override
  String get cryptoPassIntro =>
      'Escolha uma frase-senha e anote-a em um lugar seguro. Se você a esquecer, não há como recuperar o que está na nuvem (o que está neste dispositivo não se perde). Tudo será enviado criptografado e os dados anteriores serão apagados do Drive.';

  @override
  String get cryptoPassLabel => 'Frase-senha';

  @override
  String get cryptoPassRepeat => 'Repita a frase-senha';

  @override
  String get cryptoPassMismatch => 'As duas frases-senha não coincidem.';

  @override
  String get cryptoActivate => 'Ativar';

  @override
  String get cryptoUnlock => 'Desbloquear';

  @override
  String cryptoPassShort(int min) {
    return 'A frase-senha precisa ter pelo menos $min caracteres.';
  }

  @override
  String get cryptoStepDeriving =>
      'Gerando a chave (pode levar alguns segundos)…';

  @override
  String get cryptoStepSyncBeforeEncrypt =>
      'Sincronizando antes de criptografar…';

  @override
  String get cryptoStepSyncBeforeDecrypt =>
      'Sincronizando antes de descriptografar…';

  @override
  String cryptoStepEncrypting(int done, int total) {
    return 'Criptografando $done/$total…';
  }

  @override
  String cryptoStepDecrypting(int done, int total) {
    return 'Descriptografando $done/$total…';
  }

  @override
  String get commonRename => 'Renomear';

  @override
  String get commonExport => 'Exportar';

  @override
  String get commonSave => 'Salvar';

  @override
  String get commonUpdate => 'Atualizar';

  @override
  String get commonSearch => 'Pesquisar';

  @override
  String sheetLabel(int n) {
    return 'Página $n';
  }

  @override
  String sheetLabelTitled(int n, String title) {
    return 'Página $n · $title';
  }

  @override
  String sheetCountPlural(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas',
      one: '$count página',
    );
    return '$_temp0';
  }

  @override
  String get menuInsertPdf => 'PDF';

  @override
  String get menuInsertVoice => 'Gravação de voz';

  @override
  String get menuInsertImage => 'Imagem';

  @override
  String get menuInsertCamera => 'Câmera';

  @override
  String get menuInsertAudio => 'Arquivo de áudio';

  @override
  String get menuInsertSticky => 'Nota adesiva';

  @override
  String get menuInsertSheet => 'Nova página';

  @override
  String get menuMoreReadingExit => 'Sair do modo leitura';

  @override
  String get menuMoreReading => 'Modo leitura';

  @override
  String get menuMoreBookmarkRemove => 'Remover marcador';

  @override
  String get menuMoreBookmarkAdd => 'Marcar esta página';

  @override
  String get menuMoreFullscreen => 'Tela cheia';

  @override
  String get menuMoreStyle => 'Estilo da página';

  @override
  String get menuMorePaperColor => 'Cor do papel';

  @override
  String get menuMoreShortcuts => 'Atalhos de teclado';

  @override
  String get menuMoreFavoriteRemove => 'Remover dos favoritos';

  @override
  String get menuMoreFavoriteAdd => 'Favorito';

  @override
  String get menuMoreLockRemove => 'Remover bloqueio';

  @override
  String get menuMoreLockAdd => 'Bloquear com PIN';

  @override
  String get menuMoreShare => 'Compartilhar';

  @override
  String get menuMorePrint => 'Imprimir';

  @override
  String get menuMoreDeleteNotebook => 'Excluir caderno';

  @override
  String get menuExportFolderTitle => 'Exportar pasta';

  @override
  String get menuExportFolderPdf => 'Um PDF por caderno';

  @override
  String get menuExportFolderPng =>
      'Uma pasta por caderno, com uma imagem por página';

  @override
  String get menuExportFolderVynote =>
      'Um .vynote por caderno, para levar a outro dispositivo';

  @override
  String get menuExportFormatPdf => 'PDF';

  @override
  String get menuExportFormatPng => 'Imagens (PNG)';

  @override
  String get menuExportFormatVynote => 'Vynote';

  @override
  String get menuExportBackground => 'Incluir o fundo da página';

  @override
  String get menuExportBackgroundOff =>
      'Desativado: só o que foi escrito, sobre branco';

  @override
  String get menuExportAllPdf => 'Caderno inteiro';

  @override
  String get menuExportAllPng => 'Todas as páginas, em um .zip';

  @override
  String get menuExportVynoteTitle => 'Caderno do Vynote (.vynote)';

  @override
  String get menuExportVynoteHint =>
      'Para levar a outro dispositivo ou fazer uma cópia de segurança';

  @override
  String get menuExportSheetPdf => 'PDF desta página';

  @override
  String get menuExportSheetPng => 'Imagem desta página (PNG)';

  @override
  String get sectionNew => 'Nova seção';

  @override
  String get sectionOptions => 'Opções da seção';

  @override
  String get sectionUp => 'Subir';

  @override
  String get sectionDown => 'Descer';

  @override
  String get sectionExportTitle => 'Quais seções exportar?';

  @override
  String get sectionAll => 'Todas';

  @override
  String get indexTitle => 'Índice';

  @override
  String get indexEmpty =>
      'Ainda não há títulos.\nUse a ferramenta Título da barra para marcar o que você escreveu.';

  @override
  String indexLevelUp(int level) {
    return 'Mudar para Título $level';
  }

  @override
  String indexLevelDown(int level) {
    return 'Mudar para Título $level';
  }

  @override
  String get indexRemove => 'Remover do índice';

  @override
  String get indexRenameTitle => 'Renomear título';

  @override
  String get searchHint =>
      'Pesquise nos textos, notas adesivas e títulos de páginas';

  @override
  String searchNone(String query) {
    return 'Nenhum resultado para \"$query\"';
  }

  @override
  String searchTitleSnippet(String title) {
    return 'Título: $title';
  }

  @override
  String get paperColorIvory => 'Marfim';

  @override
  String get paperColorWhite => 'Branco';

  @override
  String get paperColorCream => 'Creme';

  @override
  String get paperColorGray => 'Cinza';

  @override
  String get paperColorLightBlue => 'Azul-claro';

  @override
  String get paperColorGreen => 'Verde';

  @override
  String styleDeleteTemplate(String name) {
    return 'Excluir o modelo «$name»?';
  }

  @override
  String get styleSize => 'Tamanho';

  @override
  String get styleBackground => 'Fundo';

  @override
  String get styleTemplates => 'Modelos';

  @override
  String get styleMyTemplates => 'Meus modelos';

  @override
  String get styleFromImage => 'A partir de uma imagem…';

  @override
  String get styleSpacingLined => 'Entrelinhas';

  @override
  String get styleSpacingGrid => 'Grade';

  @override
  String get styleApplyTo => 'Aplicar a';

  @override
  String get styleThisSheet => 'Esta página';

  @override
  String get styleWholeNotebook => 'Caderno inteiro';

  @override
  String get styleTitleNew => 'Nova página';

  @override
  String get styleTitle => 'Estilo da página';

  @override
  String get styleApply => 'Aplicar';

  @override
  String get pagesAll => 'Ver todas';

  @override
  String get pagesOnlyBookmarked => 'Só marcadas';

  @override
  String get pagesNewAfter => 'Nova página depois da atual';

  @override
  String get pagesNoBookmarks => 'Não há páginas marcadas';

  @override
  String get pagesNoBookmarksHint =>
      'Não há páginas marcadas. Use o marcador acima para marcar a página que você está vendo.';

  @override
  String get pagesBookmark => 'Marcar';

  @override
  String get pagesDragToMove => 'Arraste para mover';

  @override
  String get pagesNewAfterMenu => 'Nova página depois';

  @override
  String get pagesNewWithTemplate => 'Nova página com modelo…';

  @override
  String get pagesDuplicate => 'Duplicar';

  @override
  String get pagesSaveTemplate => 'Salvar como modelo';

  @override
  String get pagesMoveBefore => 'Mover antes';

  @override
  String get pagesMoveAfter => 'Mover depois';

  @override
  String notebookTemplateDefault(int n) {
    return 'Modelo $n';
  }

  @override
  String notebookTemplateFailed(String error) {
    return 'Não foi possível salvar o modelo: $error';
  }

  @override
  String get notebookTemplateSaved => 'Modelo salvo';

  @override
  String get notebookTemplateName => 'Nome';

  @override
  String notebookSheetNameTitle(int n) {
    return 'Nome da página $n';
  }

  @override
  String get notebookOptional => 'Opcional';

  @override
  String get notebookLastSheet =>
      'Não é possível excluir a única página do caderno';

  @override
  String notebookDeleteSheetTitle(int n) {
    return 'Excluir a página $n';
  }

  @override
  String get notebookDeleteSheetBody =>
      'A página será excluída com tudo o que tem (pode ser desfeito).';

  @override
  String notebookSheetReadFailed(String error) {
    return 'Não foi possível ler a página: $error';
  }

  @override
  String get notebookBookmarkTitle => 'Marcador';

  @override
  String get notebookBookmarkHint => 'Nome (opcional)';

  @override
  String get notebookBookmarkNoName => 'Sem nome';

  @override
  String notebookSectionOpenFailed(String error) {
    return 'Não foi possível abrir a seção: $error';
  }

  @override
  String notebookSectionDefault(int n) {
    return 'Seção $n';
  }

  @override
  String get notebookSectionHint => 'Ex.: Prática';

  @override
  String get notebookSectionRename => 'Renomear seção';

  @override
  String get notebookLastSection =>
      'Não é possível excluir a única seção do caderno';

  @override
  String notebookDeleteSectionTitle(String name) {
    return 'Excluir a seção \"$name\"';
  }

  @override
  String notebookDeleteSectionBody(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas com tudo o que têm serão excluídas',
      one: '1 página com tudo o que tem será excluída',
    );
    return '$_temp0. Isso não pode ser desfeito.';
  }

  @override
  String notebookInsertFailed(String error) {
    return 'Não foi possível inserir: $error';
  }

  @override
  String get notebookRecordingBusy => 'Já há uma gravação em andamento';

  @override
  String get notebookImportingPdf => 'Importando PDF';

  @override
  String get notebookPickFile => 'Escolha o arquivo…';

  @override
  String notebookSheetsImported(int count) {
    String _temp0 = intl.Intl.pluralLogic(
      count,
      locale: localeName,
      other: '$count páginas importadas',
      one: '$count página importada',
    );
    return '$_temp0';
  }

  @override
  String get notebookFavoriteAdded => 'Adicionado aos favoritos';

  @override
  String get notebookFavoriteRemoved => 'Removido dos favoritos';

  @override
  String get notebookUnlockTitle => 'Remover bloqueio';

  @override
  String get notebookUnlockHint => 'Digite o PIN atual';

  @override
  String get notebookUnlocked => 'Caderno desbloqueado';

  @override
  String get notebookLockTitle => 'Bloquear caderno';

  @override
  String get notebookLockHint => 'Escolha um PIN de 4 ou mais dígitos';

  @override
  String get notebookPinShort => 'O PIN precisa ter pelo menos 4 dígitos';

  @override
  String get notebookPinRepeat => 'Repita o PIN';

  @override
  String get notebookPinMismatch => 'Os PINs não coincidem';

  @override
  String get notebookLocked => 'Caderno bloqueado: o PIN é pedido ao abri-lo';

  @override
  String get notebookSaved => 'Caderno salvo';

  @override
  String notebookExportFailed(String error) {
    return 'Não foi possível exportar: $error';
  }

  @override
  String notebookSheetFileName(String name, int n) {
    return '$name - página $n';
  }

  @override
  String get notebookImageSaved => 'Imagem salva';

  @override
  String get notebookFullscreenExit => 'Sair da tela cheia';

  @override
  String get notebookRecording => 'Gravando';

  @override
  String notebookRecordingNamed(String name) {
    return 'Gravando · $name';
  }

  @override
  String get notebookRecordingStop => 'Parar e salvar';

  @override
  String get notebookRecordingCancel => 'Cancelar e descartar';

  @override
  String get notebookLinkFailed => 'Não foi possível abrir o link';

  @override
  String get notebookSheetGone => 'A página não existe mais';

  @override
  String get notebookBack => 'Voltar aos cadernos';

  @override
  String get notebookSearchClose => 'Fechar pesquisa';

  @override
  String get notebookInsert => 'Inserir';

  @override
  String get notebookIndexTooltip => 'Índice';

  @override
  String get notebookSections => 'Seções';

  @override
  String get notebookPages => 'Páginas';

  @override
  String get notebookMore => 'Mais opções';

  @override
  String get notebookRemoteChanges => 'Há alterações de outro dispositivo';

  @override
  String notebookSearchIn(String name) {
    return 'Pesquisar em \"$name\"';
  }

  @override
  String notebookSheetCounter(String title, int n, int total) {
    return '$title$n / $total';
  }

  @override
  String get audioPrefix => 'Áudio';

  @override
  String get errVoiceBusy => 'Já há uma gravação em andamento';

  @override
  String get errVoiceNoPermission => 'Sem permissão para usar o microfone';

  @override
  String errVoiceFailed(String detail) {
    return 'Não foi possível gravar: $detail';
  }

  @override
  String get headingTitle => 'Adicionar ao índice';

  @override
  String get headingFailed => 'Não foi possível ler: digite o nome';

  @override
  String get headingHint => 'Nome';

  @override
  String get headingDownloading =>
      'Baixando o reconhecimento de letra, só na primeira vez (você pode digitar o nome enquanto isso)…';

  @override
  String get headingReading =>
      'Lendo a letra… (você pode digitar o nome enquanto isso)';

  @override
  String get headingMoreImportant => 'Mais importante';

  @override
  String get headingLessImportant => 'Menos importante';

  @override
  String headingLevel(int level) {
    return 'Título $level';
  }

  @override
  String get headingAdd => 'Adicionar';

  @override
  String get formatBold => 'Negrito (Ctrl+B)';

  @override
  String get formatItalic => 'Itálico (Ctrl+I)';

  @override
  String get formatUnderline => 'Sublinhado (Ctrl+U)';

  @override
  String get formatStrike => 'Tachado (Alt+Shift+5)';

  @override
  String get formatColor => 'Cor do texto';

  @override
  String get formatHighlight => 'Destaque (Ctrl+Shift+H)';

  @override
  String get formatNormal => 'Normal';

  @override
  String get formatTitle => 'Título';

  @override
  String get formatSubtitle => 'Subtítulo';

  @override
  String get formatBullets => 'Com marcadores (Ctrl+Shift+8)';

  @override
  String get formatNumbered => 'Numerada (Ctrl+Shift+7)';

  @override
  String get formatTodo => 'Lista de tarefas (Ctrl+Shift+9)';

  @override
  String get formatOutdent => 'Diminuir recuo (Shift+Tab)';

  @override
  String get formatIndent => 'Aumentar recuo (Tab)';

  @override
  String get formatAlignLeft => 'Alinhar à esquerda (Ctrl+L)';

  @override
  String get formatCenter => 'Centralizar (Ctrl+E)';

  @override
  String get formatAlignRight => 'Alinhar à direita (Ctrl+R)';

  @override
  String get formatJustify => 'Justificar (Ctrl+J)';

  @override
  String get formatSizeDown => 'Diminuir fonte (Ctrl+[)';

  @override
  String get formatSizeUp => 'Aumentar fonte (Ctrl+])';

  @override
  String get formatSizeAuto => 'Automático';

  @override
  String get formatCut => 'Recortar';

  @override
  String get pullDone => 'Página adicionada';

  @override
  String get pullHold => 'Segure para adicionar uma página';

  @override
  String get toolPen => 'Caneta · toque de novo para opções';

  @override
  String get toolHighlighter => 'Marca-texto · toque de novo para opções';

  @override
  String get toolPaint => 'Decorador · toque de novo para opções';

  @override
  String get toolShapes => 'Formas · toque de novo para opções';

  @override
  String get toolText => 'Texto com teclado';

  @override
  String get toolSelect => 'Selecionar';

  @override
  String get toolTitle => 'Título para o índice';

  @override
  String get toolUndo => 'Desfazer';

  @override
  String get toolRedo => 'Refazer';

  @override
  String toolZoomLocked(int percent) {
    return 'Zoom fixo ($percent%) · toque para soltar';
  }

  @override
  String get toolZoomLock => 'Fixar o zoom';

  @override
  String get toolMoreColors => 'Mais cores';

  @override
  String get toolPenOptions => 'Ponta, espessura e opacidade';

  @override
  String get toolDragBar => 'Arraste para mover a barra';

  @override
  String zoomIndicator(int percent) {
    return '$percent%';
  }

  @override
  String zoomIndicatorLocked(int percent) {
    return '$percent% · fixo';
  }

  @override
  String get selOrder => 'Ordem';

  @override
  String get selFront => 'Trazer para frente';

  @override
  String get selUp => 'Subir um';

  @override
  String get selDown => 'Descer um';

  @override
  String get selBack => 'Enviar para o fundo';

  @override
  String get selDuplicate => 'Duplicar';

  @override
  String get selLink => 'Link';

  @override
  String get selEditLink => 'Editar link';

  @override
  String get selRemoveLink => 'Remover link';

  @override
  String get selStraighten => 'Endireitar';

  @override
  String get selDelete => 'Excluir';

  @override
  String get selDeselect => 'Desmarcar';

  @override
  String get sheetMenuPaste => 'Colar aqui';

  @override
  String get linkTitle => 'Link';

  @override
  String get linkTitleEdit => 'Editar link';

  @override
  String get linkKindWeb => 'Página da web';

  @override
  String get linkKindSheet => 'Página';

  @override
  String get linkKindNotebook => 'Caderno';

  @override
  String get linkUrlHint => 'endereço, ex.: pt.wikipedia.org';

  @override
  String get linkNoSheets => 'Não há páginas.';

  @override
  String get linkNoNotebooks => 'Não há outros cadernos.';

  @override
  String get stickyHint => 'Nota…';

  @override
  String get editorLinkMissingPage => 'Essa página não está no caderno';

  @override
  String get editorRenameAudio => 'Renomear áudio';

  @override
  String get editorPullHint =>
      'No fim, deslize para cima e segure para adicionar uma página';

  @override
  String editorScrollerLabel(int n, int total) {
    return 'Página $n de $total';
  }

  @override
  String get editorCopied => 'Copiado';

  @override
  String editorLoadingSheet(int n) {
    return 'Carregando a página $n…';
  }

  @override
  String get tipPen => 'Esferográfica';

  @override
  String get tipFountain => 'Caneta-tinteiro';

  @override
  String get tipPencil => 'Lápis';

  @override
  String get tipFine => 'Fineliner';

  @override
  String get tipCalligraphy => 'Caligrafia';

  @override
  String get paintStyleBrush => 'Pincel';

  @override
  String get paintStyleHighlighter => 'Marca-texto';

  @override
  String get paintStyleMarker => 'Pincel atômico';

  @override
  String get paintShapeStars => 'Estrelas';

  @override
  String get paintShapeHearts => 'Corações';

  @override
  String get paintShapeSparkles => 'Brilhos';

  @override
  String get paintShapeMoons => 'Luas';

  @override
  String get paintShapeDots => 'Pontos';

  @override
  String get paintShapeCircles => 'Círculos';

  @override
  String get paintShapeExclamations => 'Exclamações';

  @override
  String get paintShapeBolts => 'Raios';

  @override
  String get paintShapeTicks => 'Marcas de visto';

  @override
  String get paintShapeCrosses => 'Xis';

  @override
  String get paintShapeClouds => 'Nuvens';

  @override
  String get paintShapeBubbles => 'Balões';

  @override
  String get paintShapeLeaves => 'Folhas';

  @override
  String get paintShapePaws => 'Patinhas';

  @override
  String get paintShapeTriangles => 'Triângulos';

  @override
  String get paintShapeSquares => 'Quadrados';

  @override
  String get paintShapeDiamonds => 'Losangos';

  @override
  String get paintShapeFlowers => 'Flores';

  @override
  String get paintShapeNotes => 'Notas musicais';

  @override
  String get shapeKindLine => 'Reta';

  @override
  String get shapeKindArrow => 'Seta';

  @override
  String get shapeKindRectangle => 'Retângulo';

  @override
  String get shapeKindCircle => 'Círculo';

  @override
  String get shapeKindEllipse => 'Elipse';

  @override
  String get shapeKindTriangle => 'Triângulo';

  @override
  String get penFavorites => 'Favoritos';

  @override
  String get penFavHelp =>
      'Segure um favorito para substituí-lo pela cor atual.';

  @override
  String get penPanelHighlighter => 'Marca-texto';

  @override
  String get penPanelPencil => 'Caneta';

  @override
  String get penTip => 'Ponta';

  @override
  String get penWidth => 'Espessura';

  @override
  String get penOpacity => 'Opacidade';

  @override
  String get penSmartShapes => 'Formas inteligentes';

  @override
  String get penSmartShapesHint =>
      'Mantenha a caneta parada ao final de uma forma';

  @override
  String get penColor => 'Cor';

  @override
  String get penEraser => 'Borracha (pressione o botão da caneta)';

  @override
  String get penEraserSmall => 'Pequena';

  @override
  String get penEraserMedium => 'Média';

  @override
  String get penEraserLarge => 'Grande';

  @override
  String get shapesTitle => 'Formas';

  @override
  String get shapesBorder => 'Borda';

  @override
  String get shapesBorderHint => 'A borda usa a cor e a espessura da caneta.';

  @override
  String get shapesFill => 'Preenchimento';

  @override
  String get shapesNoFill => 'Retas e setas não têm preenchimento.';

  @override
  String get shapesSnapGrid => 'Encaixar na grade';

  @override
  String get shapesSnapGridHint =>
      'Em páginas quadriculadas, milimetradas, pontilhadas ou com eixos';

  @override
  String get paintPanelTitle => 'Decorador';

  @override
  String get paintStroke => 'Traço';

  @override
  String get paintWidth => 'Largura';

  @override
  String get paintBackground => 'Fundo';

  @override
  String get paintGlitter => 'Brilho';

  @override
  String get paintAmount => 'Quantidade';

  @override
  String get paintAuto => 'Auto';

  @override
  String get paintSize => 'Tamanho';

  @override
  String shapeMeasureTriangle(String base, String height) {
    return 'base $base · altura $height mm';
  }

  @override
  String get librarySampleNotebook => 'Meu caderno';

  @override
  String libraryRecoveredNotebook(int n) {
    return 'Caderno recuperado $n';
  }

  @override
  String get exportFileNotebook => 'Caderno';

  @override
  String get exportFileFolder => 'Pasta';

  @override
  String get exportFileSection => 'Seção';

  @override
  String get exportFilePage => 'página';

  @override
  String get exportFileSheet => 'página';

  @override
  String get exportSavePdf => 'Salvar PDF';

  @override
  String get exportSaveImage => 'Salvar imagem';

  @override
  String get exportSaveImages => 'Salvar imagens';

  @override
  String get exportSaveNotebook => 'Salvar caderno';

  @override
  String get exportSaveFolder => 'Salvar pasta';

  @override
  String get settingsTitle => 'Configurações';

  @override
  String get settingsSectionLanguage => 'Idioma';

  @override
  String get settingsAppLanguage => 'Idioma do app';

  @override
  String get settingsInkLanguage => 'Idioma da escrita à mão';

  @override
  String get settingsLanguageSystem => 'Igual ao sistema';

  @override
  String get settingsInkSameAsApp => 'Igual ao app';

  @override
  String get settingsInkHelp =>
      'Serve para ler os títulos que você escreve à mão. Ao trocar, o novo modelo é baixado (cerca de 20 MB) e o anterior é excluído.';

  @override
  String get settingsSectionUpdates => 'Atualizações';

  @override
  String get settingsCheckUpdates => 'Verificar atualizações';

  @override
  String get settingsAutoUpdates => 'Verificar atualizações automaticamente';

  @override
  String get settingsSectionAbout => 'Sobre';

  @override
  String get settingsVersion => 'Versão';

  @override
  String get settingsSource => 'Código-fonte';

  @override
  String get settingsLicense => 'Licença';

  @override
  String get settingsLicenseValue => 'GPL v3 ou posterior';

  @override
  String get settingsPrivacy => 'Política de privacidade';

  @override
  String get updateChecking => 'Verificando atualizações…';

  @override
  String get updateCheckFailed =>
      'Não foi possível verificar atualizações agora';

  @override
  String get updateUpToDate => 'Você já tem a versão mais recente';

  @override
  String get colorEyedropper => 'Conta-gotas';

  @override
  String get eyedropperHint => 'Toque na folha para pegar uma cor';

  @override
  String get eyedropperCancel => 'Cancelar conta-gotas';

  @override
  String get colorRecent => 'Recentes';
}
