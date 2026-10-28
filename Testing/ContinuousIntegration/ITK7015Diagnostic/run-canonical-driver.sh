#!/usr/bin/env bash
set -euo pipefail

# Retain the already reviewed compiler/runtime/fixture guards and simple witness.
bash Testing/ContinuousIntegration/ITK7015Diagnostic/run.sh
root="$PWD"
source_root="$root/exact-source"
harness="$root/Testing/ContinuousIntegration/ITK7015Diagnostic/CanonicalDriver"
out="$root/diagnostic-out/$ITK7015_CASE/canonical-driver"
build="$root/itk7015-canonical-libraries"
driver_build="$root/itk7015-canonical-driver"
cmake="$root/itk7015-tools/cmake-4.0.1-macos-universal/CMake.app/Contents/bin/cmake"
compiler="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang++"
c_compiler="$DEVELOPER_DIR/Toolchains/XcodeDefault.xctoolchain/usr/bin/clang"
sdk_path="$(xcrun --sdk macosx --show-sdk-path)"
mkdir -p "$out"
exec > >(tee "$out/driver.log") 2>&1
test -z "$(git -C "$source_root" status --porcelain)"

# An independent build preserves the earlier minimal-module artifact unchanged.
"$cmake" -S "$source_root" -B "$build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=17 -DCMAKE_CXX_STANDARD_REQUIRED=ON \
  -DCMAKE_CXX_EXTENSIONS=OFF -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_OSX_SYSROOT="$sdk_path" \
  -DCMAKE_C_COMPILER="$c_compiler" -DCMAKE_CXX_COMPILER="$compiler" \
  -DITK_BUILD_DEFAULT_MODULES=OFF -DModule_ITKVideoCore=ON -DModule_ITKTestKernel=ON \
  -DModule_ITKVideoIO=ON -DBUILD_SHARED_LIBS=OFF -DITK_USE_CCACHE=OFF \
  -DBUILD_TESTING=OFF -DBUILD_EXAMPLES=OFF -DITK_BUILD_DOCUMENTATION=OFF \
  -DITK_WRAP_PYTHON=OFF -DCMAKE_DISABLE_FIND_PACKAGE_Python3=ON \
  2>&1 | tee "$out/configure.log"
ninja -C "$build" -t commands ITKVideoCore ITKTestKernel ITKVideoIO > "$out/library-command-graph.txt"
if grep -Ein 'python|[.]py|(^|/)cargo([[:space:]]|$)' "$out/library-command-graph.txt"; then
  exit 3
fi
ninja -C "$build" -j3 ITKVideoCore ITKTestKernel ITKVideoIO 2>&1 | tee "$out/library-build.log"
cp "$build/CMakeCache.txt" "$out/library-CMakeCache.txt"

"$cmake" -S "$harness" -B "$driver_build" -G Ninja \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_OSX_ARCHITECTURES=x86_64 \
  -DCMAKE_OSX_SYSROOT="$sdk_path" -DCMAKE_CXX_COMPILER="$compiler" -DITK_DIR="$build" \
  -DITK7015_SOURCE_ROOT="$source_root" \
  -DITK7015_INPUT="$root/diagnostic-out/$ITK7015_CASE/HeadMRVolumeCompressed.mha" \
  -DITK7015_BASELINE="$root/diagnostic-out/$ITK7015_CASE/expected-frame.mha" \
  2>&1 | tee "$out/native-configure.log"
ninja -C "$driver_build" -t commands ITKVideoCoreTestDriver > "$out/native-command-graph.txt"
if grep -Ein 'python|[.]py|(^|/)cargo([[:space:]]|$)' "$out/native-command-graph.txt"; then
  exit 3
fi
ninja -C "$driver_build" -j2 ITKVideoCoreTestDriver 2>&1 | tee "$out/native-build.log"
cp "$driver_build/ITKVideoCoreTestDriver" "$driver_build/ITKVideoCoreTestDriver.cxx" \
  "$driver_build/CMakeCache.txt" "$driver_build/CTestTestfile.cmake" "$out/"
mkdir -p "$out/native-support"
cp "$build/lib/"*.a "$out/native-support/"
shasum -a 256 "$out/ITKVideoCoreTestDriver" "$out/native-support/"*.a > "$out/native-identities.sha256"
set +e
arch -x86_64 "$root/itk7015-tools/cmake-4.0.1-macos-universal/CMake.app/Contents/bin/ctest" \
  --test-dir "$driver_build" --verbose --output-on-failure --no-tests=error -R '^ImageToVideoFilterTest$' \
  2>&1 | tee "$out/ctest.log"
test_status=${PIPESTATUS[0]}
set -e
printf '%s\n' "$test_status" > "$out/ctest.exit"
cp -R "$driver_build/Testing" "$out/"
if test -f "$driver_build/HeadMRVolume_Frame0.mha"; then
  cp "$driver_build/HeadMRVolume_Frame0.mha" "$out/"
fi
test -z "$(git -C "$source_root" status --porcelain)"
exit "$test_status"
