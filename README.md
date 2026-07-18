# NFC-e Capture Agent

Agente de captura automática de NFC-e do PDV para o Rook System.

## Download

Acesse a seção [Releases](https://github.com/rook-system-agentic/nfce-agent-releases/releases) para baixar a versão mais recente.

## Instalação (Windows) — instalador gráfico

1. No Rook, acesse **Central de Dados → Fontes → Agente de Captação** e clique em **Gerar Token do Agente**.
2. Baixe o **RookAgentSetup.exe** e dê **duplo-clique**.
3. O instalador abre uma janela ("avançar → concluir"): cole o token e confirme a **pasta de XMLs do PDV** (ele detecta as mais comuns automaticamente).
4. Pronto — o agente é instalado e inicia sozinho, escondido, a cada login. O Rook receberá suas vendas automaticamente.

> Não é preciso abrir o PowerShell nem executar como administrador. O instalador roda por usuário (em `%LOCALAPPDATA%\Rook Agent`).
>
> **Aviso do Windows (SmartScreen):** enquanto o instalador não estiver assinado com um certificado de code-signing, o Windows pode mostrar "O Windows protegeu o seu PC" na primeira execução. Clique em **Mais informações → Executar assim mesmo**.

## Build do instalador (mantenedores)

O instalador é gerado pelo Inno Setup a partir de [`installer/rook-agent-setup.iss`](installer/rook-agent-setup.iss).
O workflow [`build-installer`](.github/workflows/build-installer.yml) compila num runner Windows e publica o `RookAgentSetup.exe` como artefato (baixa o `rook-agent-win.exe` do release informado). A assinatura de código é uma trilha à parte (certificado do PO).

### Release 1.2.3 (ROO-648 / ROO-649)

1. No monorepo `rook-system`, rode o workflow **Build NFC-e Agent binaries** com
   `publish_release=true` e `release_tag=nfce-agent-v1.2.3` (confira que os DOIS
   assets subiram — no 1.2.2 o `rook-agent-mac` ficou faltando e o auto-update
   de macs respondia 502).
2. Dispare **Build Installer (Windows)** com `release_tag=nfce-agent-v1.2.3` e
   anexe o `RookAgentSetup.exe` ao mesmo release.
3. Só depois dos 3 assets no release: PR no app Rook bumpando `RELEASE_TAG` e
   `LATEST_AGENT_VERSION` JUNTOS (binários primeiro, constantes depois).

**Correções 1.2.3:**
- Instalador não grava mais o `.rook-agent.json` por conta própria: delega ao
  `rook-agent.exe --configure --token ... --folder ...` (ROO-648). O helper
  Pascal da 1.2.2 (`WriteBuffer(Utf8[1], N)`) falhava em qualquer máquina.
- Gravação atômica da config no agente (tmp+rename): reinstalar por cima de um
  agente funcional não destrói mais a configuração em caso de falha (ROO-649).

### Release 1.2.2 (ROO-590)

1. No monorepo `rook-system`, rode o workflow **Build NFC-e Agent binaries** (gera
   `rook-agent-win.exe` / `rook-agent-mac` com `pkg --no-bytecode`).
2. Publique os assets no release `nfce-agent-v1.2.2` deste repositório.
3. Dispare **Build Installer (Windows)** com `release_tag=nfce-agent-v1.2.2` e
   anexe o `RookAgentSetup.exe` ao mesmo release.
4. Confirme que o app Rook aponta `RELEASE_TAG=nfce-agent-v1.2.2` na rota de download.

**Correções 1.2.2:**
- Crash Windows: `[pkg] V8 rejected the bytecode cache` (binário rebuild com `--no-bytecode`).
- Config `.rook-agent.json` gravada em UTF-8 (caminhos com acento, ex. `João Paulo`).

