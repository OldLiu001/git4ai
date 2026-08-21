@echo off
setlocal
rem git4ai (Go / Windows) build & install script
rem  1) build bin\git.exe with Go
rem  2) copy to %USERPROFILE%\.git4ai\bin\git.exe (user level)
rem  3) prepend that dir to user PATH so it shadows the real git (with length guard)
rem NOTE: keep this file ASCII-only; cmd parses .bat in the OEM codepage and
rem       non-ASCII can break lines.

set "ROOT=%~dp0"
set "DEST=%USERPROFILE%\.git4ai\bin"

rem ---- check go ----
where go >nul 2>nul
if errorlevel 1 (
  echo [x] 'go' not found on PATH. Add Go's bin dir to PATH first, then retry.
  exit /b 1
)

echo [*] building git.exe ...
pushd "%ROOT%"
go build -o "bin\git.exe" .
if errorlevel 1 ( popd & echo [x] build failed. & exit /b 1 )
popd
echo [+] built: %ROOT%bin\git.exe

rem ---- copy to user dir ----
if not exist "%DEST%" mkdir "%DEST%"
copy /y "%ROOT%bin\git.exe" "%DEST%\git.exe" >nul
echo [+] installed: %DEST%\git.exe

rem ---- prepend to user PATH (idempotent, length-guarded) ----
powershell -NoProfile -ExecutionPolicy Bypass -Command "$d='%DEST%';$p=[Environment]::GetEnvironmentVariable('Path','User');if($p -and (($p -split ';') -contains $d)){Write-Host '[i] already in user PATH, skipped.'}else{$np=$d;if($p){$np=$d+';'+$p};if($np.Length -gt 1024){Write-Host ('[w] new PATH length '+$np.Length+' >1024; NOT auto-set. Add the dir to user Path (front) manually.' ) }else{[Environment]::SetEnvironmentVariable('Path',$np,'User');Write-Host ('[+] prepended to user PATH: '+$d)}}"

echo.
echo -- verify (open a NEW terminal) --
echo   git --version          # should print git version (passthrough)
echo   git commit -m "short"  # should be rejected by git4ai
echo   Note: only applies to shells that resolve git via PATH (cmd / PowerShell /
echo         some IDEs). Direct git.exe absolute-path or tool-internal git bypass it.
endlocal