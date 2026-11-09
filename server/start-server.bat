@echo off
setlocal
cd /d "%~dp0"

if not exist ".venv\Scripts\python.exe" (
    echo Ambiente Python nao encontrado. Execute setup.bat primeiro.
    pause
    exit /b 1
)

call ".venv\Scripts\activate.bat"

if "%GMD_ADMIN_PASSWORD%"=="" (
    echo Defina uma senha forte para proteger o painel.
    set /p GMD_ADMIN_PASSWORD=Senha do administrador: 
)

if "%GMD_ADMIN_PASSWORD%"=="" (
    echo A senha e obrigatoria. O servidor nao sera iniciado.
    pause
    exit /b 1
)

python -m uvicorn app:app --host 127.0.0.1 --port 8000
pause
