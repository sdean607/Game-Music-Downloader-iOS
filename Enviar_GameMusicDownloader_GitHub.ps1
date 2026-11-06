$ErrorActionPreference = "Stop"

$RepoUrl = "https://github.com/sdean607/Game-Music-Downloader-iOS.git"
$Branch = "main"

Write-Host ""
Write-Host "Game Music Downloader - envio seguro para o GitHub" -ForegroundColor Cyan
Write-Host "Pasta: $((Get-Location).Path)"
Write-Host ""

# Confere se o Git está instalado.
if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw "Git não encontrado. Instale o Git for Windows em https://git-scm.com/download/win e execute este script novamente."
}

# Evita enviar a partir da pasta errada.
if (-not (Test-Path ".\GameMusicDownloader.xcodeproj\project.pbxproj")) {
    throw "Projeto Xcode não encontrado nesta pasta. Abra o PowerShell dentro da pasta GameMusicDownloader (a que contém GameMusicDownloader.xcodeproj)."
}

# Inicializa o repositório local, se necessário.
if (-not (Test-Path ".git")) {
    git init
    if ($LASTEXITCODE -ne 0) { throw "Falha ao inicializar o Git." }
}

# Garante a branch main.
git branch -M $Branch
if ($LASTEXITCODE -ne 0) { throw "Não foi possível selecionar a branch main." }

# Configura ou valida o remoto.
$ExistingRemote = git remote get-url origin 2>$null
if ($LASTEXITCODE -eq 0 -and $ExistingRemote) {
    if ($ExistingRemote.Trim() -ne $RepoUrl) {
        throw "Já existe um remoto 'origin' diferente: $ExistingRemote. O script parou para não enviar ao repositório errado."
    }
} else {
    git remote add origin $RepoUrl
    if ($LASTEXITCODE -ne 0) { throw "Não foi possível configurar o remoto do GitHub." }
}

# Confere se a branch remota está vazia. Se já houver commits, não sobrescreve.
git ls-remote --exit-code --heads origin $Branch *> $null
$RemoteCheck = $LASTEXITCODE
if ($RemoteCheck -eq 0) {
    throw "A branch main já existe no GitHub. O script parou para evitar sobrescrever alterações remotas."
}
if ($RemoteCheck -ne 2) {
    throw "Não foi possível verificar o GitHub. Confira a conexão e a autenticação do Git."
}

# Prepara e cria o commit.
git add .
if ($LASTEXITCODE -ne 0) { throw "Falha ao adicionar os arquivos." }

git diff --cached --quiet
if ($LASTEXITCODE -eq 0) {
    throw "Não há alterações para enviar. Verifique se os arquivos do projeto estão nesta pasta."
}
if ($LASTEXITCODE -gt 1) { throw "Falha ao verificar as alterações preparadas." }

git commit -m "Publish Game Music Downloader project"
if ($LASTEXITCODE -ne 0) { throw "Falha ao criar o commit. Configure seu nome/e-mail Git e tente novamente." }

# Publica a branch e inicia o workflow configurado para push.
git push -u origin $Branch
if ($LASTEXITCODE -ne 0) {
    throw "O envio falhou. Nenhum sucesso foi confirmado. Verifique a autenticação do GitHub e tente novamente."
}

Write-Host ""
Write-Host "Envio concluído. O GitHub Actions deve iniciar o workflow de iOS." -ForegroundColor Green
Write-Host "Acompanhe em: https://github.com/sdean607/Game-Music-Downloader/actions"
Write-Host ""
