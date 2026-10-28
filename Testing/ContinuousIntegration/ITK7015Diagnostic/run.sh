#!/usr/bin/env bash
set -euo pipefail

case "${ITK7015_CASE}:${ITK7015_SOURCE_REF}" in
  base:3f19582d1686ea86c1522f6e1610b585bea09361) ;;
  candidate:17185fa89dc815c3a5a48e0b2694305e49e0758b) ;;
  *) exit 2 ;;
esac
root="$PWD"
source_root="$root/exact-source"
harness="$root/Testing/ContinuousIntegration/ITK7015Diagnostic"
out="$root/diagnostic-out/$ITK7015_CASE"
tools="$root/itk7015-tools"
build="$root/itk7015-libraries"
native_build="$root/itk7015-native-case"
mkdir -p "$out" "$tools"
exec > >(tee "$out/driver.log") 2>&1

test "$(git -C "$source_root" rev-parse HEAD)" = "$ITK7015_SOURCE_REF"
test -z "$(git -C "$source_root" status --porcelain)"
git -C "$source_root" rev-parse HEAD 'HEAD^{tree}' > "$out/source-identity.txt"
sw_vers > "$out/runtime.txt"
uname -a >> "$out/runtime.txt"
test "$(uname -m)" = arm64
xcodebuild -version > "$out/xcode.txt"
test -x "$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
compiler="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
c_compiler="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
"$compiler" --version | tee "$out/compiler.txt"
grep -F 'Apple clang version 17.0.0 (clang-1700.0.13.5)' "$out/compiler.txt"
test "$(sw_vers -productVersion | cut -d. -f1)" = 15
arch -x86_64 /usr/bin/uname -m | tee "$out/execution-architecture.txt"
grep -x x86_64 "$out/execution-architecture.txt"
arch -x86_64 /usr/sbin/sysctl -n sysctl.proc_translated | tee "$out/rosetta-translated.txt"
grep -x 1 "$out/rosetta-translated.txt"
cat > "$out/scope.txt" <<'EOF'
The original failing CI used macos-15, Apple clang 17.0.0 (clang-1700.0.13.5), and Xcode_16.4.
This diagnostic requires that compiler build, an arm64 host, and translated x86_64 execution.
The runner image, macOS patch build, and SDK are recorded but not pinned to the historical image.
This prepared variant would replay the original C++17 default only after a narrow explicit ADR009 exception. It is not the canonical C++23 verification.
It builds only native VideoCore/IOMeta dependencies and the unchanged original test outside the full CTest driver.
An isolated pass does not establish that the original full CI failure was a flake or has been repaired.
EOF
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
test -d "$sdk_path"
printf '%s\n' "$sdk_path" > "$out/sdk.txt"
xcrun --sdk macosx --show-sdk-version >> "$out/sdk.txt"

curl --fail --location --retry 2 --max-time 180 \
  https://github.com/Kitware/CMake/releases/download/v4.0.1/cmake-4.0.1-macos-universal.tar.gz \
  -o "$tools/cmake.tar.gz"
printf '%s  %s\n' 5bb98e3096f0efe159bd862c2f293a43b5ebee6c0646bbc5fe7244cf2fc1c261 \
  "$tools/cmake.tar.gz" | shasum -a 256 -c -
tar -xzf "$tools/cmake.tar.gz" -C "$tools"
cmake="$tools/cmake-4.0.1-macos-universal/CMake.app/Contents/bin/cmake"
"$cmake" --version > "$out/cmake.txt"
command -v ninja
ninja --version > "$out/ninja.txt"

curl --fail --location --retry 2 --max-time 90 \
  https://insightsoftwareconsortium.github.io/ITKTestingData/CID/bafkreid54i4w3c7hw3pgglrfexxpv5iftnuye3nca2ctqyml3rvzk6p6ny \
  -o "$out/HeadMRVolumeCompressed.mha"
curl --fail --location --retry 2 --max-time 90 \
  https://insightsoftwareconsortium.github.io/ITKTestingData/CID/bafkreib4utjmhhmwvmtmz64vmy5pbmmn3phbj22yje32knkrq5x7435bju \
  -o "$out/expected-frame.mha"
printf '%s  %s\n' 7de2396d8be7b6de632e2525eefaf5059b69826da2068538618bdc6b9579fe6e \
  "$out/HeadMRVolumeCompressed.mha" | shasum -a 256 -c -
printf '%s  %s\n' 3ca4d2c39d96ab26ccfb95663af0b18ddbce14eb584937a53551876ffe6fa14d \
  "$out/expected-frame.mha" | shasum -a 256 -c -
