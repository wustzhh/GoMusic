@echo off
cd /d "%~dp0"

echo ========================================
echo   GoMusic Build (Windows + Android)
echo ========================================

set JAVA_HOME=D:\app-dev\jdk\jdk-17.0.16+8
set GRADLE_USER_HOME=D:\Dependencies\gradle

REM --- patch gradle.properties for local JDK (restored after build) ---
python -c "import re; p='android/gradle.properties'; c=open(p,encoding='utf-8').read(); c=re.sub(r'org.gradle.java.home=.*', 'org.gradle.java.home=D:/app-dev/jdk/jdk-17.0.16+8', c); open(p,'w',encoding='utf-8').write(c)"

echo.
echo [1/2] Building Windows...
call D:\app-dev\flutter\bin\flutter.bat build windows
if errorlevel 1 (
    echo Windows build FAILED!
    goto :restore
)

echo.
echo [2/2] Building Android APK...
call D:\app-dev\flutter\bin\flutter.bat build apk --release
if errorlevel 1 (
    echo APK build FAILED!
    goto :restore
)

:restore
REM --- restore gradle.properties ---
git checkout android/gradle.properties 2>nul

echo.
echo ========================================
echo  Windows: build\windows\x64\runner\Release\gomusic.exe
echo  APK:     build\app\outputs\flutter-apk\app-release.apk
echo ========================================
pause
