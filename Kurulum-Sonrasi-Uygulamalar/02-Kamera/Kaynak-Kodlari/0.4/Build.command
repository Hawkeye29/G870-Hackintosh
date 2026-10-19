#!/bin/zsh
set -eu
cd -- "${0:A:h}"
mkdir -p build/generated build/module-cache
sdk=$(/usr/bin/xcrun --sdk driverkit --show-sdk-path)
macsdk=$(/usr/bin/xcrun --sdk macosx --show-sdk-path)
toolchain=$(/usr/bin/xcode-select -p)/Toolchains/XcodeDefault.xctoolchain/usr/bin
"$toolchain/iig" --def src/Driver/G870MatchProbe.iig --header build/generated/G870MatchProbe.h --impl build/generated/G870MatchProbe.iig.cpp --deployment-target 23.0 -- -x c++ -std=c++17 -D__IIG=1 -D__DRIVERKIT__=1 -isysroot "$sdk" -I"$sdk/System/DriverKit/usr/include" -F"$sdk/System/DriverKit/System/Library/Frameworks"
"$toolchain/clang++" -target x86_64-apple-driverkit23.0 -std=c++20 -O2 -isysroot "$sdk" -Ibuild/generated -I"$sdk/System/DriverKit/usr/include" -F"$sdk/System/DriverKit/System/Library/Frameworks" -L"$sdk/System/DriverKit/usr/lib" -framework DriverKit src/Driver/G870MatchProbe.cpp build/generated/G870MatchProbe.iig.cpp -o build/G870MatchProbe
"$toolchain/swiftc" -sdk "$macsdk" -target x86_64-apple-macosx13.0 -module-cache-path build/module-cache src/Host.swift -o build/G870Host -framework AppKit -framework SystemExtensions
"$toolchain/clang++" -isysroot "$macsdk" -target x86_64-apple-macosx13.0 -std=c++17 -O2 -Wall -Wextra -c src/Capture.cpp -o build/Capture.o
"$toolchain/swiftc" -sdk "$macsdk" -target x86_64-apple-macosx13.0 -module-cache-path build/module-cache -import-objc-header src/Capture.h src/CameraProvider.swift src/main.swift build/Capture.o -o build/G870Provider -framework CoreMediaIO -framework IOKit -framework ImageIO -framework CoreGraphics -lc++
/usr/bin/python3 src/package.py

"$toolchain/clang++" -isysroot "$macsdk" -target x86_64-apple-macosx13.0 -std=c++17 -O2 src/Registry.cpp -framework IOKit -framework CoreFoundation -o g870-registry
