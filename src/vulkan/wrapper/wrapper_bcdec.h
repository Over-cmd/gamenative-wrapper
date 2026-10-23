#ifndef WRAPPER_BCDEC_H
#define WRAPPER_BCDEC_H

#pragma once

#include "wrapper_private.h"
#include <stddef.h>

#ifdef __cplusplus
extern "C" {
#endif

/* Definición robusta del macro de exportación para toolchains de Android/Linux (Clang/GCC) */
#if defined(_WIN32) || defined(_WIN64)
  #ifdef WRAPPER_BCDEC_EXPORTS
    #define WRAPPER_BCDEC_EXPORT __declspec(dllexport)
  #else
    #define WRAPPER_BCDEC_EXPORT __declspec(dllimport)
  #endif
#else
  #if defined(__GNUC__) && __GNUC__ >= 4
    #define WRAPPER_BCDEC_EXPORT __attribute__((visibility("default")))
  #else
    #define WRAPPER_BCDEC_EXPORT
  #endif
#endif

WRAPPER_BCDEC_EXPORT VkFormat
get_format_for_bcn(VkFormat bcn_format);

WRAPPER_BCDEC_EXPORT VkFormat
get_decode_format_for_bcn(VkFormat bcn_format);

WRAPPER_BCDEC_EXPORT int
is_astc_4x4(VkFormat format);

WRAPPER_BCDEC_EXPORT int
is_astc_8x8(VkFormat format);

WRAPPER_BCDEC_EXPORT int
is_astc(VkFormat format);

WRAPPER_BCDEC_EXPORT size_t
bcn_upload_size(VkFormat bcn_format, int w, int h);

WRAPPER_BCDEC_EXPORT int
get_texel_size_for_format(VkFormat format);

WRAPPER_BCDEC_EXPORT int
is_emulated_bcn(struct wrapper_physical_device *pdev, VkFormat format);

WRAPPER_BCDEC_EXPORT void
decompress_bcn_format(void *srcBuffer,
                      void *dstBuffer,
                      int w,
                      int h,
                      int src_w,
                      VkFormat format,
                      int offset);

#undef WRAPPER_BCDEC_EXPORT

#ifdef __cplusplus
}
#endif

#endif /* WRAPPER_BCDEC_H */
