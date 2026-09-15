@echo off
rem ============================================================
rem  PCelechron - repair Windows icon cache
rem
rem  Symptom it fixes: the shortcut's icon is correct in
rem  "Properties -> Shortcut -> Change Icon", but the desktop
rem  keeps showing the old icon even after reinstalling.
rem  This is a stale per-user icon cache, not an installer bug.
rem
rem  Run this file by double-clicking it. Explorer (taskbar)
rem  will restart briefly - that is expected.
rem ============================================================
setlocal

echo.
echo [1/4] Stopping explorer.exe ...
taskkill /f /im explorer.exe >nul 2>&1
timeout /t 2 /nobreak >nul

echo [2/4] Deleting icon caches ...
del /a /f /q "%LocalAppData%\IconCache.db" >nul 2>&1
del /a /f /q "%LocalAppData%\Microsoft\Windows\Explorer\iconcache*.db" >nul 2>&1
del /a /f /q "%LocalAppData%\Microsoft\Windows\Explorer\thumbcache*.db" >nul 2>&1

echo [3/4] Restarting explorer.exe ...
start "" explorer.exe
timeout /t 2 /nobreak >nul

echo [4/4] Asking the shell to rebuild its icon cache ...
"%SystemRoot%\System32\ie4uinit.exe" -show

echo.
echo Done. The desktop icon should now be refreshed.
echo If it still shows the old icon, right-click the desktop and
echo choose "Refresh", or sign out and sign back in.
echo.
pause
endlocal
