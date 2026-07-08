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

