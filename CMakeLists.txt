cmake_minimum_required(VERSION 3.20)

project(GAME
    VERSION 0.1.0
    LANGUAGES CXX
)

include(CTest)
set(CMAKE_RUNTIME_OUTPUT_DIRECTORY "${CMAKE_BINARY_DIR}")
add_subdirectory(legacy/terminal-cpp)
