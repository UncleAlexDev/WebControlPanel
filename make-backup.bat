@echo on
@call :GET_CURRENT_DATE

:: -----------------------------------------------

@SET BINDIR=www\cgi-bin\esz7
@for /f "tokens=1" %%A in (%BINDIR%\VERSION) do @(
    @set "VERSION=%%~A"
)
@echo VER: %VERSION%

:: -----------------------------------------------

@SET PRJNAME=bbi2-wcp
@SET BACKUPDIR=..\%PRJNAME%-backups
@SET BACKUPNAME=%PRJNAME%-%VERSION%-%DT%

:: -----------------------------------------------

@SET tmpdir=..\%PRJNAME%-%VERSION%-%DT%
@rd /s /q %tmpdir% 2>NUL
:: @mkdir %tmpdir%\%PRJNAME% >NUL

xcopy /S /Y /V . "%tmpdir%\"
@if "%ERRORLEVEL%" NEQ "0" (
    @echo ERROR: can't copy to %target%
    @pause
    @goto :EOF
)

:: -----------------------------------------------

@mkdir %BACKUPDIR% 2>NUL
7z a -tzip %BACKUPDIR%\%BACKUPNAME%.zip %tmpdir% 
@if "%ERRORLEVEL%" NEQ "0" (
    @echo ERROR: Can't pack %tmpdir% to %BACKUPDIR%\%BACKUPNAME%.zip
)
@rd /s /q %tmpdir% 2>NUL

:: -----------------------------------------------
@goto :EOF

:: -----------------------------------------------
:GET_CURRENT_DATE
@set dt=%date: =0%
@set dt=%dt:~6,4%%dt:~3,2%%dt:~0,2%
@set tm=%time: =0%
@set tm=%tm:~0,2%%tm:~3,2%%tm:~6,2%
@set DT=%dt%-%tm%
@echo Date/Time stamp: %DT%
@exit /b 0
