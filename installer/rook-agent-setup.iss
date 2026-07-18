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
; ROO-590: 1.2.2 — binário rebuild com pkg --no-bytecode (crash V8) + config UTF-8
; ROO-648: 1.2.3 — a config passa a ser gravada pelo PRÓPRIO agente
;   (rook-agent.exe --configure): o helper Pascal da 1.2.2 usava
;   WriteBuffer(Utf8[1], N) — idiom Delphi que o PascalScript não suporta
;   (buffer temporário de 1 byte + overread) e falhava em QUALQUER máquina.
#define AppVersion "1.2.3"
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

// Quota um argumento para a linha de comando Windows (regras da CRT /
// CommandLineToArgvW): backslashes FINAIS antes da aspa de fechamento
// precisam ser dobrados, senão `--folder "C:\pasta\"` parseia como
// `C:\pasta"` e a aspa literal engole o resto da linha (regra 2n+1 da doc
// Microsoft). Token e paths nunca contêm aspas — só a cauda precisa disso.
function ArgQuote(const S: String): String;
var
  N: Integer;
begin
  N := 0;
  while (Length(S) - N > 0) and (S[Length(S) - N] = '\') do
    N := N + 1;
  Result := '"' + S + StringOfChar('\', N) + '"';
end;

// Grava a config DELEGANDO ao próprio agente (ROO-648) + registra a
// inicialização automática oculta.
//
// Por que delegar: o agente Node já grava .rook-agent.json certo (UTF-8 sem
// BOM) há várias versões, com acento no perfil ou sem; era a rotina Pascal
// daqui que corrompia (1.2.1: ANSI → mojibake; 1.2.2: WriteBuffer com idiom
// Delphi → falha sempre). O --configure também é ATÔMICO (tmp+rename): falha
// no meio não destrói config anterior (ROO-649). Exec usa CreateProcessW e o
// exe Node lê GetCommandLineW — parâmetros Unicode chegam intactos fim a fim.
procedure WriteConfigAndAutostart();
var
  appDir, exePath, params, vbs: String;
  rc: Integer;
begin
  appDir := ExpandConstant('{app}');
  exePath := appDir + '\{#ExeName}';

  // Em reinstalação com "manter configuração", NÃO reconfigura — o token
  // atual continua valendo.
  if not KeepConfig then
  begin
    params := '--configure --token ' + ArgQuote(Trim(TokenPage.Values[0])) +
              ' --folder ' + ArgQuote(FolderPage.Values[0]);
    rc := 0;
    if (not Exec(exePath, params, appDir, SW_HIDE, ewWaitUntilTerminated, rc)) or (rc <> 0) then
      MsgBox('Não foi possível gravar a configuração do agente (código ' + IntToStr(rc) + '). ' +
        'Detalhes: %LOCALAPPDATA%\Rook Agent\rook-agent.log. Se o arquivo não existir, ' +
        'verifique a quarentena do antivírus e rode o instalador novamente.', mbError, MB_OK);
  end;

  // VBS no Startup: roda o agente com janela oculta (0) e sem esperar (False).
  // VBS é ANSI-friendly; o caminho do exe vem de ExpandConstant (Unicode ok
  // se gravarmos UTF-8 com BOM? Script VBS classico lê ANSI. Caminho com
  // acento no %LOCALAPPDATA% raramente muda o path do exe — o perfil do
  // usuário NÃO entra em {localappdata}\Rook Agent de forma diferente.
  // {localappdata} já resolve para C:\Users\<nome>\AppData\Local — se o
  // nome tem acento, o .vbs precisa de UTF-16/ado. Mantemos SaveStringToFile
  // nativo para VBS (compat) e só o JSON do agente em UTF-8.
  vbs :=
    'Set WshShell = CreateObject("WScript.Shell")' + #13#10 +
    'WshShell.Run """' + exePath + '""", 0, False' + #13#10;
  SaveStringToFile(ExpandConstant('{userstartup}') + '\Rook Agent.vbs', vbs, False);
end;

// Roda `rook-agent.exe --check` (valida config, pasta, conexão e token no
// servidor) e traduz o código de saída em mensagem para a tela final.
// Códigos: 0=ok · 2=token inválido · 3=sem conexão · 4=pasta inacessível · 5=sem config.
//
// O check roda DESACOPLADO (batch + ewNoWait) com prazo máximo de 45s no lado
// do instalador: se o agente algum dia travar sem sair, o instalador NÃO
// congela junto (lição do incidente ROO-294 — processo vivo-mas-preso sem
// timeout vira tela congelada sem diagnóstico). O batch grava o código de
// saída num arquivo; %ERRORLEVEL% numa linha própria de um ARQUIVO .cmd
// expande na execução (inline com `&` expandiria antes de rodar o exe).
procedure RunPostInstallCheck();
var
  exePath, batPath, resultFile, bat, s: String;
  i, rc, killRc: Integer;
  lines: TArrayOfString;
begin
  exePath := ExpandConstant('{app}') + '\{#ExeName}';
  batPath := ExpandConstant('{app}') + '\run-check.cmd';
  resultFile := ExpandConstant('{app}') + '\check-result.tmp';
  DeleteFile(resultFile);
  DeleteFile(resultFile + '.part');

  // %~dp0 (pasta do próprio .cmd) em vez de caminho literal: usuário Windows
  // com acento no nome (ex. João) quebraria o batch ANSI por codepage OEM.
  // Escreve em .part e renomeia (move = atômico): a leitura nunca pega
  // arquivo escrito pela metade.
  bat :=
    '@echo off' + #13#10 +
    '"%~dp0{#ExeName}" --check >nul 2>&1' + #13#10 +
    'echo %ERRORLEVEL%>"%~dp0check-result.tmp.part"' + #13#10 +
    'move /Y "%~dp0check-result.tmp.part" "%~dp0check-result.tmp" >nul' + #13#10;
  SaveStringToFile(batPath, bat, False);

  if not Exec(ExpandConstant('{cmd}'), '/S /C ""' + batPath + '""', ExpandConstant('{app}'), SW_HIDE, ewNoWait, rc) then
  begin
    DeleteFile(batPath);
    CheckOk := False;
    CheckResultMsg :=
      'Não foi possível executar a verificação pós-instalação. ' +
      'Consulte o log em %LOCALAPPDATA%\Rook Agent\rook-agent.log.';
    Exit;
  end;

  // Espera até 45s (o --check tem timeout interno de rede de 30s).
  // Break por "conteúdo lido", NÃO pelo sinal do valor: crash do agente vira
  // ERRORLEVEL NEGATIVO (NTSTATUS, ex. -1073741819) e precisa quebrar o loop
  // na hora — não esperar os 45s e virar falso "timeout".
  rc := -999999;
  for i := 1 to 90 do
  begin
    if FileExists(resultFile) then
    begin
      if LoadStringsFromFile(resultFile, lines) and (GetArrayLength(lines) > 0) then
      begin
        s := Trim(lines[0]);
        if s <> '' then
        begin
          rc := StrToIntDef(s, -999999);
          break;
        end;
      end;
    end;
    Sleep(500);
  end;
  DeleteFile(batPath);
  DeleteFile(resultFile);

  if rc = -999999 then
  begin
    // Timeout ou resultado ilegível: mata um possível processo preso e reporta.
    Exec(ExpandConstant('{sys}\taskkill.exe'), '/F /IM {#ExeName}', '', SW_HIDE, ewWaitUntilTerminated, killRc);
    // O cmd desbloqueado pelo kill ainda pode gravar o resultado atrasado.
    Sleep(500);
    DeleteFile(batPath);
    DeleteFile(resultFile);
    DeleteFile(resultFile + '.part');
    CheckOk := False;
    CheckResultMsg :=
      'A verificação não terminou no tempo esperado (45s). O agente pode estar bloqueado ou a rede muito lenta. ' +
      'Consulte o log em %LOCALAPPDATA%\Rook Agent\rook-agent.log e, se o arquivo não existir, verifique a quarentena do antivírus.';
    Exit;
  end;

  // 9009 = cmd não achou o exe (típico de quarentena de antivírus).
  if (rc = 9009) or (not FileExists(exePath)) then
  begin
    CheckOk := False;
    CheckResultMsg :=
      'O executável do agente NÃO pôde ser iniciado. Provável bloqueio do antivírus — ' +
      'abra o Windows Defender (Histórico de proteção / quarentena), restaure/permita o rook-agent.exe e reinstale.';
    Exit;
  end;

  // Exit code negativo = o agente ABRIU e crashou (NTSTATUS) — quase sempre
  // interferência de antivírus/DLL bloqueada, não problema de config/rede.
  if rc < 0 then
  begin
    CheckOk := False;
    CheckResultMsg :=
      'O agente iniciou mas travou logo em seguida (código ' + IntToStr(rc) + '). ' +
      'Provável interferência do antivírus — verifique o Histórico de proteção do Windows Defender ' +
      'e o log em %LOCALAPPDATA%\Rook Agent\rook-agent.log.';
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
      // Ambíguo de propósito: 5 pode ser o exit "sem config" do agente OU o
      // ERRORLEVEL 5 do cmd para "acesso negado" (antivírus barrando o exe).
      CheckOk := False;
      CheckResultMsg :=
        'A configuração do agente não foi encontrada — rode o instalador novamente escolhendo "Reconfigurar". ' +
        'Se você acabou de configurar, também pode ser o antivírus bloqueando a execução (acesso negado) — ' +
        'verifique o Histórico de proteção do Windows Defender.';
    end;
  else
    begin
      CheckOk := False;
      // Código 1 genérico costuma ser crash de arranque (ex. bytecode pkg em
      // 1.2.1 — ROO-590). Se não há log, o binário morreu antes da app.
      if (rc = 1) and (not FileExists(ExpandConstant('{app}') + '\rook-agent.log')) then
        CheckResultMsg :=
          'O agente abriu e encerrou imediatamente (código 1), sem gerar log. ' +
          'Isso indica binário incompatível ou bloqueio no arranque. ' +
          'Instale a versão 1.2.2+ (corrigida) ou restaure o rook-agent.exe na quarentena do antivírus.'
      else
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
