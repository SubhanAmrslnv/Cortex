#!/usr/bin/env bash
# @version: 1.2.0
# SessionStart project profiler — detects project type, extracts deps, entry points,
# folder structure; writes .cortex/cache/project-profile.json.
# Idempotent via fingerprint. Prunes scan cache entries >7 days on each run.

if [ -z "$CORTEX_ROOT" ]; then
  if [ -d "$(pwd)/.claude" ]; then
    export CORTEX_ROOT="$(pwd)/.claude"
  else
    export CORTEX_ROOT="$(pwd)/.claude"
  fi
fi

command -v jq &>/dev/null || exit 0

CACHE_DIR="$CORTEX_ROOT/cache"
PROFILE="$CACHE_DIR/project-profile.json"
SCAN_CACHE="$CACHE_DIR/scans"

mkdir -p "$CACHE_DIR" "$SCAN_CACHE" 2>/dev/null

# Prune scan cache entries older than 7 days
find "$SCAN_CACHE" -type f -mtime +7 -delete 2>/dev/null || true

# ── Fingerprint: key manifest files mod-times + cwd ──────────────────────
_fingerprint() {
  {
    find . -maxdepth 2 \( \
      -name "*.csproj" -o -name "*.sln" \
      -o -name "package.json" -o -name "go.mod" \
      -o -name "Cargo.toml" -o -name "pom.xml" \
      -o -name "requirements.txt" -o -name "pyproject.toml" \
    \) -not -path "*/obj/*" -not -path "*/node_modules/*" 2>/dev/null \
    | sort \
    | while IFS= read -r f; do
        echo "$f $(stat -c '%Y' "$f" 2>/dev/null || stat -f '%m' "$f" 2>/dev/null || echo 0)"
      done
    echo "$(pwd)"
  } | md5sum 2>/dev/null | cut -d' ' -f1 || echo "nofp"
}

current_fp=$(_fingerprint)

if [[ -f "$PROFILE" ]]; then
  stored_fp=$(jq -r '.fingerprint // empty' "$PROFILE" 2>/dev/null)
  [[ "$stored_fp" == "$current_fp" ]] && exit 0
fi

# ── Project type detection (priority: dotnet > rust > java > node > go > python) ──
_detect_type() {
  local csprojs
  csprojs=$(find . -name "*.csproj" -not -path "*/obj/*" -not -path "*/bin/*" 2>/dev/null | wc -l)
  [[ $csprojs -gt 0 ]]                                                 && { echo "dotnet"; return; }
  [[ -f Cargo.toml ]]                                                  && { echo "rust";   return; }
  [[ -f pom.xml || -f build.gradle || -f build.gradle.kts ]]          && { echo "java";   return; }
  [[ -f package.json ]]                                                && { echo "node";   return; }
  [[ -f go.mod ]]                                                      && { echo "go";     return; }
  [[ -f requirements.txt || -f pyproject.toml || -f setup.py ]]       && { echo "python"; return; }
  echo "unknown"
}

project_type=$(_detect_type)

