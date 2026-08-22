#!/bin/zsh
set -euo pipefail

# 노터라이즈된 S.tand-macOS-<MARKETING_VERSION>.dmg가 담긴 디렉터리에서 서명된 appcast(stand.xml)를 생성한다.
# 비밀 EdDSA 키는 generate_keys가 저장해 둔 로그인 키체인에서 generate_appcast가 직접 읽는다.
# 이 스크립트는 키를 생성하거나 출력하지 않는다.
#
# 사용법: scripts/make-mac-appcast.sh <release-dir> [download-url-prefix] [generate_appcast 경로]

release_dir="${1:?릴리스 디렉터리가 필요합니다 (S.tand-macOS-<version>.dmg 포함)}"
download_url_prefix="${2:-https://nasfinder.com/downloads/}"
generate_appcast="${3:-generate_appcast}"
sparkle_key_account="${SPARKLE_KEY_ACCOUNT:-STand}"

if ! command -v "${generate_appcast}" >/dev/null 2>&1; then
  echo "generate_appcast를 찾을 수 없습니다. Sparkle 2.9.2 배포 아카이브의 bin/generate_appcast 경로를 세 번째 인자로 지정하세요." >&2
  exit 1
fi

setopt null_glob
dmgs=("${release_dir}"/S.tand-macOS-*.dmg)
if (( ${#dmgs[@]} == 0 )); then
  echo "S.tand-macOS-<version>.dmg 형식의 DMG가 ${release_dir}에 없습니다." >&2
  exit 1
fi

for dmg in "${dmgs[@]}"; do
  if ! xcrun stapler validate "${dmg}" >/dev/null 2>&1; then
    echo "경고: ${dmg}에 노터라이즈 스테이플 확인 실패. 배포 전 노터라이즈 여부를 확인하세요." >&2
  fi
done

"${generate_appcast}" \
  --account "${sparkle_key_account}" \
  --download-url-prefix "${download_url_prefix}" \
  --link "https://nasfinder.com/apps/stand" \
  --maximum-deltas 0 \
  --maximum-versions 3 \
  -o "${release_dir}/stand.xml" \
  "${release_dir}"

echo "생성 완료: ${release_dir}/stand.xml"
echo "업로드 대상: https://nasfinder.com/appcasts/stand.xml (HTTPS 필수)"
