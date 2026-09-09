#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
root_dir=${script_dir:h}
archive_dir="${root_dir}/artifacts/ios"
archive_path="${archive_dir}/S.tand-TestFlight.xcarchive"
export_path="${archive_dir}/TestFlight-upload"
asc_key_path="${STAND_ASC_KEY_PATH:-/Users/armsone/.private_keys/AuthKey_6YU37JNN2D.p8}"
asc_key_id="${STAND_ASC_KEY_ID:-6YU37JNN2D}"
asc_issuer_id="${STAND_ASC_ISSUER_ID:-69a6de89-aa4c-47e3-e053-5b8c7c11a4d1}"

build_settings=$(xcodebuild -project "${root_dir}/STand.xcodeproj" -scheme STand -configuration Release -showBuildSettings)
marketing_version=$(print -r -- "$build_settings" | awk '/ MARKETING_VERSION = / { print $3; exit }')
build_number=$(print -r -- "$build_settings" | awk '/ CURRENT_PROJECT_VERSION = / { print $3; exit }')

if [[ -z "$marketing_version" || -z "$build_number" ]]; then
  print -u2 'S.tand 버전 또는 빌드 번호를 읽지 못했습니다.'
  exit 65
fi

if [[ ! -r "$asc_key_path" || -z "$asc_key_id" || -z "$asc_issuer_id" ]]; then
  print -u2 '기존 App Store Connect 인증키 설정을 찾지 못했습니다.'
  exit 69
fi

mkdir -p "$archive_dir"
xcodebuild archive \
  -project "${root_dir}/STand.xcodeproj" \
  -scheme STand \
  -configuration Release \
  -destination 'generic/platform=iOS' \
  -archivePath "$archive_path" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$asc_key_path" \
  -authenticationKeyID "$asc_key_id" \
  -authenticationKeyIssuerID "$asc_issuer_id"

xcodebuild -exportArchive \
  -archivePath "$archive_path" \
  -exportPath "$export_path" \
  -exportOptionsPlist "${root_dir}/Configuration/ExportOptionsAppStore.plist" \
  -allowProvisioningUpdates \
  -authenticationKeyPath "$asc_key_path" \
  -authenticationKeyID "$asc_key_id" \
  -authenticationKeyIssuerID "$asc_issuer_id"

print "TestFlight 업로드 요청 완료: S.tand ${marketing_version} (${build_number})"
