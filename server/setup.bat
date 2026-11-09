@echo off
setlocal
cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
    py -3.13 -m venv .venv
    if errorlevel 1 (
        echo Nao foi possivel criar o ambiente Python.
        pause
        exit /b 1
    )
)

call ".venv\Scripts\activate.bat"
python -m pip install --upgrade pip
if errorlevel 1 (
    echo Falha ao atualizar o pip.
    pause
    exit /b 1
)
python -m pip install -r requirements.txt
if errorlevel 1 (
    echo Falha ao instalar as dependencias.
    pause
    exit /b 1
)

echo.
echo Instalacao concluida. Execute start-server.bat para iniciar.
pause
