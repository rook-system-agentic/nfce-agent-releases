; ============================================================
; Rook — Agente de Captação (NFC-e) — Instalador gráfico (ROO-243)
; ============================================================
; Substitui o fluxo antigo (PowerShell como admin + assistente no CMD) por
; um instalador com janela: "avançar → avançar → concluir".
;
;   - Instala POR USUÁRIO em %LOCALAPPDATA%\Rook Agent (SEM UAC/admin).
;   - Pergunta o token (campo de texto, não console) e a pasta de XMLs do PDV
;     (com autodetecção das pastas mais comuns + botão Procurar).
;   - Grava a config .rook-agent.json que o agente já lê — sem assistente no CMD.
;   - Registra a inicialização automática (VBS no Startup) que roda o agente
;     ESCONDIDO (sem janela preta) a cada login.
;   - Inicia o agente ao concluir, também escondido.
;
; Compilado pelo CI (.github/workflows/build-installer.yml) num runner Windows.
; Runtime (fluxo do leigo) deve ser validado num Windows real — não dá pra
; testar a execução do .exe no CI (só a compilação).
; ============================================================

#define AppName "Rook - Agente de Captação"
#define AppVersion "1.2.0"
#define AppPublisher "Rook System"
#define ExeName "rook-agent.exe"

[Setup]
AppId={{B3B7F1E2-9C4D-4E3A-9A1B-7A6F2C0D5E44}}
AppName={#AppName}
AppVersion={#AppVersion}
AppPublisher={#AppPublisher}
AppSupportURL=https://app.rooksystem.com.br
DefaultDirName={localappdata}\Rook Agent
DisableDirPage=yes
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
OutputDir=Output
OutputBaseFilename=RookAgentSetup
Compression=lzma2
SolidCompression=yes
WizardStyle=modern
UninstallDisplayName={#AppName}
; Sem SignTool aqui: a assinatura de código é trilha paralela (certificado do PO).
; Enquanto não houver certificado, o Windows mostra o aviso do SmartScreen na 1ª execução.

[Languages]
Name: "brazilianportuguese"; MessagesFile: "compiler:Languages\BrazilianPortuguese.isl"

[Files]
Source: "rook-agent.exe"; DestDir: "{app}"; DestName: "{#ExeName}"; Flags: ignoreversion

[Run]
; Inicia o agente escondido ao finalizar (sem janela de console).
Filename: "{app}\{#ExeName}"; Flags: nowait runhidden skipifsilent

[Code]
var
  TokenPage: TInputQueryWizardPage;
  FolderPage: TInputDirWizardPage;

// Autodetecção das pastas de XML dos PDVs mais comuns.
function DetectPdvFolder(): String;
var
  candidates: array of String;
  i: Integer;
begin
  Result := '';
  SetArrayLength(candidates, 6);
  candidates[0] := 'C:\Colibri\XML\NFC-e';
  candidates[1] := 'C:\Saipos\Dados\XMLs';
  candidates[2] := 'C:\Consumer\XML';
  candidates[3] := 'C:\Degust\XML\NFC-e';
  candidates[4] := 'C:\Acsn\XML\NFC-e';
  candidates[5] := 'C:\PDV\XML';
  for i := 0 to GetArrayLength(candidates) - 1 do
    if DirExists(candidates[i]) then
    begin
      Result := candidates[i];
      Exit;
    end;
end;

procedure InitializeWizard();
begin
  TokenPage := CreateInputQueryPage(wpWelcome,
    'Token do agente',
    'Cole o token gerado no Rook',
    'No Rook, acesse Central de Dados → Fontes → Agente de Captação e clique em "Gerar Token do Agente". Copie o token (começa com rk_agent_) e cole abaixo.');
  TokenPage.Add('Token:', False);

  FolderPage := CreateInputDirPage(TokenPage.ID,
    'Pasta de XMLs do PDV',
    'Onde o seu PDV salva os XMLs das vendas (NFC-e)',
    'Selecione a pasta de XMLs do seu PDV. Detectamos automaticamente as pastas mais comuns — confira ou clique em Procurar para escolher outra.',
    False, '');
  FolderPage.Add('');
  FolderPage.Values[0] := DetectPdvFolder();
end;

// Validação de cada passo antes de avançar.
function NextButtonClick(CurPageID: Integer): Boolean;
var
  token: String;
begin
  Result := True;

  if CurPageID = TokenPage.ID then
  begin
    token := Trim(TokenPage.Values[0]);
    if Pos('rk_agent_', token) <> 1 then
    begin
      MsgBox('O token deve começar com rk_agent_. Gere e copie o token no Rook (Central de Dados → Fontes → Agente de Captação).', mbError, MB_OK);
      Result := False;
    end;
  end
  else if CurPageID = FolderPage.ID then
  begin
    if Trim(FolderPage.Values[0]) = '' then
    begin
      MsgBox('Selecione a pasta de XMLs do seu PDV.', mbError, MB_OK);
      Result := False;
    end
    else if not DirExists(FolderPage.Values[0]) then
    begin
      if MsgBox('A pasta selecionada não existe neste momento (pode ser uma pasta de rede que monta depois). Deseja continuar mesmo assim?', mbConfirmation, MB_YESNO) = IDNO then
        Result := False;
    end;
  end;
end;

// Escreve a config que o agente lê + registra a inicialização automática oculta.
procedure WriteConfigAndAutostart();
var
  appDir, exePath, cfg, jsonFolder, vbs: String;
begin
  appDir := ExpandConstant('{app}');
  exePath := appDir + '\{#ExeName}';

  jsonFolder := FolderPage.Values[0];
  StringChangeEx(jsonFolder, '\', '\\', True);

  cfg :=
    '{' + #13#10 +
    '  "token": "' + Trim(TokenPage.Values[0]) + '",' + #13#10 +
    '  "folder": "' + jsonFolder + '"' + #13#10 +
    '}' + #13#10;
  SaveStringToFile(appDir + '\.rook-agent.json', cfg, False);

  // VBS no Startup: roda o agente com janela oculta (0) e sem esperar (False).
  vbs :=
    'Set WshShell = CreateObject("WScript.Shell")' + #13#10 +
    'WshShell.Run """' + exePath + '""", 0, False' + #13#10;
  SaveStringToFile(ExpandConstant('{userstartup}') + '\Rook Agent.vbs', vbs, False);
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
    WriteConfigAndAutostart();
end;

// Limpeza na desinstalação: remove o autostart (e a config).
procedure CurUninstallStepChanged(CurUninstallStep: TUninstallStep);
begin
  if CurUninstallStep = usUninstall then
  begin
    DeleteFile(ExpandConstant('{userstartup}') + '\Rook Agent.vbs');
    DeleteFile(ExpandConstant('{app}') + '\.rook-agent.json');
  end;
end;
