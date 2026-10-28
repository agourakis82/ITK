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
build="$root/itk7015-internal-build"
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
This focused diagnostic requires C++23 under ADR009; the original CI did not override ITK's C++17 default.
It configures the original ITK root with default modules and BUILD_TESTING on, then builds only its internal VideoCore test driver and selected original data outputs.
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
cp "$source_root/CMake/ITKModuleTest.cmake" "$out/"
ruby "$harness/prepare-diagnostic.rb" "$original" "$out/diagnostic-test.cxx"

# Supply only a real filesystem prefix as an inert optional-find hint.
# No executable/version/FOUND variable is provided and every Python finder is disabled.
python_root_hint=""
for candidate_root in /opt/homebrew/opt/python@*/Frameworks/Python.framework/Versions/3.* \
  /Library/Developer/CommandLineTools/Library/Frameworks/Python3.framework/Versions/3.* \
  "$DEVELOPER_DIR"/Library/Frameworks/Python3.framework/Versions/3.*; do
  if test -d "$candidate_root/lib" && compgen -G "$candidate_root/bin/python3*" >/dev/null; then
    python_root_hint="$(cd "$candidate_root" && pwd -P)"
    break
  fi
done
test -n "$python_root_hint"
printf '%s\n' "$python_root_hint" > "$out/python-filesystem-hint.txt"
ls -ld "$python_root_hint" "$python_root_hint"/bin/python3* >> "$out/python-filesystem-hint.txt"

store="$root/internal-data-store"
mkdir -p "$store/CID"
cp "$out/HeadMRVolumeCompressed.mha" "$store/CID/bafkreid54i4w3c7hw3pgglrfexxpv5iftnuye3nca2ctqyml3rvzk6p6ny"
cp "$out/expected-frame.mha" "$store/CID/bafkreib4utjmhhmwvmtmz64vmy5pbmmn3phbj22yje32knkrq5x7435bju"

configure_internal() {
  local source_dir="$1" build_dir="$2" receipt="$3"
  mkdir -p "$receipt"
  "$cmake" --trace-expand --trace-format=json-v1 \
    --trace-redirect="$receipt/configure-trace.jsonl" \
    -S "$source_dir" -B "$build_dir" -G Ninja \
    -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_STANDARD=23 -DCMAKE_CXX_STANDARD_REQUIRED=ON \
    -DCMAKE_CXX_EXTENSIONS=OFF -DCMAKE_OSX_ARCHITECTURES=x86_64 \
    -DCMAKE_OSX_SYSROOT="$sdk_path" \
    -DCMAKE_C_COMPILER="$c_compiler" -DCMAKE_CXX_COMPILER="$compiler" \
    -DITK_BUILD_DEFAULT_MODULES=ON -DBUILD_TESTING=ON -DBUILD_SHARED_LIBS=OFF \
    -DBUILD_EXAMPLES=OFF -DITK_BUILD_DOCUMENTATION=OFF -DITK_WRAP_PYTHON=OFF \
    -DITK_USE_CCACHE=OFF -DCMAKE_DISABLE_FIND_PACKAGE_Python3=ON \
    -DCMAKE_DISABLE_FIND_PACKAGE_Python=ON -DCMAKE_DISABLE_FIND_PACKAGE_PythonInterp=ON \
    -DPython3_ROOT_DIR="$python_root_hint" -DExternalData_OBJECT_STORES="$store" \
    2>&1 | tee "$receipt/configure.log"
  ruby "$harness/audit-configure.rb" "$receipt/configure-trace.jsonl" \
    "$receipt/configure-execute-process.json"
  cp "$build_dir/CMakeCache.txt" "$receipt/"
  data_targets=(ExternalData/Testing/Data/Input/HeadMRVolumeCompressed.mha
    ExternalData/Modules/Video/Core/test/Baseline/HeadMRVolume_Frame0.mha)
  ninja -C "$build_dir" -t commands ITKVideoCoreTestDriver "${data_targets[@]}" \
    > "$receipt/internal-command-graph.txt"
  if grep -Ein 'python|[.]py|(^|/)cargo([[:space:]]|$)|(^|/)w3([[:space:]]|$)' \
    "$receipt/internal-command-graph.txt"; then
    exit 3
  fi
  ninja -C "$build_dir" -j3 ITKVideoCoreTestDriver "${data_targets[@]}" \
    2>&1 | tee "$receipt/internal-build.log"
  cp "$build_dir/bin/ITKVideoCoreTestDriver" "$receipt/"
  cp "$build_dir/Modules/Video/Core/test/ITKVideoCoreTestDriver.cxx" "$receipt/"
  cp "$build_dir/Modules/Video/Core/test/CTestTestfile.cmake" "$receipt/"
  cp "$source_dir/Modules/Video/Filtering/test/CMakeLists.txt" "$receipt/neighbor-registration-source.cmake"
  mkdir -p "$receipt/native-support"
  cp "$build_dir/lib/"*.a "$receipt/native-support/"
  shasum -a 256 "$receipt/ITKVideoCoreTestDriver" "$receipt/native-support/"*.a \
    > "$receipt/native-identities.sha256"
  shasum -a 256 "$build_dir/ExternalData/Testing/Data/Input/HeadMRVolumeCompressed.mha" \
    "$build_dir/ExternalData/Modules/Video/Core/test/Baseline/HeadMRVolume_Frame0.mha" \
    > "$receipt/runtime-input-identities.sha256"
}

