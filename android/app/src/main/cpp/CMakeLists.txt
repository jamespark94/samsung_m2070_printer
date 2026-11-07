cmake_minimum_required(VERSION 3.18.1)
project("spl_encoder" C CXX)

set(CMAKE_CXX_STANDARD 17)

include_directories(
    ${CMAKE_CURRENT_SOURCE_DIR}/jbig
)

add_library(spl_encoder SHARED
    jbig/jbig.c
    jbig/jbig_ar.c
    qpdl_encoder.cpp
    native_bridge.cpp
)

target_link_libraries(spl_encoder
    jnigraphics
    log
)
