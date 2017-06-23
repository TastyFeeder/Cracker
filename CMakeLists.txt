cmake_minimum_required(VERSION 2.8)
project( cracker )
find_package(CUDA REQUIRED)
set(CMAKE_CXX_FLAGS_RELEASE "-O3")
set(CUDA_64_BIT_DEVICE_CODE ON)


cuda_add_executable( cracker main.cu )

