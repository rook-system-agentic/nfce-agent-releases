; ============================================================
; Rook — Agente de Captação (NFC-e) — Instalador gráfico (ROO-243 + ROO-279)
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
; ROO-279 acrescenta:
;   - Reinstalação consciente: se já existe config na máquina, o assistente
;     mostra isso e oferece MANTER o token/pasta atuais (evita revogar token
;     à toa e reconfigurar às cegas).
;   - Encerra um rook-agent.exe em execução antes de copiar os arquivos
;     (evita arquivo-em-uso e processo duplicado).
;   - Verificação pós-instalação: roda `rook-agent.exe --check` (valida config,
;     pasta, conexão e token no servidor) e mostra o RESULTADO REAL na tela
;     final — "conectado ao Rook" ou o motivo exato da falha. Se o executável
;     nem abrir, aponta para provável bloqueio de antivírus.
;
; Compilado pelo CI (.github/workflows/build-installer.yml) num runner Windows.
; Runtime (fluxo do leigo) deve ser validado num Windows real — não dá pra
; testar a execução do .exe no CI (só a compilação).
; ============================================================

#define AppName "Rook - Agente de Captação"
#define AppVersion "1.2.1"
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
  ReinstallPage: TInputOptionWizardPage;
  TokenPage: TInputQueryWizardPage;
  FolderPage: TInputDirWizardPage;
  PrevConfigExists: Boolean;
  KeepConfig: Boolean;
  CheckOk: Boolean;
  CheckResultMsg: String;

function ConfigFilePath(): String;
begin
  Result := ExpandConstant('{localappdata}\Rook Agent\.rook-agent.json');
end;

// O agente antigo (pré-instalador) gravava a config na home do usuário;
// o agente migra sozinho, então também conta como "já instalado".
function LegacyConfigFilePath(): String;
begin
  Result := ExpandConstant('{%USERPROFILE}\.rook-agent.json');
