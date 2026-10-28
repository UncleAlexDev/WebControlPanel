@echo on
@call :GET_CURRENT_DATE

:: -----------------------------------------------
@setlocal enabledelayedexpansion

@SET PRJNAME=bbi2-wcp
@SET BINDIR=www\cgi-bin\esz7
@SET EXEFILE=%BINDIR%\control
@SET DEPLOY_DIR=..\%PRJNAME%-deploy

:: -----------------------------------------------

@SET FILES=cgi-bin index.html favicon.ico logo-64.png sha256.min.js

:: -----------------------------------------------
@IF NOT EXIST "!EXEFILE!" (
    @echo.
    @echo ERROR: !EXEFILE! - file not found
    @echo.
    @pause
    @exit /b 1
)

:: -----------------------------------------------
@for /f "tokens=1" %%A in (%BINDIR%\VERSION) do @(
    @set "VERSION=%%~A"
)
@echo VER: %VERSION%

:: -----------------------------------------------
@SET TARGET_BIN_DIR=..\%PRJNAME%-%VERSION%-bin-%DT%
@SET TARGET_SRC_DIR=..\%PRJNAME%-%VERSION%-src-%DT%

@rd /s /q %TARGET_BIN_DIR% 2>NUL 
@rd /s /q %TARGET_SRC_DIR% 2>NUL

@if not exist "%TARGET_BIN_DIR%" mkdir "%TARGET_BIN_DIR%"

@xcopy /E /Y /I /V /Q www\* "%TARGET_BIN_DIR%\" >NUL
@if "%ERRORLEVEL%" NEQ "0" (
    @echo.
    @echo ERROR: failed to copy 'www' files to %TARGET_BIN_DIR%
    @echo.
    @pause
    @exit /b 1
)

@xcopy /S /Y /I /V /Q * %TARGET_SRC_DIR%\* >NUL
@if "%ERRORLEVEL%" NEQ "0" (
    @echo.
    @echo ERROR: failed to copy files to %TARGET_SRC_DIR%
    @echo.
    @pause
    @exit /b 1
)

:: -----------------------------------------------
@del /f /q %TARGET_BIN_DIR%.zip 2>NUL
@del /f /q %TARGET_SRC_DIR%.zip 2>NUL

7z a -tzip -bb0 %TARGET_BIN_DIR%.zip %TARGET_BIN_DIR% >NUL
@if "%ERRORLEVEL%" NEQ "0" (
    @echo error for %TARGET_BIN_DIR%.zip
    @pause
    @exit /b 1
)
@rd /s /q %TARGET_BIN_DIR% 2>NUL 

7z a -tzip -bb0 %TARGET_SRC_DIR%.zip %TARGET_SRC_DIR% >NUL
@if "%ERRORLEVEL%" NEQ "0" (
    @echo error for %TARGET_SRC_DIR%.zip
    @pause
    @exit /b 1
)
@rd /s /q %TARGET_SRC_DIR% 2>NUL

:: -----------------------------------------------
@mkdir %DEPLOY_DIR% 2>NUL
@move /Y %TARGET_BIN_DIR%.zip %DEPLOY_DIR%\ >NUL
@move /Y %TARGET_SRC_DIR%.zip %DEPLOY_DIR%\ >NUL

:: -----------------------------------------------
@echo.
@echo The package was built successfully
@echo.


:: -----------------------------------------------
:GET_CURRENT_DATE
@set dt=%date: =0%
@set dt=%dt:~6,4%%dt:~3,2%%dt:~0,2%
@set tm=%time: =0%
@set tm=%tm:~0,2%%tm:~3,2%%tm:~6,2%
@set DT=%dt%-%tm%
@echo Date/Time stamp: %DT%
@exit /b 0
