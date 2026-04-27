#!/usr/bin/env bash
# @version: 1.0.0
# PostToolUse contract sync — detects DTO/API/schema/controller changes, warns
# about missing tests and stale/absent frontend mock/example data. Read-only.
#
# Contract signals: filename suffix (Dto|Request|Response|Command|Query|Schema|
# Model|Entity|Contract|Payload|ViewModel) OR controller route decorators in content.
# Test check: looks for co-named test files (Tests.ext, .test.ext, .spec.ext, _test.ext).
# Mock check: only fires when project already uses mock/fixture files — prevents
# false alerts in projects with no frontend mock layer.

source "${CORTEX_ROOT:-$(pwd)/.claude}/core/shared/bootstrap.sh" || exit 0

input=$(cat)
[[ -z "$input" ]] && exit 0

file=$(echo "$input" | jq -r '.tool_input.file_path // empty' 2>/dev/null)
[[ -z "$file" || ! -f "$file" ]] && exit 0

ext="${file##*.}"
case "$ext" in
  cs|ts|tsx|js|jsx|py|go|java) ;;
  *) exit 0 ;;
esac

fname=$(basename "$file")
fname_noext="${fname%.*}"
fname_lower=$(echo "$fname_noext" | tr '[:upper:]' '[:lower:]')

# ── Contract detection ────────────────────────────────────────────────────────
is_contract=0

# Filename-suffix signal (most reliable)
echo "$fname_lower" | grep -qE \
  '(dto|request|response|command|query|event|schema|contract|payload|model|entity|viewmodel|view_model)' \
  && is_contract=1

# Content signal: controller/router annotations (REST endpoint owners are also contracts)
if [[ $is_contract -eq 0 ]]; then
  grep -qiE \
    '(\[ApiController\]|\[Route\]|@RestController|@Controller|@RequestMapping|@GetMapping|@PostMapping|app\.(get|post|put|patch|delete)\(|router\.(get|post|put|patch|delete)\()' \
    "$file" 2>/dev/null && is_contract=1
fi

[[ $is_contract -eq 0 ]] && exit 0

# Accumulate warnings as raw JSON strings; one jq call at the end
declare -a warn_parts=()

_add_warn() {
  local type="$1" msg="$2" sug="$3"
  local me="${msg//\\/\\\\}"; me="${me//\"/\\\"}"
  local se="${sug//\\/\\\\}"; se="${se//\"/\\\"}"
  warn_parts+=( "{\"type\":\"$type\",\"file\":\"$fname\",\"message\":\"$me\",\"suggestion\":\"$se\"}" )
}

# ── Test file check ───────────────────────────────────────────────────────────
test_found=$(find . -type f \( \
  -iname "${fname_noext}Test.${ext}"  -o -iname "${fname_noext}Tests.${ext}" \
  -o -iname "${fname_noext}.test.${ext}" -o -iname "${fname_noext}.spec.${ext}" \
  -o -iname "${fname_noext}_test.${ext}" -o -iname "test_${fname_lower}.${ext}" \
\) \
  -not -path "*/node_modules/*" -not -path "*/.git/*" \
  -not -path "*/bin/*"          -not -path "*/obj/*"  \
2>/dev/null | head -1)

if [[ -z "$test_found" ]]; then
  _add_warn "missing_test" \
    "No test file found for contract ${fname}" \
    "Create ${fname_noext}Tests.${ext} (or .spec/.test variant) with field validation and serialization round-trip assertions — never leave test stubs empty"
fi

# ── Frontend mock/example data check ─────────────────────────────────────────
# Guard: only warn when the project already uses mock/fixture/example files,
# so we don't produce noise in projects with no frontend mock layer.
project_has_mocks=$(find . -type f \( \
  -iname "*.mock.ts" -o -iname "*.mock.js" \
  -o -iname "*.fixture.ts" -o -iname "*.fixture.js" \
  -o -iname "*.example.ts" -o -iname "*.example.json" \
  -o -iname "*.stub.ts"  -o -iname "*.stub.js" \
\) -not -path "*/node_modules/*" -not -path "*/.git/*" \
2>/dev/null | head -1)

if [[ -n "$project_has_mocks" ]]; then
  # Strip contract suffix to get entity base name for cross-referencing
  base_name=$(echo "$fname_lower" \
    | sed -E 's/(dto|request|response|command|query|event|schema|contract|payload|model|entity|viewmodel|view_model)$//')
  # Fallback: use full name if stripping left nothing or stripped everything
  [[ -z "$base_name" || "$base_name" == "$fname_lower" ]] && base_name="$fname_lower"

  # Collect candidate mock files (up to 40, avoiding heavy dirs)
  mapfile -t mock_candidates < <(
    find . -type f \( \
      -iname "*.mock.*" -o -iname "*.fixture.*" \
      -o -iname "*.example.*" -o -iname "*.stub.*" \
      -o -iname "*.stories.*" \
    \) \
    -not -path "*/node_modules/*" -not -path "*/.git/*" \
    2>/dev/null | head -40
  )

  mock_found=""
  for mf in "${mock_candidates[@]}"; do
    grep -qiE "(${base_name}|${fname_noext})" "$mf" 2>/dev/null \
      && { mock_found="$mf"; break; }
  done

  if [[ -z "$mock_found" ]]; then
    _add_warn "stale_mock" \
      "Frontend mock/example data for ${fname_noext} not found or may be stale" \
      "Add a sample ${fname_noext} mock object in the existing fixtures/mocks directory with realistic values matching all current fields"
  fi
fi

# ── Output ────────────────────────────────────────────────────────────────────
[[ ${#warn_parts[@]} -eq 0 ]] && exit 0

warns_json=$(printf '%s,' "${warn_parts[@]}")
warns_json="[${warns_json%,}]"

jq -n \
  --arg path "$file" \
  --argjson warns "$warns_json" \
  '{"contract_sync": {"file": $path, "warnings": $warns}}'

exit 0
