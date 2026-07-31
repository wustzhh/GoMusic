@echo off
cd /d "%~dp0"
call gradlew.bat assembleDebug
if exist "app\build\outputs\apk\debug\app-debug.apk" (
    copy /y "app\build\outputs\apk\debug\app-debug.apk" "GoMusic.apk"
    echo.
    echo APK已生成: GoMusic.apk
) else (
    echo 编译失败
)
pause
