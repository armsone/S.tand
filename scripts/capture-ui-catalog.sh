#!/bin/zsh
set -euo pipefail

script_dir="${0:A:h}"
project_dir="${script_dir:h}"
artifact_dir="${project_dir}/artifacts/ui-catalog"
derived_data_dir="${project_dir}/DerivedData/UICatalog"
result_bundle="${artifact_dir}/STand-UICatalog.xcresult"
attachment_dir="${artifact_dir}/attachments"
screenshot_dir="${artifact_dir}/screenshots"

mkdir -p "${artifact_dir}"
rm -rf "${result_bundle}" "${attachment_dir}" "${screenshot_dir}"
rm -f "${artifact_dir}/index.html" "${artifact_dir}/manifest.json"

xcodebuild test \
  -project "${project_dir}/STand.xcodeproj" \
  -scheme STand \
  -destination 'platform=iOS Simulator,name=iPhone 17 Pro' \
  -only-testing:STandUITests/STandUICatalogTests/testCaptureUICatalog \
  -parallel-testing-enabled NO \
  -maximum-parallel-testing-workers 1 \
  -derivedDataPath "${derived_data_dir}" \
  -resultBundlePath "${result_bundle}"

mkdir -p "${attachment_dir}"
xcrun xcresulttool export attachments \
  --path "${result_bundle}" \
  --output-path "${attachment_dir}"

"${script_dir}/make-ui-catalog-index.sh" "${attachment_dir}" "${artifact_dir}"

echo "UI catalog: ${artifact_dir}/index.html"
