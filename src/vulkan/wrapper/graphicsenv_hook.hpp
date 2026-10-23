#ifndef GRAPHICSENV_HOOK_HPP
#define GRAPHICSENV_HOOK_HPP

#pragma once

#ifdef __cplusplus
extern "C" {
#endif

/* Definición robusta del macro de exportación para toolchains de Android (Clang/GCC) */
#if defined(_WIN32) || defined(_WIN64)
  #ifdef GRAPHICSENV_HOOK_EXPORTS
    #define GRAPHICSENV_HOOK_API __declspec(dllexport)
  #else
    #define GRAPHICSENV_HOOK_API __declspec(dllimport)
  #endif
#else
  #if defined(__GNUC__) && __GNUC__ >= 4
    #define GRAPHICSENV_HOOK_API __attribute__((visibility("default")))
  #else
    #define GRAPHICSENV_HOOK_API
  #endif
#endif

/* 
 * Configura las rutas de las capas gráficas (Vulkan layers / GraphicsEnv).
 * Utiliza visibilidad explícita para garantizar que se exporte 
 * correctamente en la biblioteca compartida (.so) cargada en Android.
 */
GRAPHICSENV_HOOK_API bool set_layer_paths();

#undef GRAPHICSENV_HOOK_API

#ifdef __cplusplus
}
#endif

#endif /* GRAPHICSENV_HOOK_HPP */
