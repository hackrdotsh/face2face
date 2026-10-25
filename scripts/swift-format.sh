#!/usr/bin/env bash
set -euo pipefail

formatter=$(command -v swift-format || xcrun --find swift-format)
exec "$formatter" "$@" --recursive \
  apps/ios/Face2FaceCore/Package.swift \
  apps/ios/Face2Face \
  apps/ios/Face2FaceSurfaces \
  apps/ios/Face2FaceWidgets \
  apps/ios/Face2FaceTests \
  apps/ios/Face2FaceUITests \
  apps/ios/Face2FaceCore/Sources \
  apps/ios/Face2FaceCore/Tests
