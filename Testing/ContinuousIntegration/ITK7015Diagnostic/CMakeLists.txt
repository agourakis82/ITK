cmake_minimum_required(VERSION 3.22)
project(ITK7015OriginalCase LANGUAGES CXX)
set(CMAKE_CXX_STANDARD 17)
set(CMAKE_CXX_STANDARD_REQUIRED ON)
set(CMAKE_CXX_EXTENSIONS OFF)
find_package(ITK REQUIRED COMPONENTS ITKVideoCore ITKIOMeta)
if(NOT ITK7015_SOURCE_ROOT OR NOT ITK7015_DIAGNOSTIC_SOURCE)
  message(FATAL_ERROR "The exact source and separate diagnostic source are required")
endif()
add_executable(itk7015-original-case main.cxx
  ${ITK7015_SOURCE_ROOT}/Modules/Video/Core/test/itkImageToVideoFilterTest.cxx)
add_executable(itk7015-diagnostic-case EXCLUDE_FROM_ALL main.cxx
  ${ITK7015_DIAGNOSTIC_SOURCE})
target_compile_definitions(itk7015-diagnostic-case PRIVATE ITK7015_DIAGNOSTIC=1)
foreach(target itk7015-original-case itk7015-diagnostic-case)
  target_include_directories(${target} PRIVATE ${ITK_INCLUDE_DIRS}
    ${ITK7015_SOURCE_ROOT}/Modules/Core/TestKernel/include)
  target_link_libraries(${target} PRIVATE ${ITK_LIBRARIES})
endforeach()
