#!/bin/sh
# Fails when the core or a fork names a launcher or asks a host for a
# function. A host sets each value through psdk_core.h. The core must
# never reach up to a name that the host defines.
#
# Two things fail:
#   - The word "empo" anywhere in the repo's own files or in the forks.
#     The ANGLE download from the empo-deps release is a file location,
#     not launcher code, so that one name is allowed.
#   - A weak declaration or a weak import in the forks or in src/. A weak
#     name is how a library calls a function that the host may define.
#     SFML's own weak sfmlMain in SFMain.mm is upstream code and stays.
set -eu

cd "$(dirname "$0")/.."

status=0

if git grep -niIw 'empo' -- . ':!scripts/check-no-host-code.sh' | grep -v 'mateo-m/empo-deps/'
then
    echo "error: the lines above name a launcher" >&2
    status=1
fi

for fork in sources/sfml sources/litergss2
do
    if git -C "$fork" grep -niIw 'empo'
    then
        echo "error: $fork names a launcher" >&2
        status=1
    fi
done

weak='__attribute__ *\(\( *weak|weak_import|#pragma weak'
if git grep -nE "$weak" -- src
then
    echo "error: src/ has a weak name" >&2
    status=1
fi
if git -C sources/sfml grep -nE "$weak" -- ':!src/SFML/Window/iOS/SFMain.mm'
then
    echo "error: sources/sfml has a weak name" >&2
    status=1
fi
if git -C sources/litergss2 grep -nE "$weak"
then
    echo "error: sources/litergss2 has a weak name" >&2
    status=1
fi

exit "$status"
