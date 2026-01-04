set -xe

jai -x64 test.jai -quiet
./test
(
    cd examples
    jai -x64 compiletime.jai -quiet &&
    jai -x64 pregenerate.jai -quiet &&
    ./pregenerate &&
    jai -x64 use_generated.jai -quiet &&
    :
)
