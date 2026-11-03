#!/usr/bin/env bash
# Creates foundation stubs from templates. Never overwrites existing files.
# Optionally copies design-system candidates (widgets/themes/…) into lib/design_system/
# via feature_apply --keep-deprecated (originals stay, marked deprecated).
# Usage: foundation_apply.sh [--dry-run] [--router none|go_router|auto_route]
#          [--di get_it|provider] [--migrate-ds none|high|all|id,id,...] [project_root]
# Exit 0 = ok, 1 = ds migrate left unresolved imports, 2 = bad root/args.
set -u

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TPL_DIR="$(cd "$SCRIPT_DIR/../templates/foundation" && pwd)"
FEATURE_APPLY="$(cd "$SCRIPT_DIR/../../clean-arch-new-feature/scripts" && pwd)/feature_apply.sh"
DRY=false
ROUTER=none
DI=""
MIGRATE_DS=none
ROOT="."
while [ $# -gt 0 ]; do
  case "$1" in
    --dry-run) DRY=true; shift ;;
    --router) ROUTER="${2:-none}"; shift 2 ;;
    --di) DI="${2:-}"; shift 2 ;;
    --migrate-ds) MIGRATE_DS="${2:-none}"; shift 2 ;;
    *) ROOT="$1"; shift ;;
  esac
done

cd "$ROOT" 2>/dev/null || { echo "Cannot enter $ROOT" >&2; exit 2; }
[ -d lib ] || { echo "No lib/ directory found" >&2; exit 2; }
ROOT_ABS="$(pwd)"

SCAN="$(bash "$SCRIPT_DIR/foundation_scan.sh" .)"
shared="$(printf '%s' "$SCAN" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("shared_folder","core"))' 2>/dev/null || echo core)"
di_scan="$(printf '%s' "$SCAN" | python3 -c 'import json,sys; print(json.load(sys.stdin).get("di","get_it"))' 2>/dev/null || echo get_it)"
[ -n "$DI" ] || DI="$di_scan"
[ "$DI" = ask ] && DI=get_it

created=0
skipped=0
would=0

write_file() { # dest template [sed_expr]
  local dest="$1" tpl="$2" expr="${3:-}"
  if [ -f "$dest" ]; then
    echo "SKIP exists $dest"
    skipped=$((skipped + 1))
    return
  fi
  if [ "$DRY" = true ]; then
    echo "DRY would create $dest"
    would=$((would + 1))
    return
  fi
  mkdir -p "$(dirname "$dest")"
  if [ -n "$expr" ]; then
    sed "$expr" "$tpl" > "$dest"
  else
    cp "$tpl" "$dest"
  fi
  echo "CREATED $dest"
  created=$((created + 1))
}

# bootstrap
write_file "lib/bootstrap/app_config.dart" "$TPL_DIR/app_config.dart.tpl"
if [ "$DI" = provider ]; then
  write_file "lib/bootstrap/global_providers.dart" "$TPL_DIR/global_providers.dart.tpl"
else
  write_file "lib/bootstrap/injection.dart" "$TPL_DIR/injection.dart.tpl"
fi

# core/error
mkdir -p "lib/$shared/error" 2>/dev/null || true
write_file "lib/$shared/error/result.dart" "$TPL_DIR/result.dart.tpl"

# design_system stub (ensure folder exists before migrate)
if [ ! -d lib/design_system ]; then
  if [ "$DRY" = true ]; then
    echo "DRY would create lib/design_system/README.md"
    would=$((would + 1))
  else
    mkdir -p lib/design_system
    cp "$TPL_DIR/design_system_readme.md.tpl" lib/design_system/README.md
    echo "CREATED lib/design_system/README.md"
    created=$((created + 1))
  fi
else
  echo "SKIP exists lib/design_system/"
  skipped=$((skipped + 1))
fi

# router (opt-in)
case "$ROUTER" in
  go_router|auto_route)
    if [ "$DRY" = true ]; then
      echo "DRY would create lib/router/app_router.dart ($ROUTER)"
      would=$((would + 1))
    else
      mkdir -p lib/router
      if [ -f lib/router/app_router.dart ]; then
        echo "SKIP exists lib/router/app_router.dart"
        skipped=$((skipped + 1))
      else
        sed "s/__ROUTER_PACKAGE__/$ROUTER/" "$TPL_DIR/app_router.dart.tpl" > lib/router/app_router.dart
        echo "CREATED lib/router/app_router.dart"
        created=$((created + 1))
      fi
    fi
    ;;
  none|"")
    echo "SKIP router (--router none)"
    ;;
  *)
    echo "REFUSED unknown --router $ROUTER (use none|go_router|auto_route)" >&2
    exit 2
    ;;
esac

# ---- Design system migrate (copy + deprecate via feature_apply) ----
ds_rc=0
if [ "$MIGRATE_DS" = none ] || [ -z "$MIGRATE_DS" ]; then
  echo "SKIP design_system migrate (--migrate-ds none)"
elif [ ! -f "$FEATURE_APPLY" ]; then
  echo "REFUSED: feature_apply.sh not found at $FEATURE_APPLY" >&2
  exit 2
else
  plan="$(mktemp -t foundation_ds.XXXXXX.tsv 2>/dev/null || mktemp)"
  scan_json="$(mktemp -t foundation_scan.XXXXXX.json 2>/dev/null || mktemp)"
  # shellcheck disable=SC2064
  trap "rm -f '$plan' '$scan_json'" EXIT
  printf '%s' "$SCAN" > "$scan_json"

  python3 - "$MIGRATE_DS" "$plan" "$scan_json" <<'PY'