end;

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
  PrevConfigExists := FileExists(ConfigFilePath()) or FileExists(LegacyConfigFilePath());
  KeepConfig := False;
  CheckOk := False;
  CheckResultMsg := '';

  // Página de reinstalação: só aparece quando já existe config na máquina.
  ReinstallPage := CreateInputOptionPage(wpWelcome,
    'Agente já instalado nesta máquina',
    'Encontramos uma configuração anterior do Agente de Captação',
    'Este computador já tem o agente configurado (token e pasta de XMLs). ' +
    'Se você está apenas reinstalando ou atualizando o programa, mantenha a configuração atual — ' +
    'NÃO é preciso gerar um novo token no Rook. Escolha uma opção:',
    True, False);
  ReinstallPage.Add('Manter a configuração atual (recomendado) — só reinstala o programa');
  ReinstallPage.Add('Reconfigurar — informar um novo token e a pasta de XMLs');
  ReinstallPage.Values[0] := True;

  TokenPage := CreateInputQueryPage(ReinstallPage.ID,
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

function ShouldSkipPage(PageID: Integer): Boolean;
begin
  Result := False;
  if (PageID = ReinstallPage.ID) and (not PrevConfigExists) then
    Result := True;
  if ((PageID = TokenPage.ID) or (PageID = FolderPage.ID)) and KeepConfig then
    Result := True;
end;

// Validação de cada passo antes de avançar.
function NextButtonClick(CurPageID: Integer): Boolean;
var
  token: String;
begin
  Result := True;

  if CurPageID = ReinstallPage.ID then
  begin
    KeepConfig := ReinstallPage.Values[0];
  end
  else if CurPageID = TokenPage.ID then
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

// Encerra um agente em execução antes de copiar arquivos: evita
// "arquivo em uso" na troca do .exe e processo duplicado depois.
function PrepareToInstall(var NeedsRestart: Boolean): String;
var
  rc: Integer;
begin
  Result := '';
  Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#ExeName}', '', SW_HIDE, ewWaitUntilTerminated, rc);
  // Pequena pausa para o Windows liberar o lock do executável.
  Sleep(800);
end;

// Escreve a config que o agente lê + registra a inicialização automática oculta.
procedure WriteConfigAndAutostart();
var
  appDir, exePath, cfg, jsonFolder, vbs: String;
begin
  appDir := ExpandConstant('{app}');
  exePath := appDir + '\{#ExeName}';

  // Em reinstalação com "manter configuração", NÃO sobrescreve a config —
  // o token atual continua valendo.
  if not KeepConfig then
  begin
    jsonFolder := FolderPage.Values[0];
    StringChangeEx(jsonFolder, '\', '\\', True);

    cfg :=
      '{' + #13#10 +
      '  "token": "' + Trim(TokenPage.Values[0]) + '",' + #13#10 +
      '  "folder": "' + jsonFolder + '"' + #13#10 +
      '}' + #13#10;
    SaveStringToFile(appDir + '\.rook-agent.json', cfg, False);
  end;

  // VBS no Startup: roda o agente com janela oculta (0) e sem esperar (False).
  vbs :=
    'Set WshShell = CreateObject("WScript.Shell")' + #13#10 +
    'WshShell.Run """' + exePath + '""", 0, False' + #13#10;
  SaveStringToFile(ExpandConstant('{userstartup}') + '\Rook Agent.vbs', vbs, False);
end;

// Roda `rook-agent.exe --check` (valida config, pasta, conexão e token no
// servidor) e traduz o código de saída em mensagem para a tela final.
// Códigos: 0=ok · 2=token inválido · 3=sem conexão · 4=pasta inacessível · 5=sem config.
procedure RunPostInstallCheck();
var
  exePath: String;
  rc: Integer;
begin
  exePath := ExpandConstant('{app}') + '\{#ExeName}';

  if not Exec(exePath, '--check', ExpandConstant('{app}'), SW_HIDE, ewWaitUntilTerminated, rc) then
  begin
    CheckOk := False;
    CheckResultMsg :=
      'O executável do agente NÃO pôde ser iniciado. Provável bloqueio do antivírus — ' +
      'abra o Windows Defender (Histórico de proteção / quarentena), restaure/permita o rook-agent.exe e reinstale.';
    Exit;
  end;

  case rc of
    0:
    begin
      CheckOk := True;
      CheckResultMsg := 'Verificação concluída: o agente CONECTOU ao Rook, o token foi aceito e a pasta de XMLs está acessível. Em instantes a Central de Dados mostrará o agente como Online.';
    end;
    2:
    begin
      CheckOk := False;
      CheckResultMsg :=
        'O agente abriu, mas o Rook recusou o token (inválido ou revogado). ' +
        'Gere um novo token em Central de Dados → Agente de Captação e reinstale colando o token novo. ' +
        'Atenção: gerar token novo desconecta instalações antigas.';
    end;
    3:
    begin
      CheckOk := False;
      CheckResultMsg :=
        'O agente abriu, mas NÃO conseguiu falar com app.rooksystem.com.br. ' +
        'Verifique a internet, proxy ou firewall desta máquina e rode o instalador de novo.';
    end;
    4:
    begin
      CheckOk := False;
      CheckResultMsg :=
        'O agente conectou ao Rook, mas a pasta de XMLs configurada está inacessível neste momento. ' +
        'O agente ficará tentando a cada 60 segundos (normal para pasta de rede). Confira o caminho se o problema persistir.';
    end;
    5:
    begin
      CheckOk := False;
      CheckResultMsg :=
        'A configuração do agente não foi encontrada. Rode o instalador novamente escolhendo "Reconfigurar".';
    end;
  else
    begin
      CheckOk := False;
      CheckResultMsg :=
        'Não foi possível confirmar o estado do agente (código ' + IntToStr(rc) + '). ' +
        'Consulte o log em %LOCALAPPDATA%\Rook Agent\rook-agent.log.';
    end;
  end;
end;

procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    WriteConfigAndAutostart();
    RunPostInstallCheck();
  end;
end;

// Tela final mostra o resultado REAL da verificação (não só "concluído").
procedure CurPageChanged(CurPageID: Integer);
begin
  if CurPageID = wpFinished then
  begin
    WizardForm.FinishedLabel.Height := WizardForm.FinishedLabel.Height + ScaleY(80);
    WizardForm.FinishedLabel.Caption :=
      WizardForm.FinishedLabel.Caption + #13#10#13#10 + CheckResultMsg;
    if not CheckOk then
      MsgBox('Atenção: o agente foi instalado, mas ainda NÃO está operando.' + #13#10#13#10 +
        CheckResultMsg + #13#10#13#10 +
        'Log detalhado: %LOCALAPPDATA%\Rook Agent\rook-agent.log', mbError, MB_OK);
  end;
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
