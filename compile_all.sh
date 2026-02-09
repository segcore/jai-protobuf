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
)
