#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
root_dir=${script_dir:h}
archive_dir="${root_dir}/artifacts/ios"
archive_path="${archive_dir}/S.tand-TestFlight.xcarchive"
export_path="${archive_dir}/TestFlight-upload"

build_settings=$(xcodebuild -project "${root_dir}/STand.xcodeproj" -scheme STand -configuration Release -showBuildSettings)
marketing_version=$(print -r -- "$build_settings" | awk '/ MARKETING_VERSION = / { print $3; exit }')
build_number=$(print -r -- "$build_settings" | awk '/ CURRENT_PROJECT_VERSION = / { print $3; exit }')

if [[ -z "$marketing_version" || -z "$build_number" ]]; then
  print -u2 'S.tand 버전 또는 빌드 번호를 읽지 못했습니다.'
  exit 65
fi

if ! security find-identity -v -p codesigning | grep -q 'Apple Distribution'; then
  print -u2 'App Store 배포 인증서를 찾지 못했습니다. 기존 Xcode App Store Connect 계정 연결을 복구한 뒤 다시 실행하세요.'
  exit 69
fi

mkdir -p "$archive_dir"
xcodebuild archive \
  -project "${root_dir}/STand.xcodeproj" \
  -scheme STand \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  -allowProvisioningUpdates

xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "${root_dir}/Configuration/ExportOptionsAppStore.plist" \
  -allowProvisioningUpdates

print "TestFlight 업로드 요청 완료: S.tand ${marketing_version} (${build_number})"
