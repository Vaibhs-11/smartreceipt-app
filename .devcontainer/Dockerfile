# Base image
FROM mcr.microsoft.com/vscode/devcontainers/base:ubuntu

# Install general dependencies
RUN apt-get update && apt-get install -y git curl unzip xz-utils zip libglu1-mesa openjdk-11-jdk wget

# Install Flutter (stable channel)
RUN git clone https://github.com/flutter/flutter.git -b stable /usr/local/flutter
ENV PATH="/usr/local/flutter/bin:/usr/local/flutter/bin/cache/dart-sdk/bin:${PATH}"

# Run flutter doctor (may take a bit)
RUN /usr/local/flutter/bin/flutter --version || true
