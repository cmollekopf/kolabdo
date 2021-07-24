#!/bin/bash
# ./release.sh v0.1.9
set -x
flutter build apk --release
cp build/app/outputs/apk/release/app-release.apk kolabdo.apk
gh release create $1 --notes "" 'kolabdo.apk#kolabdo.apk'