original="$source_root/Modules/Video/Core/test/itkImageToVideoFilterTest.cxx"
printf '%s  %s\n' 8170d562a382f2feffaaf5ecb59c910bb578a3eb083f70f6c165979c72ea0465 \
  "$original" | shasum -a 256 -c -
cp "$original" "$out/original-test.cxx"
cp "$harness/main.cxx" "$harness/CMakeLists.txt" "$out/"
ruby "$harness/prepare-diagnostic.rb" "$original" "$out/diagnostic-test.cxx"

"$cmake" -S "$source_root" -B "$build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=17 -DCMAKE_CXX_STANDARD_REQUIRED=ON \
  -DCMAKE_CXX_EXTENSIONS=OFF -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_OSX_SYSROOT="$sdk_path" \
  -DCMAKE_C_COMPILER="$c_compiler" -DCMAKE_CXX_COMPILER="$compiler" \
  -DITK_BUILD_DEFAULT_MODULES=OFF -DModule_ITKVideoCore=ON -DModule_ITKIOMeta=ON \
  -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF -DITK_BUILD_DOCUMENTATION=OFF \
  -DITK_WRAP_PYTHON=OFF -DCMAKE_DISABLE_FIND_PACKAGE_Python3=ON \
  2>&1 | tee "$out/configure.log"
ninja -C "$build" -t commands ITKVideoCore ITKIOMeta > "$out/library-command-graph.txt"
if grep -Ein 'python|[.]py|(^|/)cargo([[:space:]]|$)' "$out/library-command-graph.txt"; then
  exit 3
fi
ninja -C "$build" -j3 ITKVideoCore ITKIOMeta 2>&1 | tee "$out/library-build.log"
cp "$build/CMakeCache.txt" "$out/library-CMakeCache.txt"

"$cmake" -S "$harness" -B "$native_build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_OSX_SYSROOT="$sdk_path" \
  -DCMAKE_CXX_COMPILER="$compiler" -DITK_DIR="$build" \
  -DITK7015_SOURCE_ROOT="$source_root" -DITK7015_DIAGNOSTIC_SOURCE="$out/diagnostic-test.cxx" \
  2>&1 | tee "$out/native-configure.log"
ninja -C "$native_build" -t commands itk7015-original-case > "$out/native-command-graph.txt"
if grep -Ein 'python|[.]py|(^|/)cargo([[:space:]]|$)' "$out/native-command-graph.txt"; then
  exit 3
fi
ninja -C "$native_build" -j2 itk7015-original-case 2>&1 | tee "$out/native-build.log"
cp "$native_build/itk7015-original-case" "$out/"
cp "$native_build/CMakeCache.txt" "$out/native-CMakeCache.txt"
mkdir -p "$out/native-support"
cp "$build/lib/"*.a "$out/native-support/"
file "$out/itk7015-original-case" > "$out/binary-type.txt"
otool -L "$out/itk7015-original-case" > "$out/linked-libraries.txt"
shasum -a 256 "$out/itk7015-original-case" "$out/native-support/"*.a > "$out/native-identities.sha256"

export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=3
export ITK_GLOBAL_DEFAULT_THREADER=Pool
mkdir -p "$out/original-output" "$out/diagnostic-output"
set +e
arch -x86_64 "$out/itk7015-original-case" "$out/HeadMRVolumeCompressed.mha" \
  "$out/original-output/HeadMRVolume_Frame0.mha" > "$out/original-run.log" 2>&1
original_status=$?
set -e
printf '%s\n' "$original_status" > "$out/original.exit"
cat "$out/original-run.log"

if test "$original_status" -ne 0; then
  ninja -C "$native_build" -j2 itk7015-diagnostic-case 2>&1 | tee "$out/diagnostic-build.log"
  cp "$native_build/itk7015-diagnostic-case" "$out/"
  set +e
  arch -x86_64 "$out/itk7015-diagnostic-case" "$out/HeadMRVolumeCompressed.mha" \
    "$out/diagnostic-output/HeadMRVolume_Frame0.mha" > "$out/diagnostic-run.log" 2>&1
  diagnostic_status=$?
  set -e
  printf '%s\n' "$diagnostic_status" > "$out/diagnostic.exit"
  cat "$out/diagnostic-run.log"
  exit "$original_status"
fi

printf 'Not executed: original case passed\n' > "$out/diagnostic-not-run.txt"
set +e
cmp "$out/expected-frame.mha" "$out/original-output/HeadMRVolume_Frame0.mha" \
  > "$out/output-byte-comparison.txt" 2>&1
comparison_status=$?
set -e
printf '%s\n' "$comparison_status" > "$out/output-byte-comparison.exit"
test "$comparison_status" -eq 0
test -z "$(git -C "$source_root" status --porcelain)"
printf 'Original case and complete expected output passed\n'
