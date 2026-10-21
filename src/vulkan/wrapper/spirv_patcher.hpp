#ifndef __SPIRV_PATCHER_HPP
#define __SPIRV_PATCHER_HPP

#pragma once

#include <cstdint>
#include <cstddef>

#ifdef __cplusplus
extern "C" {
#endif

#if defined(__GNUC__) && __GNUC__ >= 4
  __attribute__((visibility("default")))
#endif
void
remove_ClipDistance(uint32_t *pCode, size_t *codeSize);

#if defined(__GNUC__) && __GNUC__ >= 4
  __attribute__((visibility("default")))
#endif
void
patch_OpConstantComposite_to_OpSpecConstantComposite(uint32_t *pCode, uint32_t codeSize);

#ifdef __cplusplus
}
#endif

#endif /* __SPIRV_PATCHER_HPP */
