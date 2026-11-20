#!/bin/bash
# Compila e instala Apuntes en la tablet conectada por USB
export PATH=~/flutter/bin:$PATH JAVA_HOME=~/Android/jdk21 ANDROID_HOME=~/Android/Sdk
cd "$(dirname "$0")"
flutter build apk --release && adb install -r build/app/outputs/flutter-apk/app-release.apk
