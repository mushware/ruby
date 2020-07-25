
START "" /B /D "mushware" /WAIT powershell.exe -ExecutionPolicy Bypass -NonInteractive -NoProfile -File build_dll.ps1 "%BUILD_CONFIGURATION%" "%TRAVIS_BUILD_NUMBER%" -InstallMissing
EXIT /B %ERRORLEVEL%
