@echo off
cd /d "%~dp0"
python -m http.server 5000 --directory build\web
