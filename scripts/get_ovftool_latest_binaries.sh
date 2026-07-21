#!/usr/bin/env bash
set -euo pipefail

DEST_DIR="${1:-binaries}"
PAGE_URL="${OVFTOOL_PAGE_URL:-https://developer.broadcom.com/tools/open-virtualization-format-ovf-tool/latest}"
API_URL="${PAGE_URL}?p_p_id=SDK_AND_TOOL_DETAILS_INSTANCE_iwlk&p_p_lifecycle=2&p_p_state=normal&p_p_mode=view&p_p_resource_id=documentDownloadArtifact&p_p_cacheability=cacheLevelPage"

mkdir -p "${DEST_DIR}"
TMP_DIR="$(mktemp -d)"
trap 'rm -rf "${TMP_DIR}"' EXIT

HTML_FILE="${TMP_DIR}/latest.html"
RESP_FILE="${TMP_DIR}/response.json"

log() {
  printf '[ovftool-binaries] %s\n' "$*"
}

fail() {
  printf '[ovftool-binaries][error] %s\n' "$*" >&2
  exit 1
}

json_field() {
  local field_path="$1"
  local file_path="$2"

  if command -v jq >/dev/null 2>&1; then
    jq -r "${field_path} // empty" "${file_path}"
  else
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
  fi
}

log "Fetching latest OVF Tool page"
curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors "${PAGE_URL}" -o "${HTML_FILE}"

ARTIFACT_ID="$({ grep -oE 'artifactId:[[:space:]]*[0-9]+' "${HTML_FILE}" || true; } | head -n1 | grep -oE '[0-9]+' || true)"
[[ -n "${ARTIFACT_ID}" ]] || fail "Could not determine artifactId from page"

LINUX_FILE="$({ grep -oE 'VMware-ovftool-[0-9.\-]+-lin\.x86_64\.zip' "${HTML_FILE}" || true; } | head -n1)"
[[ -n "${LINUX_FILE}" ]] || fail "Could not find Linux OVF Tool artifact"

mapfile -t WINDOWS_FILES < <({ grep -oE 'VMware-ovftool-[0-9.\-]+-win\.x86_64\.(zip|msi)' "${HTML_FILE}" || true; } | sort -u)
[[ "${#WINDOWS_FILES[@]}" -gt 0 ]] || fail "Could not find Windows OVF Tool artifacts"

FILES=("${LINUX_FILE}" "${WINDOWS_FILES[@]}")

for file_name in "${FILES[@]}"; do
  log "Requesting signed URL for ${file_name}"
  payload="$(printf '{"fileName":"%s","artifactId":%s,"fileType":"Download"}' "${file_name}" "${ARTIFACT_ID}")"

  curl -fsSL --retry 5 --retry-delay 2 --retry-all-errors \
    -X POST "${API_URL}" \
    -H 'Content-Type: application/json' \
    --data "${payload}" \
    -o "${RESP_FILE}"

  download_url="$(json_field '.data.downloadUrl' "${RESP_FILE}")"
  success_flag="$(json_field '.success' "${RESP_FILE}")"

  [[ "${success_flag}" == "true" ]] || fail "API returned non-success for ${file_name}: $(cat "${RESP_FILE}")"
  [[ -n "${download_url}" ]] || fail "Missing downloadUrl for ${file_name}: $(cat "${RESP_FILE}")"

  log "Downloading ${file_name}"
  curl -fL --retry 5 --retry-delay 2 --retry-all-errors "${download_url}" -o "${DEST_DIR}/${file_name}"
done

log "Downloaded artifacts to ${DEST_DIR}"
ls -Alh "${DEST_DIR}"
