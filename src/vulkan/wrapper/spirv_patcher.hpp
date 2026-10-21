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

/* Prototipos de funciones del parcheador de SPIR-V expuestos hacia C */
bool patch_spirv_shader(uint32_t *code, size_t size, uint32_t *out_size);

#ifdef __cplusplus
}
#endif

#endif /* SPIRV_PATCHER_HPP */
