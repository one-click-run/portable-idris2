@echo off
setlocal
set "ROOT=%~dp0"
for /f "delims=" %%F in ('dir /b /s "%ROOT%data\pack-state\install\idris2.cmd" 2^>nul') do if not defined MANAGED_IDRIS set "MANAGED_IDRIS=%%~fF"
if not defined MANAGED_IDRIS (
  >&2 echo The Pack-managed Idris 2 compiler is missing.
  exit /b 2
)
for %%D in ("%MANAGED_IDRIS%") do set "IDRIS2_BIN=%%~dpD"
for %%D in ("%IDRIS2_BIN%..") do set "IDRIS2_PREFIX=%%~fD"
set "CHEZ=scheme"
set "SCHEME=scheme"
set "HOME=%ROOT%data\home"
set "PACK_USER_DIR=%ROOT%data\pack-config"
set "PACK_STATE_DIR=%ROOT%data\pack-state"
set "PACK_CACHE_DIR=%ROOT%data\pack-cache"
set "PACK_BIN_DIR=%ROOT%bin"
set "GIT_CONFIG_GLOBAL=%ROOT%data\gitconfig"
set "XDG_CACHE_HOME=%ROOT%data\xdg-cache"
set "XDG_CONFIG_HOME=%ROOT%data\xdg-config"
set "XDG_DATA_HOME=%ROOT%data\xdg-data"
set "XDG_STATE_HOME=%ROOT%data\xdg-state"
set "ONE_CLICK_RUN_OFFLINE_RUNTIME=1"
set "MSYSTEM=MINGW64"
set "MSYS2_PATH_TYPE=inherit"
set "IDRIS2_CC=gcc"
set "PATH=%ROOT%bin;%IDRIS2_BIN%;%ROOT%chez\bin\ta6nt;%ROOT%runtime;%ROOT%msys2\mingw64\bin;%ROOT%msys2\usr\bin;%PATH%"
call "%ROOT%bin\idris2-lsp.cmd" %*
exit /b %ERRORLEVEL%
