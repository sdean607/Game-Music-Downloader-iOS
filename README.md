# Game Music Downloader

Aplicativo iOS nativo em SwiftUI para pesquisar músicas de jogos no Internet Archive, baixar arquivos MP3 e organizar uma biblioteca local.

## Estado deste pacote

Este é um **pacote de desenvolvimento inicial**, não uma versão final validada. A estrutura do projeto Xcode e o workflow de CI estão incluídos, mas este pacote ainda precisa de uma compilação real em macOS/Xcode e de testes em dispositivo.

## Requisitos

- Xcode compatível com iOS 16 ou superior.
- macOS para compilar o aplicativo iOS.
- Conta Apple e assinatura configuradas apenas para instalar/distribuir uma versão assinada em dispositivo; a compilação de Simulator do workflow não exige assinatura.

## Abrir no Xcode

1. Extraia o ZIP.
2. Abra `GameMusicDownloader.xcodeproj`.
3. Selecione o scheme `GameMusicDownloader`.
4. Para assinar no seu dispositivo, substitua o Bundle Identifier de exemplo `com.example.GameMusicDownloader` por um identificador exclusivo e configure sua equipe Apple em Signing & Capabilities.
5. Compile primeiro para um simulador iOS.

## Compilação automática no GitHub Actions

O arquivo `.github/workflows/ios-build.yml` executa um build de iOS Simulator em um runner `macos-15` quando há push ou pull request na branch `main`, ou quando o workflow é iniciado manualmente.

Quando o build termina com sucesso, o workflow publica o artefato `GameMusicDownloader-iOS-Simulator` por 14 dias. Esse artefato é destinado ao Simulator; não é um IPA assinado para instalação em iPhone.

## Funcionalidades integradas nesta etapa

- Pesquisa de itens de áudio no Internet Archive, incluindo a licença declarada na pesquisa.
- Tela de detalhes que consulta os metadados completos antes de listar arquivos.
- Filtro de arquivos: extensão `.mp3`, nome seguro, arquivo não privado e origem diferente de `metadata`.
- Verificação conservadora da licença, comparando o valor da pesquisa com os metadados.
- Downloads liberados somente para CC0, Public Domain Mark, CC BY e CC BY-SA nas versões reconhecidas pelo verificador.
- Bloqueio de licenças ausentes, divergentes, desconhecidas, NC e ND.
- Confirmação explícita do usuário antes de iniciar o download.
- Download temporário com validação HTTP, tipo MIME, arquivo não vazio e limite de 150 MB.
- Biblioteca local em `Documents/GameMusic`, indexada por `library.json`.
- Player, playlists, favoritos, histórico e equalizador de 10 bandas continuam na estrutura do app.

## Limitações e validações pendentes

- A compilação Xcode ainda não foi confirmada por um runner macOS.
- A validação automatizada da licença cobre a declaração dos metadados; não comprova titularidade, autorização do uploader ou que cada faixa individual esteja coberta pela licença do item.
- O fluxo de download ainda não exibe percentual real de progresso.
- A pesquisa e os downloads precisam de testes ponta a ponta com respostas reais e variadas do Internet Archive.
- Reprodução em segundo plano, interrupções de áudio, controles remotos e equalizador precisam ser testados em iPhone físico.
- O Bundle Identifier ainda é um placeholder.

## Observação sobre direitos autorais

A presença de um arquivo no Internet Archive não significa, por si só, que ele esteja livre de direitos autorais. Antes de baixar, redistribuir ou utilizar qualquer áudio, confirme a licença, a titularidade e as permissões aplicáveis.
