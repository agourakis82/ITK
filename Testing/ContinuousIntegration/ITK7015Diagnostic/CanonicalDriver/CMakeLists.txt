cmake_minimum_required(VERSION 3.22)
project(ITK7015CanonicalDriver LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 23)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
find_package(ITK REQUIRED COMPONENTS ITKVideoCore ITKVideoIO ITKTestKernel)
if(NOT ITK7015_SOURCE_ROOT OR NOT ITK7015_INPUT OR NOT ITK7015_BASELINE)
  message(FATAL_ERROR "Exact source, original input and original baseline are required")
endif()

# Match ITKVideoCore's complete original driver table and ITKModuleTest's hooks.
set(KitTests
  itkImageToVideoFilterTest.cxx
  itkRingBufferTest.cxx
  itkTemporalDataObjectTest.cxx
  itkTemporalProcessObjectTest.cxx
  itkTemporalRegionTest.cxx
  itkVectorImageToVideoTest.cxx
  itkVideoSourceTest.cxx
  itkVideoStreamTest.cxx)
set(CMAKE_TESTDRIVER_BEFORE_TESTMAIN "#include \"itkTestDriverBeforeTest.inc\"")
set(CMAKE_TESTDRIVER_AFTER_TESTMAIN "#include \"itkTestDriverAfterTest.inc\"")
create_test_sourcelist(Tests ITKVideoCoreTestDriver.cxx ${KitTests}
  EXTRA_INCLUDE itkTestDriverIncludeRequiredFactories.h
  FUNCTION ProcessArgumentsAndRegisterRequiredFactories)
list(TRANSFORM KitTests PREPEND "${ITK7015_SOURCE_ROOT}/Modules/Video/Core/test/")
add_executable(ITKVideoCoreTestDriver ITKVideoCoreTestDriver.cxx ${KitTests})
target_include_directories(ITKVideoCoreTestDriver PRIVATE ${ITK_INCLUDE_DIRS})
target_link_libraries(ITKVideoCoreTestDriver PRIVATE ${ITK_LIBRARIES})

enable_testing()
add_test(NAME ImageToVideoFilterTest COMMAND ITKVideoCoreTestDriver
  --compare "${ITK7015_BASELINE}" "${CMAKE_CURRENT_BINARY_DIR}/HeadMRVolume_Frame0.mha"
  itkImageToVideoFilterTest "${ITK7015_INPUT}" "${CMAKE_CURRENT_BINARY_DIR}/HeadMRVolume_Frame0.mha")
set_tests_properties(ImageToVideoFilterTest PROPERTIES ENVIRONMENT
  "ITK_GLOBAL_DEFAULT_NUMBER_OF_THREADS=3;ITK_GLOBAL_DEFAULT_THREADER=Pool")
