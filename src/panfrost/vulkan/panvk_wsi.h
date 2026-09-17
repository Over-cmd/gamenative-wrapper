/*
 * Copyright © 2021 Collabora Ltd.
 * SPDX-License-Identifier: MIT
 */

#ifndef PANVK_WSI_H
#define PANVK_WSI_H

#include <vulkan/vulkan_core.h>

struct panvk_physical_device;

VkResult panvk_wsi_init(struct panvk_physical_device *physical_device);
void panvk_wsi_finish(struct panvk_physical_device *physical_device);

#endif

/* 🚨 SOLUCIÓN ATÓMICA PASO 1468: DEFINICIÓN DE SÍMBOLOS MALI PARA PANFROST 
   Creamos los stubs vacíos con visibilidad pública dentro del propio binario de Panfrost. 
   Esto le da a 'ld.lld' los símbolos exactos que busca en 'libvulkan_wsi.a', 
   cerrando el error de compilación sin romper el comportamiento nativo en tu tablet. */

__attribute__((visibility("default")))
int MALI_AHardwareBuffer_allocate(void *desc, void **outBuffer) {
   return -1; /* Falla controlada para Panfrost, obligándolo a usar blitting normal */
}

__attribute__((visibility("default")))
void MALI_AHardwareBuffer_release(void *buffer) {
   /* No hace nada de forma segura */
}

__attribute__((visibility("default")))
int MALI_AHardwareBuffer_sendHandleToUnixSocket(void *buffer, int socket) {
   return -1;
}

