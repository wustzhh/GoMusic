@echo off
cd /d "%~dp0"
set JAVA_HOME=D:\app-dev\jdk\jdk-17.0.16+8
set ANDROID_HOME=D:\app-dev\android-sdk
set ANDROID_SDK_ROOT=D:\app-dev\android-sdk
set PATH=%JAVA_HOME%\bin;%PATH%
echo Building APK...
D:\app-dev\flutter\bin\flutter build apk --release
if %errorlevel% equ 0 (
  echo.
  echo APK built successfully!
  echo Location: build\app\outputs\flutter-apk\app-release.apk
) else (
  echo Build failed!
)
pause
