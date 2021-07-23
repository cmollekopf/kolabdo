#!/bin/bash
# ./release.sh v0.1.9
set -x
gh release create $1 --notes "" 'build/app/outputs/apk/release/app-release.apk#kolabdo.apk'
