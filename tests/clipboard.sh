#!/usr/bin/env bash
set -euo pipefail

binary=${1:?pass the z-layout-switcher binary}
test_dir=$(mktemp -d)
trap 'rm -rf "$test_dir"' EXIT

cat > "$test_dir/wl-paste" <<'EOF'
#!/usr/bin/env bash
if [[ " $* " == *" --list-types "* ]]; then
  printf 'text/plain;charset=utf-8\n'
else
  [[ " $* " == *" --no-newline "* ]] || exit 1
  if [[ " $* " == *" --primary "* ]]; then
    printf ghbdtn
  else
    printf old-clipboard
  fi
fi
EOF
cat > "$test_dir/wl-copy" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$2" >> "$TEST_STATE_DIR/types"
count=$(wc -l < "$TEST_STATE_DIR/types")
cat > "$TEST_STATE_DIR/copy-$count"
EOF
cat > "$test_dir/wtype" <<'EOF'
#!/usr/bin/env bash
printf '%s\n' "$*" > "$TEST_STATE_DIR/keys"
EOF
chmod +x "$test_dir/wl-paste" "$test_dir/wl-copy" "$test_dir/wtype"

PATH="$test_dir:$PATH" TEST_STATE_DIR="$test_dir" "$binary" --layouts us,ru --from 0
test "$(cat "$test_dir/copy-1")" = 'привет'
test "$(cat "$test_dir/copy-2")" = 'old-clipboard'
test "$(cat "$test_dir/keys")" = '-s 200 -M ctrl -k v -m ctrl'

printf '#!/usr/bin/env bash\nexit 1\n' > "$test_dir/wtype"
if PATH="$test_dir:$PATH" TEST_STATE_DIR="$test_dir" "$binary" --layouts us,ru --from 0 2>/dev/null; then
  echo 'expected wtype failure' >&2
  exit 1
fi
test "$(cat "$test_dir/copy-4")" = 'old-clipboard'
