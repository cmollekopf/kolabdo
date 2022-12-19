#!/bin/bash
set -x
set -e
VERSION=$(grep version: pubspec.yaml | sed "s/version: //")
flutter build apk --release
cp build/app/outputs/apk/release/app-release.apk kolabdo.apk
gh release create "v$VERSION" --notes "New release" "kolabdo.apk#kolabdo.apk"
