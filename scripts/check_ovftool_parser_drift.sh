#!/usr/bin/env bash
set -euo pipefail

PAGE_URL="${OVFTOOL_PAGE_URL:-https://developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest}"
API_URL="${PAGE_URL}?p_p_id=SDK_AND_TOOL_DETAILS_INSTANCE_iwlk&p_p_lifecycle=2&p_p_state=normal&p_p_mode=view&p_p_resource_id=documentDownloadArtifact&p_p_cacheability=cacheLevelPage"

fail() {
  printf '[parser-drift][error] %s\n' "$*" >&2
  exit 1
}

info() {
  printf '[parser-drift] %s\n' "$*"
}

TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

HTML_FILE="${TMP_DIR}/latest.html"
RESPONSE_FILE="${TMP_DIR}/response.json"

info "Fetching latest OVF Tool page"
curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors "${PAGE_URL}" -o "${HTML_FILE}" || \
  fail "Could not fetch OVF Tool page: ${PAGE_URL}"

FILE_NAME="$({ grep -oE 'VMware-ovftool-[0-9.\-]+-lin\.x86_64\.zip' "${HTML_FILE}" || true; } | head -n1)"
ARTIFACT_ID="$({ grep -oE 'artifactId:[[:space:]]*[0-9]+' "${HTML_FILE}" || true; } | head -n1 | grep -oE '[0-9]+' || true)"
FILE_TYPE_PRESENT="$(grep -c 'fileType:[[:space:]]*"Download"' "${HTML_FILE}" || true)"
ENDPOINT_PRESENT="$(grep -c 'p_p_resource_id=documentDownloadArtifact' "${HTML_FILE}" || true)"

[[ -n "${FILE_NAME}" ]] || fail "Parser drift: Linux filename pattern not found in page"
[[ -n "${ARTIFACT_ID}" ]] || fail "Parser drift: artifactId pattern not found in page JavaScript"
[[ "${FILE_TYPE_PRESENT}" -gt 0 ]] || fail "Parser drift: fileType Download marker missing from page JavaScript"
[[ "${ENDPOINT_PRESENT}" -gt 0 ]] || fail "Parser drift: documentDownloadArtifact endpoint marker missing"

PAYLOAD="$(printf '{"fileName":"%s","artifactId":%s,"fileType":"Download"}' "${FILE_NAME}" "${ARTIFACT_ID}")"

info "Posting schema validation request"
curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors \
  -X POST "${API_URL}" \
  -H 'Content-Type: application/json' \
  --data "${PAYLOAD}" \
  -o "${RESPONSE_FILE}" || fail "Download API POST failed"

DOWNLOAD_URL=""
SUCCESS_FLAG=""
if command -v jq >/dev/null 2>&1; then
  DOWNLOAD_URL="$(jq -r '.data.downloadUrl // empty' "${RESPONSE_FILE}")"
  SUCCESS_FLAG="$(jq -r '.success // empty' "${RESPONSE_FILE}")"
else
  DOWNLOAD_URL="$(python3 - <<'PY' "${RESPONSE_FILE}"
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
print((data.get('data') or {}).get('downloadUrl',''))
PY
)"
  SUCCESS_FLAG="$(python3 - <<'PY' "${RESPONSE_FILE}"
import json, sys
with open(sys.argv[1], 'r', encoding='utf-8') as f:
    data = json.load(f)
print(str(data.get('success','')))
PY
)"
fi

[[ "${SUCCESS_FLAG}" == "true" ]] || fail "Parser drift: API success flag is not true. Response: $(cat "${RESPONSE_FILE}")"
[[ -n "${DOWNLOAD_URL}" ]] || fail "Parser drift: data.downloadUrl missing in API response"

info "Validated parser schema and API response"
info "fileName=${FILE_NAME} artifactId=${ARTIFACT_ID}"
