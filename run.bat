@echo off
setlocal
cd /d "%~dp0"

:MENU
cls
echo.
echo   ===== Spells ^& Items by LLM =====
echo.
echo   -- SINGLE ITEM --
echo   1.  Save ONE page             (prompt for category + slug/URL)
echo   2.  Parse ONE page            (prompt for category + html path)
echo.
echo   -- SPELLS --
echo   11. Extract spell links       (source/spells.html  -^>  data/spells-index.json)
echo   12. Save ALL spell pages      (download all from index)
echo   13. Parse ALL spell pages     (source/spells/*.html -^>  data/spells/*.json)
echo   14. Build spells.js           (data/spells/*.json  -^>  web/spells.js)
echo   19. FULL spell pipeline       (11 -^> 12 -^> 13 -^> 14)
echo.
echo   -- ITEMS --
echo   21. Extract item links        (source/items.html   -^>  data/items-index.json)
echo   22. Save ALL item pages       (download all from index)
echo   23. Parse ALL item pages      (source/items/*.html -^>  data/items/*.json)
echo   24. Build items.js            (data/items/*.json  -^>  web/items.js)
echo   29. FULL item pipeline        (21 -^> 22 -^> 23 -^> 24)
echo.
echo   -- COMMON --
echo   8.  Pack web archive          (web/*  -^>  dist/spells-and-items-web.zip)
echo   9.  FULL pipeline (both)      (19 + 29 + 8)
echo.
echo   0.  Exit
echo.
set /p "CHOICE=Choose: "

if "%CHOICE%"=="1"  goto ONE_SAVE
if "%CHOICE%"=="2"  goto ONE_PARSE
if "%CHOICE%"=="11" goto SPELLS_EXTRACT
if "%CHOICE%"=="12" goto SPELLS_SAVE
if "%CHOICE%"=="13" goto SPELLS_PARSE
if "%CHOICE%"=="14" goto SPELLS_BUILD
if "%CHOICE%"=="19" goto SPELLS_FULL
if "%CHOICE%"=="21" goto ITEMS_EXTRACT
if "%CHOICE%"=="22" goto ITEMS_SAVE
if "%CHOICE%"=="23" goto ITEMS_PARSE
if "%CHOICE%"=="24" goto ITEMS_BUILD
if "%CHOICE%"=="29" goto ITEMS_FULL
if "%CHOICE%"=="8"  goto PACK
if "%CHOICE%"=="9"  goto ALL_FULL
if "%CHOICE%"=="0"  goto END
goto MENU

:: ============================================================
:: SINGLE ITEM
:: ============================================================

:ONE_SAVE
cls
set "CAT="
set /p "CAT=Category [s=spell, i=item] (empty to cancel): "
if not defined CAT goto MENU
if /i "%CAT%"=="s" goto ONE_SAVE_SPELL
if /i "%CAT%"=="i" goto ONE_SAVE_ITEM
echo Invalid category.
pause
goto MENU

:ONE_SAVE_SPELL
cls
set "SLUG="
set /p "SLUG=Enter spell slug or URL (empty to cancel): "
if not defined SLUG goto MENU
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\spells\Save-SpellPage.ps1" -Spell "%SLUG%" -NoPause
echo.
pause
goto MENU

:ONE_SAVE_ITEM
cls
set "SLUG="
set /p "SLUG=Enter item slug or URL (empty to cancel): "
if not defined SLUG goto MENU
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\items\Save-ItemPage.ps1" -Item "%SLUG%" -NoPause
echo.
pause
goto MENU

:ONE_PARSE
cls
set "CAT="
set /p "CAT=Category [s=spell, i=item] (empty to cancel): "
if not defined CAT goto MENU
if /i "%CAT%"=="s" goto ONE_PARSE_SPELL
if /i "%CAT%"=="i" goto ONE_PARSE_ITEM
echo Invalid category.
pause
goto MENU

:ONE_PARSE_SPELL
cls
set "HTMLFILE="
set /p "HTMLFILE=Enter path to HTML, or slug in source\spells (empty to cancel): "
if not defined HTMLFILE goto MENU
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\spells\Parse-Spell.ps1" -Path "%HTMLFILE%" -NoPause
echo.
pause
goto MENU

:ONE_PARSE_ITEM
cls
set "HTMLFILE="
set /p "HTMLFILE=Enter path to HTML in source\items (empty to cancel): "
if not defined HTMLFILE goto MENU
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\items\Parse-Item.ps1" -InputPath "%HTMLFILE%" -NoPause
echo.
pause
goto MENU

:: ============================================================
:: SPELLS
:: ============================================================

:SPELLS_EXTRACT
cls
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\spells\Extract-SpellLinks.ps1" -NoPause
echo.
pause
goto MENU

:SPELLS_SAVE
cls
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\spells\Save-AllSpells.ps1" -NoPause
echo.
pause
goto MENU

:SPELLS_PARSE
cls
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\spells\Parse-AllSpells.ps1" -NoPause
echo.
pause
goto MENU

:SPELLS_BUILD
cls
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\common\Build-SpellWebData.ps1" -NoPause
echo.
pause
goto MENU

:SPELLS_FULL
cls
echo === SPELLS: full pipeline ===
echo.
call :RUN_SPELLS_PIPELINE
if errorlevel 1 goto PIPELINE_FAIL
echo.
echo === SPELLS: full pipeline done ===
pause
goto MENU

:: ============================================================
:: ITEMS
:: ============================================================

:ITEMS_EXTRACT
cls
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\items\Extract-ItemLinks.ps1" -NoPause
echo.
pause
goto MENU

:ITEMS_SAVE
cls
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\items\Save-AllItems.ps1" -NoPause
echo.
pause
goto MENU

:ITEMS_PARSE
cls
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\items\Parse-AllItems.ps1" -NoPause
echo.
pause
goto MENU

:ITEMS_BUILD
cls
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\common\Build-ItemWebData.ps1" -NoPause
echo.
pause
goto MENU

:ITEMS_FULL
cls
echo === ITEMS: full pipeline ===
echo.
call :RUN_ITEMS_PIPELINE
if errorlevel 1 goto PIPELINE_FAIL
echo.
echo === ITEMS: full pipeline done ===
pause
goto MENU

:: ============================================================
:: COMMON
:: ============================================================

:PACK
cls
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\common\Pack-DataWeb.ps1" -NoPause
echo.
pause
goto MENU

:ALL_FULL
cls
echo === FULL PIPELINE: spells + items + pack ===
echo.
echo ===== SPELLS =====
echo.
call :RUN_SPELLS_PIPELINE
if errorlevel 1 goto PIPELINE_FAIL
echo.
echo ===== ITEMS =====
echo.
call :RUN_ITEMS_PIPELINE
if errorlevel 1 goto PIPELINE_FAIL
echo.
echo ===== PACK =====
echo.
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\common\Pack-DataWeb.ps1" -NoPause
if errorlevel 1 goto PIPELINE_FAIL
echo.
echo === FULL PIPELINE done ===
pause
goto MENU

:: ============================================================
:: SUBROUTINES
:: ============================================================

:RUN_SPELLS_PIPELINE
echo --- Step 1/4: Extract spell links ---
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\spells\Extract-SpellLinks.ps1" -NoPause
if errorlevel 1 exit /b 1
echo.
echo --- Step 2/4: Save ALL spell pages ---
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\spells\Save-AllSpells.ps1" -NoPause
if errorlevel 1 exit /b 1
echo.
echo --- Step 3/4: Parse ALL spell pages ---
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\spells\Parse-AllSpells.ps1" -NoPause
if errorlevel 1 exit /b 1
echo.
echo --- Step 4/4: Build spells.js ---
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\common\Build-SpellWebData.ps1" -NoPause
if errorlevel 1 exit /b 1
goto :eof

:RUN_ITEMS_PIPELINE
echo --- Step 1/4: Extract item links ---
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\items\Extract-ItemLinks.ps1" -NoPause
if errorlevel 1 exit /b 1
echo.
echo --- Step 2/4: Save ALL item pages ---
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\items\Save-AllItems.ps1" -NoPause
if errorlevel 1 exit /b 1
echo.
echo --- Step 3/4: Parse ALL item pages ---
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\items\Parse-AllItems.ps1" -NoPause
if errorlevel 1 exit /b 1
echo.
echo --- Step 4/4: Build items.js ---
powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0scripts\common\Build-ItemWebData.ps1" -NoPause
if errorlevel 1 exit /b 1
goto :eof

:PIPELINE_FAIL
echo.
echo *** PIPELINE ABORTED: a step failed (see errors above) ***
pause
goto MENU

:END
endlocal
exit /b 0