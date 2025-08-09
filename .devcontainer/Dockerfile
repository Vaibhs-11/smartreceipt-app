FROM mcr.microsoft.com/devcontainers/base:ubuntu

# Install base dependencies
RUN apt-get update && apt-get install -y \
    curl unzip wget git openjdk-17-jdk \
    libglu1-mesa \
    && apt-get clean

# Install Flutter
RUN git clone https://github.com/flutter/flutter.git /usr/local/flutter
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Install Android Command Line Tools
RUN mkdir -p /usr/local/android-sdk/cmdline-tools \
    && wget https://dl.google.com/android/repository/commandlinetools-linux-11076708_latest.zip -O /tmp/cmdline-tools.zip \
    && unzip /tmp/cmdline-tools.zip -d /usr/local/android-sdk/cmdline-tools \
    && mv /usr/local/android-sdk/cmdline-tools/cmdline-tools /usr/local/android-sdk/cmdline-tools/latest

# Set Android SDK environment variables
ENV ANDROID_SDK_ROOT=/usr/local/android-sdk
ENV PATH="${ANDROID_SDK_ROOT}/cmdline-tools/latest/bin:${ANDROID_SDK_ROOT}/platform-tools:${PATH}"
