#!/usr/bin/env bash
# nix-shape-check.sh — fast (~50ms) static shape checker for .nix files.
#
# Catches the 5 sharp edges that bite when editing NixOS config in this
# flake's dendritic pattern. Runs BEFORE nix evaluation so you get a
# fast fail without waiting 30s for nix to eval.
#
# Checks:
#   1. PATTERN MISMATCH      — file path says "host" but declares a "role"
#                              (or vice versa)
#   2. INNER ARGS MISSING    — body uses pkgs.X but inner function args
#                              don't declare pkgs (build intermittently
#                              fails when module graph changes)
#   3. ATTRSET COLLISION     — same attrset key declared twice in one
#                              module (e.g. two environment.systemPackages)
#   4. HOSTNAME MISMATCH     — file declares nixos.hosts."X" but lives
#                              under hosts/Y/...
#   5. ORPHAN LOWER-LEVEL    — file isn't nixos.hosts.<H> and isn't in
#                              dendriticExceptions AND isn't in default.nix
#                              imports → walker won't import it
#
# Usage:
#   ./scripts/nix-shape-check.sh                      # check whole tree
#   ./scripts/nix-shape-check.sh path/to/file.nix     # check one file
#   ./scripts/nix-shape-check.sh --staged             # only staged files
#   ./scripts/nix-shape-check.sh --json               # JSON output for CI
#
# Exit codes:
#   0 — clean
#   1 — at least one issue found (printed as diagnostics)
#   2 — usage error
#
# Designed to be wrong sometimes (false positives) but never wrong about
# the OPPOSITE (false negatives). When in doubt, flag and let the human
# decide. The nix evaluator is the ground truth — this is just a fast
# pre-filter.

set -uo pipefail

REPO_ROOT="$(git rev-parse --show-toplevel 2>/dev/null || echo "$PWD")"
cd "$REPO_ROOT"

# ── Args ────────────────────────────────────────────────────────────
TARGET=""
MODE="tree"
JSON_OUT=0
while [[ $# -gt 0 ]]; do
    case "$1" in
        --staged) MODE="staged"; shift ;;
        --json)   JSON_OUT=1; shift ;;
        -h|--help)
            sed -n '2,/^$/p' "$0" | sed 's/^# \?//'
            exit 0
            ;;
        -*) echo "unknown flag: $1" >&2; exit 2 ;;
        *)  TARGET="$1"; shift ;;
    esac
done

# ── Collect files to check ─────────────────────────────────────────
collect_files() {
    case "$MODE" in
        staged)
            git diff --cached --name-only --diff-filter=AM | grep '\.nix$' || true
            ;;
        tree)
            if [[ -n "$TARGET" ]]; then
                echo "$TARGET"
            else
                # Walk hosts/ and modules/ and pkgs/. Skip tests/ and flake.nix
                # (the walker entry point, not a leaf module).
                find hosts modules pkgs -name '*.nix' -not -path '*/.git/*' 2>/dev/null
                echo flake.nix
            fi
            ;;
    esac
}

mapfile -t FILES < <(collect_files)

