#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "$0")"
archive=${1:?usage: verify-package.sh ARCHIVE}
archive=$(realpath -- "$archive")
[[ -f $archive ]]
expected=$(mktemp); actual=$(mktemp); extract_dir=$(mktemp -d)
trap 'rm -f -- "$expected" "$actual"; rm -rf -- "$extract_dir"' EXIT
printf '%s\n' .github/workflows/validate.yml 70-rog-strix-energy.rules BarWidget.qml CHANGELOG.md LICENSE Panel.qml README.md RELEASE_CHECKLIST.md SECURITY.md Service.qml manifest.json package.sh preview.png rog-strix-control test.sh verify-package.sh | LC_ALL=C sort >"$expected"
tar -tzf "$archive" | sed 's#^\./##; /\/$/d' | LC_ALL=C sort >"$actual"
! grep -Eq '(^/|(^|/)\.\.(/|$))' "$actual"
diff -u "$expected" "$actual"
tar -xzf "$archive" -C "$extract_dir"
[[ -x $extract_dir/rog-strix-control && -x $extract_dir/test.sh && -x $extract_dir/package.sh && -x $extract_dir/verify-package.sh ]]
(cd -- "$extract_dir" && ./test.sh)
printf 'verified package: %s\n' "$archive"
