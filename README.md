# Game Music Downloader

Plataforma web responsiva para pesquisar, baixar (quando autorizado), organizar e reproduzir músicas de jogos. O projeto iOS original permanece no repositório como referência enquanto a experiência web é desenvolvida.

## Plataforma web

A aplicação web usa:
- **Frontend:** HTML, CSS e JavaScript, com tema escuro preto/roxo e layout adaptável a computador e celular.
- **Backend:** Python 3.13, FastAPI e Uvicorn.
- **Catálogo:** Internet Archive (pesquisa, metadados e arquivos).
- **Biblioteca:** arquivos MP3 e índice JSON armazenados no computador que hospeda o servidor.
- **PWA:** manifesto e service worker para permitir adicionar o site à tela inicial. O cache offline cobre a interface; a API, a biblioteca e o áudio continuam exigindo o servidor ligado e conexão.
- **Acesso:** autenticação HTTP Basic obrigatória na API. Para acesso externo, use HTTPS por meio de um túnel; não abra portas no roteador.

## Iniciar no Windows 10

Requisitos: Windows 10 64-bit, Python 3.13 e conexão com a internet.

1. Baixe o ZIP da branch de desenvolvimento web ou clone o repositório.
2. Abra a pasta `server`.
3. Execute `setup.bat` para criar o ambiente virtual e instalar as dependências.
4. Execute `start-server.bat`.
5. Defina uma senha forte quando solicitada. A senha é obrigatória; não existe senha padrão.
6. Abra `http://127.0.0.1:8000` no navegador.
7. Entre com a senha definida no terminal.

A biblioteca será criada em `server/data/music`, com índice em `server/data/library.json`. Não coloque essa pasta no Git nem a compartilhe publicamente.

## Acesso pela internet

O servidor escuta somente em `127.0.0.1:8000`. Para um teste remoto, instale o Cloudflare Tunnel e execute:

```powershell
cloudflared tunnel --url http://127.0.0.1:8000
```

O Quick Tunnel gera um endereço HTTPS temporário. Mantenha o terminal do túnel aberto. O endereço é público, portanto compartilhe-o somente com pessoas autorizadas e use uma senha forte. Quick Tunnels são destinados a testes, não a hospedagem permanente. Para uso contínuo, configure um túnel nomeado e domínio ou outra solução de acesso privado.

## Funcionalidades web incluídas nesta etapa

- Pesquisa de itens de áudio no Internet Archive.
- Consulta de metadados e listagem de arquivos MP3 públicos.
- Verificação conservadora de licenças CC0, Public Domain Mark, CC BY e CC BY-SA.
- Bloqueio de licenças ausentes, divergentes, NC, ND e desconhecidas.
- Confirmação explícita de direitos antes do download.
- Revalidação dos metadados no servidor antes de baixar.
- Limite de 150 MB, validação de MIME, arquivo não vazio e nome seguro.
- Biblioteca central no computador servidor.
- Reprodução no navegador, controles de faixa, seek, volume, aleatório e repetição.
- Favoritos, playlists e histórico armazenados no navegador.
- Interface PWA responsiva.

## Limitações conhecidas desta etapa

- Esta é a primeira base funcional da versão web; não substitui ainda todas as telas e recursos do aplicativo iOS.
- Favoritos, playlists e histórico ficam no armazenamento local do navegador; a biblioteca de áudio fica no servidor.
- A reprodução em segundo plano e os controles da tela bloqueada dependem do suporte do navegador e do sistema operacional.
- O servidor doméstico precisa permanecer ligado e conectado para acesso remoto.
- O Quick Tunnel tem URL temporária e não é uma solução de produção.
- A declaração de licença do Internet Archive não comprova titularidade nem autorização do uploader. O usuário deve conferir a página do item e os direitos aplicáveis.

## Projeto iOS original

O projeto SwiftUI permanece em `GameMusicDownloader.xcodeproj` enquanto a versão web é validada. O workflow `ios-build.yml` continua disponível para compilar o app no iOS Simulator; esse artefato não é um IPA assinado para instalação em iPhone.

## Desenvolvimento e testes

Na pasta `server`:

```powershell
py -3.13 -m venv .venv
.\\.venv\\Scripts\\activate.bat
python -m pip install -r requirements.txt
python -m compileall -q .
python -m unittest discover -s tests -v
```

A compilação de sintaxe e os testes automatizados não substituem testes reais de pesquisa, download e reprodução com dados do Internet Archive.
