#!/bin/bash
set -e

# Accept Android SDK licenses
yes | sdkmanager --sdk_root=$ANDROID_SDK_ROOT --licenses

# Install required Android SDK components
sdkmanager --sdk_root=$ANDROID_SDK_ROOT \
    "platform-tools" \
    "platforms;android-34" \
    "build-tools;34.0.0"

# Pre-cache Flutter dependencies
flutter precache

# Configure Flutter to use the installed SDK
flutter config --android-sdk $ANDROID_SDK_ROOT

# Run doctor to verify setup
flutter doctor
