#ifndef SPIRV_PATCHER_HPP
#define SPIRV_PATCHER_HPP

#pragma once

#ifdef __cplusplus
#include <cstdint>
#include <cstddef>
#else
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#endif

/* Definición robusta del macro de exportación para toolchains de Android/Linux (Clang/GCC) */
#if defined(_WIN32) || defined(_WIN64)
  #ifdef SPIRV_PATCHER_EXPORTS
    #define SPIRV_PATCHER_API __declspec(dllexport)
  #else
    #define SPIRV_PATCHER_API __declspec(dllimport)
  #endif
#else
  #if defined(__GNUC__) && __GNUC__ >= 4
    #define SPIRV_PATCHER_API __attribute__((visibility("default")))
  #else
    #define SPIRV_PATCHER_API
  #endif
#endif

#ifdef __cplusplus
extern "C" {
#endif

SPIRV_PATCHER_API void patch_OpConstantComposite_to_OpSpecConstantComposite(uint32_t *pCode, size_t size);
SPIRV_PATCHER_API void remove_ClipDistance(uint32_t *pCode, size_t *size);

#undef SPIRV_PATCHER_API

#ifdef __cplusplus
}
#endif

#endif /* SPIRV_PATCHER_HPP */