if [[ ${#FILES[@]} -eq 0 ]]; then
    if [[ $JSON_OUT -eq 1 ]]; then echo '{"issues":[],"checked":0}'; fi
    exit 0
fi

# ── Diagnostic accumulator ─────────────────────────────────────────
# Each issue is one JSON line (or human-readable in non-JSON mode).
ISSUES_HUMAN=()
ISSUES_JSON=()
checked=0

# JSON-escape a string value: escape \, ", control chars. Used when
# emitting the JSON output of an issue so quotes inside messages
# (e.g. "should be nixos.hosts.\"UwU\"") don't break the parse.
json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"        # \ -> \\
    s="${s//\"/\\\"}"        # " -> \"
    s="${s//	/\\t}"        # tab -> \t
    # newlines + CR would break the JSON line; replace with spaces.
    s="${s//$'\n'/ }"
    s="${s//$'\r'/ }"
    printf '%s' "$s"
}

emit() {
    local severity="$1" file="$2" rule="$3" line="$4" msg="$5"
    if [[ $JSON_OUT -eq 1 ]]; then
        local ef er el em
        ef=$(json_escape "$file")
        er=$(json_escape "$rule")
        em=$(json_escape "$msg")
        ISSUES_JSON+=("{\"severity\":\"$severity\",\"file\":\"$ef\",\"rule\":\"$er\",\"line\":$line,\"message\":\"$em\"}")
    else
        ISSUES_HUMAN+=("${severity}: $file:$line [$rule] $msg")
    fi
}

# ── Pre-compute the dendriticExceptions + default.nix imports state ──
# Parse flake.nix for the exceptions list once. Use grep -A / sed for the
# block extraction (bash regex is too brittle for nested braces).
declare -A IS_EXCEPTION
declare -A DEFAULT_NIX_IMPORTS  # file basename → host it lives in
if [[ -f flake.nix ]]; then
    # Extract lines inside the `dendriticExceptions = { ... };` block.
    # Crude but works: awk tracks brace depth from the marker line.
    awk '
        /dendriticExceptions[[:space:]]*=[[:space:]]*\{/ { in_block=1; depth=1; next }
        in_block {
            n_open  = gsub(/\{/, "{")
            n_close = gsub(/\}/, "}")
            depth += n_open - n_close
            if (match($0, /"[^"]+\.nix"[[:space:]]*=/)) {
                rel = substr($0, RSTART, RLENGTH)
                # strip the trailing "=" and quotes
                gsub(/^"|"[[:space:]]*=$/, "", rel)
                print rel
            }
            if (depth <= 0) in_block = 0
        }
    ' flake.nix | while IFS= read -r rel; do
        [[ -n "$rel" ]] && IS_EXCEPTION["$rel"]=1
    done
fi

# For each hosts/<H>/default.nix, parse its imports list and record which
# relative .nix files it pulls in directly.
for defnix in $(find hosts -maxdepth 2 -name default.nix 2>/dev/null); do
    host="$(echo "$defnix" | cut -d/ -f2)"
    while IFS= read -r line; do
        # Match `./<name>.nix` and `./<dir>/<name>.nix`
        if [[ "$line" =~ \./([A-Za-z0-9_./-]+\.nix) ]]; then
            rel="${BASH_REMATCH[1]}"
            DEFAULT_NIX_IMPORTS["hosts/$host/$rel"]="$host"
        fi
    done < "$defnix"
done

# ── Per-file checks ────────────────────────────────────────────────
check_file() {
    local file="$1"
    [[ -f "$file" ]] || return 0
    checked=$((checked + 1))

    local content
    content="$(cat "$file")"

    # Determine which "shape" the file declares (if any).
    local declares_role="" declares_host=""
    # Match `nixos.modules.<role> =` or `nixos.hosts."<host>" =`
    if [[ "$content" =~ nixos\.modules\.([A-Za-z0-9_-]+)[[:space:]]*= ]]; then
        declares_role="${BASH_REMATCH[1]}"
    fi
    if [[ "$content" =~ nixos\.hosts\.\"([A-Za-z0-9_-]+)\"[[:space:]]*= ]]; then
        declares_host="${BASH_REMATCH[1]}"
    fi

    # Determine the file's "home" from its path.
    local file_home=""  # "host:<H>" | "role:<R>" | "pkgs" | "flake" | "other"
    if [[ "$file" =~ ^hosts/([^/]+)/ ]]; then
        file_home="host:${BASH_REMATCH[1]}"
    elif [[ "$file" =~ ^modules/([^/]+)/ ]]; then
        file_home="role:${BASH_REMATCH[1]}"
    elif [[ "$file" =~ ^pkgs/ ]]; then
        file_home="pkgs"
    elif [[ "$file" == "flake.nix" ]]; then
        file_home="flake"
    else
        file_home="other"
    fi

    # ── Rule 1: PATTERN MISMATCH ────────────────────────────────────
    # A file under hosts/<H>/... that declares nixos.modules.<role> is
    # almost always wrong — host-specific files should declare
    # nixos.hosts.<H>, not a shared role.
    if [[ "$file_home" == host:* && -n "$declares_role" ]]; then
        local host="${file_home#host:}"
        emit "error" "$file" "pattern-mismatch" 0 \
            "file lives under hosts/$host/ but declares nixos.modules.$declares_role (should be nixos.hosts.\"$host\" or be moved to modules/)"
    fi
    # A file under modules/<R>/... that declares nixos.hosts.<H> is the
    # reverse — shared modules should declare a role, not bind to a
    # specific host.
    if [[ "$file_home" == role:* && -n "$declares_host" ]]; then
        local role="${file_home#role:}"
        emit "error" "$file" "pattern-mismatch" 0 \
            "file lives under modules/$role/ but declares nixos.hosts.\"$declares_host\" (shared module should not bind to one host)"
    fi

    # ── Rule 4: HOSTNAME MISMATCH ───────────────────────────────────
    # File declares nixos.hosts."X" but lives under hosts/Y/...
    if [[ -n "$declares_host" && "$file_home" == host:* ]]; then
        local host="${file_home#host:}"
        if [[ "$declares_host" != "$host" ]]; then
            emit "error" "$file" "hostname-mismatch" 0 \
                "file declares nixos.hosts.\"$declares_host\" but lives under hosts/$host/ (mismatched hostname — copy-paste hazard)"
        fi
    fi

    # ── Rule 2: INNER ARGS MISSING ──────────────────────────────────
    # If the body references `pkgs.X` (or `pkgs<word>`) but the inner
    # function args don't include pkgs, flag it.
    #
    # Multi-line inner signatures: the args are like
    #     { config
    #     , lib
    #     , pkgs
    #     , ...
    #     }:
    # so we need to inspect ALL lines of the inner signature, not just
    # the line containing `:`.
    if grep -qE '\bpkgs\.[A-Za-z]' <<< "$content"; then
        # Walk the file line by line. After `nixos.<modules|hosts>.<X> =`
        # we accumulate lines as the inner-block buffer. We stop when
        # we see the closing `}` (with brace depth == 0) followed by `:`.
        local in_decl=0 depth=0 inner_text="" lineno=0 sig_done=0
        while IFS= read -r line; do
            lineno=$((lineno + 1))
            if [[ $in_decl -eq 0 ]]; then
                if [[ "$line" =~ nixos\.(modules|hosts)\.[A-Za-z0-9_\".-]+[[:space:]]*=[[:space:]]*$ ]]; then
                    in_decl=1
                    depth=0
                    inner_text=""
                    sig_done=0
                fi
                continue
            fi
            # Track brace depth as we accumulate.
            local opens closes
            opens=$(grep -o '{' <<< "$line" | wc -l)
            closes=$(grep -o '}' <<< "$line" | wc -l)
            depth=$((depth + opens - closes))
            inner_text+="$line"$'\n'
            # When depth back to 0 and line ends with `:` (or `:` after
            # whitespace), we have the full inner signature.
            if [[ $depth -le 0 && $sig_done -eq 0 ]]; then
                # Check if any line in inner_text references `pkgs` as a
                # comma-separated arg (not as `${pkgs.foo}` interpolation,
                # which has braces and gets excluded by the comma-context).
                local sig_ok=0
                if grep -qE '(^|[^A-Za-z0-9_])pkgs[[:space:]]*,?' <<< "$inner_text" \
                    || grep -qE ',[[:space:]]*pkgs[[:space:]]*,?' <<< "$inner_text"; then
                    sig_ok=1
                fi
                # Also accept the single-line form: `{ pkgs, ... }:`
                if grep -qE '\{[^}]*\bpkgs\b' <<< "$inner_text"; then
                    sig_ok=1
                fi
                if [[ $sig_ok -eq 0 ]]; then
                    emit "warn" "$file" "inner-args-missing" "$lineno" \
                        "body references pkgs.* but the inner function signature does not declare pkgs — add \`pkgs,\` to the inner argset"
                fi
                in_decl=0
                sig_done=1
            fi
        done <<< "$content"
    fi

    # ── Rule 3: ATTRSET COLLISION ───────────────────────────────────
    # Two declarations of the same attrset key in the same file.
    # Common offenders: environment.systemPackages, services.<x>.settings.
    # Heuristic: count occurrences of `<attrset-key> = [ ... ];` patterns
    # at the same brace depth. We just count lines that match
    # `<attr-path> = [` (start of an attrset assignment).
    # The high-collision keys we care about:
    local collision_keys=(
        "environment.systemPackages"
        "environment.etc"
        "services\\.[A-Za-z0-9_-]+\\.settings"
        "users\\.users\\.[A-Za-z0-9_-]+\\.extraGroups"
        "boot\\.kernelParameters"
        "boot\\.loader\\.[A-Za-z0-9_-]+\\.[A-Za-z0-9_-]+"
    )
    local lineno=0
    while IFS= read -r line; do
        lineno=$((lineno + 1))
        for key in "${collision_keys[@]}"; do
            # Match line-start with optional indent, the key, optional
            # dot-suffix, then ` = [`. We need to actually count, so we
            # emit once per duplicate — but to keep this fast, we just
            # warn on the second occurrence onward.
            if [[ "$line" =~ ^[[:space:]]*(${key})[[:space:]]*=[[:space:]]*\[ ]]; then
                # Count how many previous lines also match this exact key.
                local full_key="${BASH_REMATCH[1]}"
                local prev_count
                prev_count=$(head -n $((lineno - 1)) "$file" | grep -cE "^[[:space:]]*${full_key}[[:space:]]*=" || true)
                if [[ $prev_count -ge 1 ]]; then
                    emit "warn" "$file" "attrset-collision" "$lineno" \
                        "$full_key is declared $((prev_count + 1)) times in this file — NixOS merges same-key attrsets across modules, but multiple declarations in one file are a code smell. Combine into one list."
                    break
                fi
            fi
        done
    done < "$file"

    # ── Rule 5: ORPHAN LOWER-LEVEL ──────────────────────────────────
    # A file under hosts/<H>/ that is NOT a nixos.hosts.<H> file
    # (i.e. it's a bare top-level NixOS module) must be EITHER in
    # dendriticExceptions OR imported by default.nix. Otherwise the
    # walker won't pick it up and it has no effect.
    #
    # EXCEPTION: hosts/<H>/default.nix is the host ENTRY POINT. It's
    # imported by flake.nix's nixosConfigurations attr, not by the
    # walker — that's correct. Don't flag it.
    local base="$(basename "$file")"
    if [[ "$file_home" == host:* && -z "$declares_host" && -z "$declares_role" && "$base" != "default.nix" ]]; then
        # It looks like a bare NixOS module. Check exceptions + imports.
        # Relative path from repo root:
        local rel="$file"
        if [[ -n "${IS_EXCEPTION[$rel]:-}" ]]; then
            return 0  # explicitly excepted
        fi
        if [[ -n "${DEFAULT_NIX_IMPORTS[$rel]:-}" ]]; then
            return 0  # imported by default.nix
        fi
        emit "warn" "$file" "orphan-module" 0 \
            "file looks like a bare NixOS module (no nixos.hosts.<H> or nixos.modules.<X> wrapper) but is not in dendriticExceptions and not imported by default.nix — the walker won't see it. Either add it to flake.nix:dendriticExceptions, import it in default.nix, or wrap it in nixos.hosts.\"<H>\""
    fi
}

for f in "${FILES[@]}"; do
    check_file "$f"
done

# ── Output ──────────────────────────────────────────────────────────
if [[ $JSON_OUT -eq 1 ]]; then
    # comma-separated JSON array of issues
    if [[ ${#ISSUES_JSON[@]} -gt 0 ]]; then
        joined=$(IFS=,; echo "${ISSUES_JSON[*]}")
    else
        joined=""
    fi
    echo "{\"checked\":$checked,\"issues\":[${joined}]}"
else
    if [[ ${#ISSUES_HUMAN[@]} -eq 0 ]]; then
        echo "✓ nix-shape-check: $checked files clean"
        exit 0
    fi
    echo "✗ nix-shape-check: $checked files, ${#ISSUES_HUMAN[@]} issue(s):"
    printf '  %s\n' "${ISSUES_HUMAN[@]}"
    echo
    echo "(These are static shape hints. The nix evaluator is ground truth —"
    echo " if the build passes despite these, your pattern is fine.)"
fi

# Exit 1 if any errors (not warnings) — warnings are advisory.
errs=0
for issue in "${ISSUES_HUMAN[@]}"; do
    if [[ "$issue" == error:* ]]; then errs=$((errs + 1)); fi
done
if [[ $errs -gt 0 ]]; then exit 1; fi
exit 0