run_internal() {
  local build_dir="$1" receipt="$2"
  local ctest="$tools/cmake-4.0.1-macos-universal/CMake.app/Contents/bin/ctest"
  export ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=3 ITK_GLOBAL_DEFAULT_THREADER=Pool
  "$ctest" --test-dir "$build_dir" --show-only=json-v1 \
    -R '^(ImageToVideoFilterTest|VectorImageToVideoTest|FrameAverageVideoFilterTest|DecimateFramesVideoFilterTest)$' \
    > "$receipt/planned-neighbor-registrations.json"
  set +e
  arch -x86_64 "$ctest" --test-dir "$build_dir" --verbose --output-on-failure \
    --no-tests=error -R '^ImageToVideoFilterTest$' 2>&1 | tee "$receipt/ctest.log"
  test_status=${PIPESTATUS[0]}
  set -e
  printf '%s\n' "$test_status" > "$receipt/ctest.exit"
  cp -R "$build_dir/Testing" "$receipt/"
  if test -f "$build_dir/Testing/Temporary/ITKVideoCore/HeadMRVolume_Frame0.mha"; then
    cp "$build_dir/Testing/Temporary/ITKVideoCore/HeadMRVolume_Frame0.mha" "$receipt/"
    set +e
    cmp "$out/expected-frame.mha" "$receipt/HeadMRVolume_Frame0.mha" \
      > "$receipt/output-byte-comparison.txt" 2>&1
    output_comparison_status=$?
    set -e
    printf '%s\n' "$output_comparison_status" > "$receipt/output-byte-comparison.exit"
  else
    printf 'Output absent after original CTest/cleanup; no byte comparison claimed\n' \
      > "$receipt/output-byte-comparison-unavailable.txt"
  fi
}

configure_internal "$source_root" "$build" "$out/internal-original"
run_internal "$build" "$out/internal-original"
original_status="$test_status"
test -z "$(git -C "$source_root" status --porcelain)"

# Separate counterfactual: change only the private validated traversal clone.
# The original source, target, executable, output and status remain preserved.
set +e
(
set -e
traversal_source="$root/internal-traversal-source"
git -C "$source_root" worktree add --detach "$traversal_source" "$ITK7015_SOURCE_REF"
patch --batch --forward -d "$traversal_source" -p1 < "$harness/traversal-only.patch"
printf '%s  %s\n' 81040d79696781d3b3853ad7a1f044b9a2073da5b5878723eb71084afe707f79 \
  "$traversal_source/Modules/Video/Core/test/itkImageToVideoFilterTest.cxx" | shasum -a 256 -c -
cp "$harness/traversal-only.patch" "$out/"
git -C "$traversal_source" diff -- Modules/Video/Core/test/itkImageToVideoFilterTest.cxx \
  > "$out/internal-traversal-source.diff"
set +e
(
  set -e
  configure_internal "$traversal_source" "$root/internal-traversal-build" "$out/internal-traversal"
  run_internal "$root/internal-traversal-build" "$out/internal-traversal"
  exit "$test_status"
)
traversal_status=$?
set -e
printf '%s\n' "$traversal_status" > "$out/internal-traversal.exit"
test -z "$(git -C "$source_root" status --porcelain)"
if test "$original_status" -ne 0; then
  diagnostic_source="$root/internal-diagnostic-source"
  git -C "$source_root" worktree add --detach "$diagnostic_source" "$ITK7015_SOURCE_REF"
  ruby -e 's=File.read(ARGV[0]).sub("itkImageToVideoFilterTestDiagnostic(int argc, char * argv[])","itkImageToVideoFilterTest(int argc, char * argv[])"); File.write(ARGV[1],s)' \
    "$out/diagnostic-test.cxx" "$diagnostic_source/Modules/Video/Core/test/itkImageToVideoFilterTest.cxx"
  diff -u "$original" "$diagnostic_source/Modules/Video/Core/test/itkImageToVideoFilterTest.cxx" \
    > "$out/internal-diagnostic-test.diff" || test "$?" -eq 1
  set +e
  (
    set -e
    configure_internal "$diagnostic_source" "$root/internal-diagnostic-build" "$out/internal-snapshot"
    run_internal "$root/internal-diagnostic-build" "$out/internal-snapshot"
    exit "$test_status"
  )
  snapshot_status=$?
  set -e
  printf '%s\n' "$snapshot_status" > "$out/internal-snapshot.exit"
fi
printf 'original_ctest_exit=%s\ntraversal_phase_exit=%s\n' "$original_status" "$traversal_status" \
  > "$out/paired-internal-summary.txt"
for executable in "$out/internal-original/ITKVideoCoreTestDriver" \
  "$out/internal-traversal/ITKVideoCoreTestDriver"; do
  if test -f "$executable"; then
    shasum -a 256 "$executable" >> "$out/paired-internal-summary.txt"
  fi
done
exit "$traversal_status"
)
followup_status=$?
set -e
printf '%s\n' "$followup_status" > "$out/internal-followup.exit"
if test "$original_status" -ne 0; then
  exit "$original_status"
fi
exit "$followup_status"
