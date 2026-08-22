#!/bin/zsh
set -euo pipefail

script_dir=${0:A:h}
root_dir=${script_dir:h}
build_dir="${root_dir}/build/macos-release"
archive_path="${build_dir}/STand.xcarchive"
export_dir="${build_dir}/export"
release_dir="${root_dir}/artifacts/macos"
notary_profile="${NOTARY_PROFILE:-ccmb-notary}"
sign_identity="${CODESIGN_IDENTITY:-Developer ID Application: BYOUNG KI HAN (T7B4EPLHPK)}"

build_settings=$(xcodebuild -project "${root_dir}/STand.xcodeproj" -scheme STand \
  -configuration Release -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  -showBuildSettings)
marketing_version=$(print -r -- "${build_settings}" | awk '/ MARKETING_VERSION = / { print $3; exit }')
build_number=$(print -r -- "${build_settings}" | awk '/ CURRENT_PROJECT_VERSION = / { print $3; exit }')

if [[ -z "${marketing_version}" || -z "${build_number}" ]]; then
  print -u2 "S.tand 버전 또는 빌드 번호를 읽지 못했습니다."
  exit 65
fi

dmg_path="${release_dir}/S.tand-macOS-${marketing_version}.dmg"
mkdir -p "${build_dir}" "${release_dir}"
rm -rf -- "${archive_path}" "${export_dir}"

xcodebuild archive \
  -project "${root_dir}/STand.xcodeproj" \
  -scheme STand \
  -configuration Release \
  -destination 'generic/platform=macOS,variant=Mac Catalyst' \
  -archivePath "${archive_path}"

xcodebuild -exportArchive \
  -archivePath "${archive_path}" \
  -exportPath "${export_dir}" \
  -exportOptionsPlist "${root_dir}/Configuration/ExportOptionsMac.plist"

app_path="${export_dir}/S.tand.app"
bridge_path="${app_path}/Contents/PlugIns/STandUpdaterBridge.bundle"
if [[ ! -d "${bridge_path}/Contents/Frameworks/Sparkle.framework" ]]; then
  print -u2 "내보낸 앱에 Sparkle 업데이트 브리지가 없습니다."
  exit 66
fi
if [[ -z "$(plutil -extract SUPublicEDKey raw -o - "${app_path}/Contents/Info.plist")" ]]; then
  print -u2 "내보낸 앱에 Sparkle 공개키가 없습니다."
  exit 66
fi

codesign --verify --deep --strict --verbose=2 "${app_path}"
codesign -dv --verbose=2 "${app_path}" 2>&1 | grep -F "Authority=${sign_identity}"

staging_dir=$(mktemp -d "${build_dir}/dmg.XXXXXX")
ditto "${app_path}" "${staging_dir}/S.tand.app"
ln -s /Applications "${staging_dir}/Applications"
rm -f -- "${dmg_path}"
hdiutil create -volname "S.tand" -srcfolder "${staging_dir}" -fs HFS+ -format UDZO -ov "${dmg_path}"
codesign --force --timestamp --sign "${sign_identity}" "${dmg_path}"

xcrun notarytool submit "${dmg_path}" --keychain-profile "${notary_profile}" --wait
xcrun stapler staple "${dmg_path}"
xcrun stapler staple "${app_path}"
xcrun stapler validate "${dmg_path}"
xcrun stapler validate "${app_path}"
spctl --assess --type open --context context:primary-signature --verbose=4 "${dmg_path}"
spctl --assess --type execute --verbose=4 "${app_path}"

print "완료: S.tand ${marketing_version} (${build_number})"
print "DMG: ${dmg_path}"
