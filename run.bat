@echo off
setlocal
title GameLoop - copy a keymapping between games
cd /d "%~dp0"

:menu
cls
echo ============================================================
echo    GameLoop - copy a keymapping from one game to another
echo ============================================================
echo.
echo    Set your buttons up ONCE, copy them to your other game.
echo.
echo    CLOSE GAMELOOP COMPLETELY FIRST (tray icon too).
echo.
echo ------------------------------------------------------------
echo    1)  Show every game in my config   (nothing is changed)
echo    2)  Copy a keymapping              (the main thing)
echo    3)  Quick copy: PUBG Mobile  -^>  PUBG Mobile Flash
echo    4)  See what would change           (diagnose)
echo    5)  Preview only                    (dry run)
echo    6)  Undo - restore latest backup
echo    7)  Exit
echo ------------------------------------------------------------
echo.
set "choice="
set /p choice="    Choose [1-7]: "

if "%choice%"=="1" goto act_list
if "%choice%"=="2" goto act_copy
if "%choice%"=="3" goto act_quick
if "%choice%"=="4" goto act_diag
if "%choice%"=="5" goto act_dry
if "%choice%"=="6" goto act_restore
if "%choice%"=="7" exit /b

echo.
echo    Not a valid choice.
timeout /t 2 >nul
goto menu

:act_list
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Copy-KeyMapping.ps1" -List
goto done

:act_quick
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Copy-KeyMapping.ps1" -From com.tencent.ig -To com.tencent.igfit
goto done

:act_diag
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Copy-KeyMapping.ps1" -Diagnose
goto done

:act_dry
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Copy-KeyMapping.ps1" -DryRun
goto done

:act_restore
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Copy-KeyMapping.ps1" -Restore
goto done

:act_copy
cls
echo ============================================================
echo    Copy a keymapping
echo ============================================================
echo.
echo    COPY FROM  = the game you already set your buttons up in.
echo    COPY TO    = the game you want them copied onto.
echo.
echo    Common package names:
echo       com.tencent.ig        PUBG Mobile
echo       com.tencent.igfit     PUBG Mobile (Flash / Lite client)
echo       com.dts.freefireth    Free Fire
echo       com.garena.game.kgth  Garena Free Fire
echo.
echo    Not sure? Press 1 on the menu first.
echo    Your "copy to" game must have been opened in GameLoop at
echo    least once, or it will not be in the list yet.
echo.
set "srcpkg="
set /p srcpkg="    COPY FROM (package name): "
if "%srcpkg%"=="" goto menu
set "dstpkg="
set /p dstpkg="    COPY TO   (package name): "
if "%dstpkg%"=="" goto menu
echo.
echo    %srcpkg%  -^>  %dstpkg%
echo.
powershell -NoProfile -ExecutionPolicy Bypass -File "%~dp0Copy-KeyMapping.ps1" -From "%srcpkg%" -To "%dstpkg%"
goto done

:done
echo.
echo ------------------------------------------------------------
pause
goto menu
