; Instalador de Vynote para Windows (Inno Setup).
; Uso: iscc /DAppVersion=1.0.42 windows\installer\vynote.iss
; Espera la app ya compilada en build\windows\x64\runner\Release (flutter build windows --release).
; Salida: dist\Vynote-v<versión>-windows-setup.exe

#ifndef AppVersion
  #define AppVersion "1.0.0"
#endif

#define AppName "Vynote"
#define AppExe "Vynote.exe"
#define BuildDir "..\..\build\windows\x64\runner\Release"

[Setup]
; AppId fijo: no cambiarlo nunca, así las versiones nuevas se instalan sobre la anterior.
AppId={{6F3B8A52-9C41-4E7D-B1A0-5D2E8C7F4A19}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher=Vynote
AppPublisherURL=https://github.com/santiagofr1/Vynote
DefaultDirName={autopf}\{#AppName}
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
UninstallDisplayIcon={app}\{#AppExe}
UninstallDisplayName={#AppName}
SetupIconFile=..\runner\resources\app_icon.ico
OutputDir=..\..\dist
OutputBaseFilename=Vynote-v{#AppVersion}-windows-setup
ArchitecturesAllowed=x64compatible
ArchitecturesInstallIn64BitMode=x64compatible
PrivilegesRequired=admin
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
CloseApplications=yes

[Languages]
Name: "spanish"; MessagesFile: "compiler:Languages\Spanish.isl"

[Tasks]
Name: "desktopicon"; Description: "Crear un acceso directo en el escritorio"; GroupDescription: "Accesos directos:"; Flags: unchecked

[InstallDelete]
; el ejecutable se llamaba OpenNote.exe: al actualizar sobre una instalación vieja no debe quedar
Type: files; Name: "{app}\OpenNote.exe"

[Files]
Source: "{#BuildDir}\*"; DestDir: "{app}"; Flags: ignoreversion recursesubdirs createallsubdirs

[Icons]
Name: "{group}\{#AppName}"; Filename: "{app}\{#AppExe}"
Name: "{group}\Desinstalar {#AppName}"; Filename: "{uninstallexe}"
Name: "{autodesktop}\{#AppName}"; Filename: "{app}\{#AppExe}"; Tasks: desktopicon

[Run]
Filename: "{app}\{#AppExe}"; Description: "Abrir {#AppName}"; Flags: nowait postinstall skipifsilent
