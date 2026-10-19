#!/bin/bash
set -eu
cd "$(dirname "$0")"
SDK="$(xcrun --sdk macosx --show-sdk-path)"
KERNEL="$SDK/System/Library/Frameworks/Kernel.framework/Headers"
mkdir -p build/G870Bridge.kext/Contents/MacOS
xcrun clang++ -arch x86_64 -std=c++14 -mkernel -fno-builtin -fno-exceptions -fno-rtti -fapple-kext -DKERNEL -DKERNEL_PRIVATE -nostdinc -isystem "$KERNEL" -isystem "$KERNEL/IOKit" -O2 -Wall -Wextra -Wno-unused-parameter -mmacosx-version-min=15.5 -c src/G870Bridge.cpp -o build/G870Bridge.o
xcrun clang++ -arch x86_64 -mmacosx-version-min=15.5 -nostdlib -Xlinker -kext -Xlinker -undefined -Xlinker dynamic_lookup build/G870Bridge.o "$SDK/usr/lib/libkmod.a" -o build/G870Bridge.kext/Contents/MacOS/G870Bridge
cp src/Info.plist build/G870Bridge.kext/Contents/Info.plist
xcrun clang -arch x86_64 -O2 -Wall -Wextra -framework IOKit -framework CoreFoundation src/g870ctl.c -o build/g870ctl
