cmake_minimum_required(VERSION 3.20)
project(amr_onnx LANGUAGES CXX)

if(NOT WIN32 OR NOT CMAKE_SIZEOF_VOID_P EQUAL 8)
  message(FATAL_ERROR "The D2 bridge targets Windows x64.")
endif()

set(ORT_ROOT "" CACHE PATH "Extracted Windows x64 ONNX Runtime CPU SDK")
find_path(ORT_INCLUDE onnxruntime_cxx_api.h PATHS "${ORT_ROOT}/include"
  REQUIRED NO_DEFAULT_PATH)
find_library(ORT_IMPORT onnxruntime PATHS "${ORT_ROOT}/lib"
  REQUIRED NO_DEFAULT_PATH)

add_library(amr_onnx SHARED bridge.cpp)
target_compile_features(amr_onnx PRIVATE cxx_std_17)
target_include_directories(amr_onnx SYSTEM PRIVATE "${ORT_INCLUDE}")
target_link_libraries(amr_onnx PRIVATE "${ORT_IMPORT}")
