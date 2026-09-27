#!/usr/bin/env bash
# Applies the patches of one Ruby to its source tree, in the order of
# patches/ruby<NN>.patches.lst. Blank lines and # comments are ignored.
#
#   apply-ruby-patches.sh <25|30|32|33> <source-dir>
set -euo pipefail

if [[ $# -ne 2 ]]
then
    echo "usage: $0 <25|30|32|33> <source-dir>" >&2
    exit 2
fi

patches="$(cd "$(dirname "$0")" && pwd)"
list="$patches/ruby$1.patches.lst"
if [[ ! -f "$list" ]]
then
    echo "error: no patch list $list" >&2
    exit 1
fi

cd "$2"
grep -v '^[[:space:]]*\(#.*\)\{0,1\}$' "$list" | while IFS= read -r patch
do
    echo "Applying $patch"
    git apply "$patches/$patch"
done
