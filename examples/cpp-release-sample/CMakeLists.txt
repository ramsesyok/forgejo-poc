cmake_minimum_required(VERSION 3.12)
project(cpp_release_sample LANGUAGES CXX)

set(SAMPLE_VERSION "0.1.0" CACHE STRING "Version embedded in the sample executable")

configure_file(src/version.hpp.in generated/version.hpp @ONLY)

add_executable(cpp-release-sample src/main.cpp)
set_target_properties(cpp-release-sample PROPERTIES
    RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}/bin")
target_compile_features(cpp-release-sample PRIVATE cxx_std_17)
target_include_directories(cpp-release-sample PRIVATE "${CMAKE_CURRENT_BINARY_DIR}/generated")

if(CMAKE_CXX_COMPILER_ID MATCHES "GNU|Clang")
    target_compile_options(cpp-release-sample PRIVATE -Wall -Wextra -Wpedantic)
endif()

include(CTest)
if(BUILD_TESTING)
    add_test(NAME greeting COMMAND cpp-release-sample)
    set_tests_properties(greeting PROPERTIES PASS_REGULAR_EXPRESSION "Hello from Forgejo Actions!")

    add_test(NAME version COMMAND cpp-release-sample --version)
    # The workflow compares the complete --version output; CTest checks that it runs successfully.
endif()
