#!/usr/bin/env bash
set -euo pipefail

cd -- "$(dirname -- "$0")"
version=$(jq -er '.version' manifest.json)
[[ $(jq -er '.id' manifest.json) == xyz.degendev.rog-strix-control ]]

release_files=(
  .github/workflows/validate.yml
  70-rog-strix-energy.rules BarWidget.qml CHANGELOG.md LICENSE Panel.qml README.md RELEASE_CHECKLIST.md
  SECURITY.md Service.qml manifest.json package.sh preview.png rog-strix-control
  test.sh verify-package.sh
)
for file in "${release_files[@]}"; do
  [[ -f $file && ! -L $file ]] || { printf 'missing or unsafe release file: %s\n' "$file" >&2; exit 1; }
done

./test.sh
out_dir=${1:-dist}
mkdir -p "$out_dir"
archive="$out_dir/rog-strix-control-$version.tar.gz"
temporary="$archive.tmp.$$"
trap 'rm -f -- "$temporary"' EXIT
epoch=${SOURCE_DATE_EPOCH:-$(git log -1 --format=%ct 2>/dev/null || printf '0')}
[[ $epoch =~ ^[0-9]+$ ]]
LC_ALL=C tar --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner --format=ustar -cf - "${release_files[@]}" | gzip -n >"$temporary"
mv -- "$temporary" "$archive"
trap - EXIT
./verify-package.sh "$archive"
printf '%s\n' "$archive"
