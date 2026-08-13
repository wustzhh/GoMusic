@echo off
chcp 65001 >nul
cd /d "%~dp0"

echo ========================================
echo   GoMusic 构建脚本 (Windows + Android)
echo ========================================

set JAVA_HOME=D:\app-dev\jdk\jdk-17.0.16+8
set GRADLE_USER_HOME=D:\Dependencies\gradle

REM --- 临时 patch gradle.properties（构建后还原） ---
python -c "import re; p='android/gradle.properties'; c=open(p,encoding='utf-8').read(); c=re.sub(r'org.gradle.java.home=.*', 'org.gradle.java.home=D:/app-dev/jdk/jdk-17.0.16+8', c); open(p,'w',encoding='utf-8').write(c)"

echo.
echo [1/2] 构建 Windows 版...
call D:\app-dev\flutter\bin\flutter.bat build windows
if errorlevel 1 (
    echo Windows 构建失败!
    goto :restore
)

echo.
echo [2/2] 构建 Android APK...
call D:\app-dev\flutter\bin\flutter.bat build apk --release
if errorlevel 1 (
    echo APK 构建失败!
    goto :restore
)

:restore
REM --- 还原 gradle.properties ---
git checkout android/gradle.properties 2>nul

echo.
echo ========================================
echo  Windows: build\windows\x64\runner\Release\gomusic.exe
echo  APK:     build\app\outputs\flutter-apk\app-release.apk
echo ========================================
pause
