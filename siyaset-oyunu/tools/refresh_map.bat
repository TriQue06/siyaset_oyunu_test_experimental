@echo off
REM assets/maps/turkey_map.png'i her degistirdiginde bu dosyaya cift tikla:
REM 1) data/province_pixel_map.json'i yeni PNG'den yeniden uretir
REM 2) Godot'un PNG import onbellegini zorla yeniler
REM boylece oyunu (yeniden) actiginda harita hep GUNCEL olur.

cd /d "%~dp0\.."

echo [1/2] Piksel haritasi yeniden uretiliyor...
node tools\refresh_map.js
if errorlevel 1 goto :error

echo.
echo [2/2] Godot import onbellegi yenileniyor...
"C:\Users\baris\Downloads\godot_extracted\Godot_v4.7.1-stable_win64_console.exe" --headless --path . --import >nul 2>&1

echo.
echo TAMAM. Oyunu (yeniden) baslatabilirsin.
pause
exit /b 0

:error
echo.
echo HATA olustu, yukaridaki mesaja bak.
pause
exit /b 1
