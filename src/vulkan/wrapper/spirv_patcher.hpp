#ifndef SPIRV_PATCHER_HPP
#define SPIRV_PATCHER_HPP

#ifdef __cplusplus
#include <cstdint>
#include <cstddef>
#else
#include <stdint.h>
#include <stddef.h>
#include <stdbool.h>
#endif

#ifdef __cplusplus
extern "C" {
#endif

void patch_OpConstantComposite_to_OpSpecConstantComposite(uint32_t *code, size_t size);
void remove_ClipDistance(uint32_t *code, size_t *size);

#ifdef __cplusplus
}
#endif

#endif /* SPIRV_PATCHER_HPP */