import json, os, sys

mode, plan_path, scan_path = sys.argv[1], sys.argv[2], sys.argv[3]
with open(scan_path, encoding="utf-8") as f:
    scan = json.load(f)
cands = scan.get("design_system_candidates") or []

if mode == "all":
    want = {c["id"] for c in cands}
elif mode == "high":
    want = {c["id"] for c in cands if c.get("confidence") == "high"}
else:
    want = {x.strip() for x in mode.split(",") if x.strip()}

selected = [c for c in cands if c["id"] in want]
# Pass 1: hosts (not part-of). Pass 2: include part-of siblings whose host is selected.
hosts = set()
lines = []
skipped_exists = 0
part_siblings = 0
all_dart = []
for c in selected:
    frm, to = c["from"].rstrip("/"), c["to"].rstrip("/")
    if not os.path.isdir(frm):
        continue
    for root, _dirs, files in os.walk(frm):
        for name in sorted(files):
            if not name.endswith(".dart"):
                continue
            src = os.path.join(root, name)
            rel = os.path.relpath(src, frm)
            dst = os.path.join(to, rel)
            all_dart.append((src, dst))

def is_part_of(path):
    try:
        with open(path, encoding="utf-8", errors="replace") as f:
            head = f.read(8000)
    except OSError:
        return False
    text = "\n" + head
    return "\npart of " in text or head.lstrip().startswith("part of ")

for src, dst in all_dart:
    if is_part_of(src):
        continue
    if os.path.exists(dst):
        skipped_exists += 1
        continue
    lines.append(f"{src}\t{dst}")
    hosts.add(os.path.dirname(src))

# Include part-of files next to a host we are migrating (feature_apply still refuses them —
# foundation copies these in a follow-up; listed here for dry-run counts / future apply).
# For apply, write a second plan parts.tsv that foundation copies manually.
parts_path = plan_path + ".parts"
part_lines = []
for src, dst in all_dart:
    if not is_part_of(src):
        continue
    if os.path.dirname(src) not in hosts and os.path.dirname(src) not in {
        os.path.dirname(l.split("\t")[0]) for l in lines
    }:
        # host already at destination from a prior run
        host_dir_new = os.path.dirname(dst)
        if not os.path.isdir(host_dir_new):
            continue
    if os.path.exists(dst):
        skipped_exists += 1
        continue
    part_lines.append(f"{src}\t{dst}")
    part_siblings += 1

with open(plan_path, "w", encoding="utf-8") as out:
    out.write("\n".join(lines) + ("\n" if lines else ""))
with open(parts_path, "w", encoding="utf-8") as out:
    out.write("\n".join(part_lines) + ("\n" if part_lines else ""))
sys.stderr.write(
    f"DS_PLAN files={len(lines)} part_siblings={part_siblings} candidates={len(selected)} "
    f"skipped_exists={skipped_exists} "
    f"ids={','.join(c['id'] for c in selected) or '(none)'}\n"
)
PY

  parts_plan="${plan}.parts"
  if [ ! -s "$plan" ] && [ ! -s "$parts_plan" ]; then
    echo "SKIP design_system migrate (empty plan for --migrate-ds $MIGRATE_DS)"
  else
    echo "--- design_system migrate (--migrate-ds $MIGRATE_DS) ---"
    if [ -s "$plan" ]; then
      fa_args=(--keep-deprecated)
      [ "$DRY" = true ] && fa_args=(--dry-run --keep-deprecated)
      bash "$FEATURE_APPLY" "${fa_args[@]}" "$ROOT_ABS" "$plan" || ds_rc=$?
    fi
    # part-of siblings: feature_apply refuses them; copy + deprecate header only
    if [ -s "$parts_plan" ]; then
      n_parts="$(grep -c . "$parts_plan" 2>/dev/null || echo 0)"
      if [ "$DRY" = true ]; then
        echo "DRY would copy $n_parts part-of sibling(s) into design_system/"
        would=$((would + n_parts))
      else
        TODAY="$(date +%Y-%m-%d)"
        PKG="$(sed -n 's/^name:[[:space:]]*//p' pubspec.yaml | head -n1 | tr -d ' \r')"
        while IFS="$(printf '\t')" read -r from to; do
          [ -n "$from" ] || continue
          [ -f "$from" ] || { echo "SKIP missing part $from"; continue; }
          [ -e "$to" ] && { echo "SKIP exists $to"; continue; }
          mkdir -p "$(dirname "$to")"
          cp "$from" "$to"
          if ! head -n 1 "$from" | grep -q "DEPRECATED: migrated"; then
            {
              echo "// DEPRECATED: migrated by /feature --migrate on $TODAY to package:$PKG/${to#lib/}"
              echo "// Do not edit this copy. Delete it once nothing imports it any more."
              cat "$from"
            } > "$from.tmp" && mv "$from.tmp" "$from"
          fi
          echo "COPIED part $from -> $to (original marked deprecated)"
          created=$((created + 1))
        done < "$parts_plan"
      fi
    fi
  fi
fi

if [ "$DRY" = true ]; then
  echo "DRY RUN: would create $would stub file(s), skip $skipped existing. Nothing changed."
else
  echo "DONE: created $created stubs, skipped $skipped (existing left untouched)."
fi

[ "$ds_rc" -eq 2 ] && exit 2
[ "$ds_rc" -eq 1 ] && exit 1
exit 0
