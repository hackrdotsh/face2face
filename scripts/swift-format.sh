#!/usr/bin/env bash
set -euo pipefail

exec swift-format "$@" --recursive \
  apps/ios/Face2FaceCore/Package.swift \
  apps/ios/Face2Face \
  apps/ios/Face2FaceCore/Sources \
  apps/ios/Face2FaceCore/Tests
