#!/usr/bin/env bash
# Print what its doing, and stop on any errors
set -xe

(
    cd tests
    jai -x64 test.jai -quiet
    ./test
    jai -x64 well-known.jai -quiet
    ./well-known
)
(
    cd examples
    jai -x64 01-compiletime.jai -quiet
    jai -x64 02a-pregenerate.jai -quiet
    ./02a-pregenerate
    jai -x64 02b-use_generated.jai -quiet
    jai -x64 03-imports.jai -quiet
    jai -x64 04-pool.jai -quiet
    jai -x64 proto-to-jai.jai -quiet
    ./01-compiletime &>/dev/null
    ./02b-use_generated &>/dev/null
    ./03-imports &>/dev/null
    ./04-pool &>/dev/null
    ./proto-to-jai protos/some_things.proto &>/dev/null
)
