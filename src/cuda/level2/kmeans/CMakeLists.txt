cmake_minimum_required(VERSION 3.8)

add_library(kmeansLib
    kmmain.cu
    kmeansraw.cu
)
#set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS} --ptxas-options=-v")
#set(CMAKE_CUDA_FLAGS "${CMAKE_CUDA_FLAGS}  --cudart shared")
set(CMAKE_CUDA_RUNTIME_LIBRARY "Shared")

target_link_libraries(kmeansLib -lm)
#target_compile_options(kmeansLib PRIVATE $<$<COMPILE_LANGUAGE:CUDA>:
#                       --cudart shared;
#                       >)

