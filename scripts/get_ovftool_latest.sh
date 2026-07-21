#!/usr/bin/env bash
set -euo pipefail

PAGE_URL="${OVFTOOL_PAGE_URL:-https://developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest}"
API_URL="${PAGE_URL}?p_p_id=SDK_AND_TOOL_DETAILS_INSTANCE_iwlk&p_p_lifecycle=2&p_p_state=normal&p_p_mode=view&p_p_resource_id=documentDownloadArtifact&p_p_cacheability=cacheLevelPage"
WORK_DIR="${OVFTOOL_WORK_DIR:-/tmp/ovftool-download}"
INSTALL_DIR="${OVFTOOL_INSTALL_DIR:-/opt}"

mkdir -p "${WORK_DIR}" "${INSTALL_DIR}"
HTML_FILE="${WORK_DIR}/latest.html"
RESPONSE_FILE="${WORK_DIR}/download-response.json"
HEADERS_FILE="${WORK_DIR}/download-headers.txt"

log() {
  printf '[ovftool] %s\n' "$*"
}

fail() {
  printf '[ovftool][error] %s\n' "$*" >&2
  exit 1
}

extract_json_field() {
  local field_path="$1"
  local file_path="$2"

  if command -v jq >/dev/null 2>&1; then
    jq -r "${field_path} // empty" "${file_path}"
  elif command -v python3 >/dev/null 2>&1; then
    python3 - <<'PY' "${field_path}" "${file_path}"
import json
import sys

path = sys.argv[1].strip('.')
file_path = sys.argv[2]

with open(file_path, 'r', encoding='utf-8') as f:
    data = json.load(f)

value = data
for part in path.split('.'):
    if not part:
        continue
    if isinstance(value, dict) and part in value:
        value = value[part]
    else:
        value = ''
        break

if value is None:
    value = ''

print(value)
PY
  else
    fail "Neither jq nor python3 is available to parse JSON"
  fi
}

log "Fetching ${PAGE_URL}"
curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors "${PAGE_URL}" -o "${HTML_FILE}"

LINUX_FILE_NAME="$({ grep -oE 'VMware-ovftool-[0-9.\-]+-lin\.x86_64\.zip' "${HTML_FILE}" || true; } | head -n1)"
ARTIFACT_ID="$({ grep -oE 'artifactId:[[:space:]]*[0-9]+' "${HTML_FILE}" || true; } | head -n1 | grep -oE '[0-9]+' || true)"

EXPECTED_MD5="$(awk -v f="${LINUX_FILE_NAME}" 'BEGIN{RS="</tr>"} $0~f {if (match($0, /[0-9a-f]{32}/)) {print substr($0, RSTART, RLENGTH); exit}}' "${HTML_FILE}")"

[[ -n "${LINUX_FILE_NAME}" ]] || fail "Could not determine Linux zip filename from page"
[[ -n "${ARTIFACT_ID}" ]] || fail "Could not determine artifactId from page"
[[ -n "${EXPECTED_MD5}" ]] || fail "Could not determine expected MD5 from page"

PAYLOAD="$(printf '{"fileName":"%s","artifactId":%s,"fileType":"Download"}' "${LINUX_FILE_NAME}" "${ARTIFACT_ID}")"

log "Requesting signed download URL"
curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors \
  -X POST "${API_URL}" \
  -H 'Content-Type: application/json' \
  --data "${PAYLOAD}" \
  -o "${RESPONSE_FILE}"

DOWNLOAD_URL="$(extract_json_field '.data.downloadUrl' "${RESPONSE_FILE}")"
SUCCESS_FLAG="$(extract_json_field '.success' "${RESPONSE_FILE}")"
REDIRECT_URL="$(extract_json_field '.redirectUrl' "${RESPONSE_FILE}")"

if [[ -z "${DOWNLOAD_URL}" ]]; then
  if [[ "${SUCCESS_FLAG}" != "true" && -n "${REDIRECT_URL}" ]]; then
    fail "Download endpoint returned redirect URL (${REDIRECT_URL}), likely gated/authenticated content"
  fi
  fail "No downloadUrl returned from API. Response: $(cat "${RESPONSE_FILE}")"
fi

ZIP_PATH="${WORK_DIR}/${LINUX_FILE_NAME}"
log "Downloading ${LINUX_FILE_NAME}"
curl -fL --retry 5 --retry-delay 2 --retry-all-errors -D "${HEADERS_FILE}" "${DOWNLOAD_URL}" -o "${ZIP_PATH}"

HEADER_CONTENT_TYPE="$(awk 'BEGIN{IGNORECASE=1} /^content-type:/{print tolower($2)}' "${HEADERS_FILE}" | tr -d '\r' | head -n1)"
HEADER_CONTENT_LENGTH="$(awk 'BEGIN{IGNORECASE=1} /^content-length:/{print $2}' "${HEADERS_FILE}" | tr -d '\r' | head -n1)"
ACTUAL_SIZE="$(stat -c '%s' "${ZIP_PATH}")"
ACTUAL_MD5="$(md5sum "${ZIP_PATH}" | awk '{print $1}')"

[[ "${HEADER_CONTENT_TYPE}" == "application/zip" ]] || fail "Unexpected MIME type '${HEADER_CONTENT_TYPE}'"
[[ -n "${HEADER_CONTENT_LENGTH}" ]] || fail "Missing content-length header"
[[ "${ACTUAL_SIZE}" == "${HEADER_CONTENT_LENGTH}" ]] || fail "Size mismatch: file=${ACTUAL_SIZE} header=${HEADER_CONTENT_LENGTH}"
[[ "${ACTUAL_MD5}" == "${EXPECTED_MD5}" ]] || fail "MD5 mismatch: expected=${EXPECTED_MD5} actual=${ACTUAL_MD5}"

unzip -tq "${ZIP_PATH}" >/dev/null

log "Installing OVF Tool into ${INSTALL_DIR}"
unzip -oq "${ZIP_PATH}" -d "${INSTALL_DIR}"

if [[ ! -x "${INSTALL_DIR}/ovftool/ovftool" ]]; then
  OVF_BIN="$(find "${INSTALL_DIR}" -maxdepth 4 -type f -name ovftool | head -n1 || true)"
  [[ -n "${OVF_BIN}" ]] || fail "ovftool binary not found after extraction"
  chmod +x "${OVF_BIN}"
else
  chmod +x "${INSTALL_DIR}/ovftool/ovftool"
fi

log "Installed ${LINUX_FILE_NAME}"
log "artifactId=${ARTIFACT_ID} md5=${ACTUAL_MD5} size=${ACTUAL_SIZE}"