# ── Dependencies ──────────────────────────────────────────────────────────
deps="[]"
case "$project_type" in
  node)
    [[ -f package.json ]] && \
      deps=$(jq -c '[(.dependencies // {}) + (.devDependencies // {}) | keys[]] | .[:20]' \
               package.json 2>/dev/null || echo "[]") ;;
  python)
    [[ -f requirements.txt ]] && \
      deps=$(grep -v '^#\|^$' requirements.txt 2>/dev/null \
             | cut -d'=' -f1 | cut -d'>' -f1 | cut -d'<' -f1 | cut -d'[' -f1 | head -20 \
             | jq -Rs '[split("\n")[] | select(. != "")]' 2>/dev/null || echo "[]") ;;
  go)
    [[ -f go.mod ]] && \
      deps=$(awk '/^require[[:space:]]*\(/{p=1;next} p&&/^\)/{p=0} p{print $1}' go.mod 2>/dev/null \
             | head -20 | jq -Rs '[split("\n")[] | select(. != "")]' 2>/dev/null || echo "[]") ;;
  rust)
    [[ -f Cargo.toml ]] && \
      deps=$(awk '/^\[dependencies\]/{p=1;next} /^\[/{p=0} p&&/^[a-zA-Z]/{print $1}' Cargo.toml 2>/dev/null \
             | tr -d '= ' | head -20 \
             | jq -Rs '[split("\n")[] | select(. != "")]' 2>/dev/null || echo "[]") ;;
  dotnet)
    deps=$(find . -name "*.csproj" -not -path "*/obj/*" 2>/dev/null | head -5 \
           | xargs grep -h 'PackageReference' 2>/dev/null \
           | grep -oP 'Include="\K[^"]+' | head -20 \
           | jq -Rs '[split("\n")[] | select(. != "")]' 2>/dev/null || echo "[]") ;;
  java)
    [[ -f pom.xml ]] && \
      deps=$(grep '<artifactId>' pom.xml 2>/dev/null \
             | sed 's/.*<artifactId>\(.*\)<\/artifactId>.*/\1/' | head -20 \
             | jq -Rs '[split("\n")[] | select(. != "")]' 2>/dev/null || echo "[]") ;;
esac

# ── Entry points ──────────────────────────────────────────────────────────
_to_arr() { jq -Rs '[split("\n")[] | select(. != "")]'; }
entry_points="[]"
case "$project_type" in
  node)
    main_val=$(jq -r '.main // empty' package.json 2>/dev/null)
    if [[ -n "$main_val" ]]; then
      entry_points=$(jq -n --arg m "$main_val" '[$m]')
    else
      entry_points=$(find . -maxdepth 2 -name "index.*" -not -path "*/node_modules/*" \
                     2>/dev/null | head -5 | _to_arr)
    fi ;;
  python)
    entry_points=$(find . -maxdepth 3 \
                   \( -name "main.py" -o -name "app.py" -o -name "manage.py" -o -name "run.py" \) \
                   2>/dev/null | head -5 | _to_arr) ;;
  go)
    entry_points=$(find . -name "main.go" -not -path "*/vendor/*" 2>/dev/null | head -5 | _to_arr) ;;
  rust)
    entry_points=$(find . -name "main.rs" -not -path "*/target/*" 2>/dev/null | head -5 | _to_arr) ;;
  dotnet)
    entry_points=$(find . -name "Program.cs" -not -path "*/obj/*" -not -path "*/bin/*" \
                   2>/dev/null | head -5 | _to_arr) ;;
  java)
    entry_points=$(find . \( -name "Application.java" -o -name "Main.java" \) \
                   2>/dev/null | head -5 | _to_arr) ;;
esac

# ── Folder structure (depth 2, skip noise) ────────────────────────────────
structure=$(find . -maxdepth 2 -type d \
  -not -path "*/node_modules/*" \
  -not -path "*/.git/*" \
  -not -path "*/obj/*" \
  -not -path "*/bin/*" \
  -not -path "*/target/*" \
  -not -path "*/__pycache__/*" \
  -not -path "*/.venv/*" \
  2>/dev/null | sort | head -40 \
  | jq -Rs '[split("\n")[] | select(. != "")]')

# ── Write profile ─────────────────────────────────────────────────────────
jq -n \
  --arg fp        "$current_fp" \
  --arg type      "$project_type" \
  --arg ts        "$(date -u +%Y-%m-%dT%H:%M:%SZ 2>/dev/null || date +%Y-%m-%dT%H:%M:%SZ)" \
  --argjson deps      "$deps" \
  --argjson entry     "$entry_points" \
  --argjson structure "$structure" \
  '{
    fingerprint:  $fp,
    project_type: $type,
    generated_at: $ts,
    dependencies: $deps,
    entry_points: $entry,
    structure:    $structure
  }' > "$PROFILE"

exit 0
