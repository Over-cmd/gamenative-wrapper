#include <stdlib.h>
#include <dlfcn.h>
#include <string>
#include <iostream>
#include <unistd.h>
#include <mutex>

#include "graphicsenv_hook.hpp"
#include "wrapper_log.h"

#define LIBNAME "/system/lib64/libgraphicsenv.so"
#define WRAPPER_LAYERS_PATH "/data/data/com.winlator.cmod/files/imagefs/usr/lib:/data/data/com.termux/files/usr/lib"

static void *graphicsenv_handle = nullptr;
static std::string env_layers_path;
static std::once_flag init_flag;

static void *(*getInstance)() = nullptr;
static void *(*getAppNamespace)(void *) = nullptr;
// Apuntadores adaptados para evitar fallos de ABI estrictos entre versiones de Android
static void (*setLayerPaths_ref)(void *, void *, const std::string&) = nullptr;
static void (*setLayerPaths_val)(void *, void *, std::string) = nullptr;

template <typename T>
void get_function_pointer(T& pointer, void* handle, const std::string& name) {
   if (!pointer && handle) {
      pointer = reinterpret_cast<T>(dlsym(handle, name.c_str()));
   }
}

extern "C"
bool set_layer_paths() {
   bool success = false;

   std::call_once(init_flag, []() {
      // 1. Intentar cargar libgraphicsenv.so con la ruta estándar
      graphicsenv_handle = dlopen(LIBNAME, RTLD_NOW | RTLD_GLOBAL);
      
      // 2. Si falla debido a restricciones de namespace en Android 14+, intentar buscar en el espacio global del proceso
      if (!graphicsenv_handle) {
         graphicsenv_handle = dlopen(nullptr, RTLD_NOW | RTLD_GLOBAL);
         if (!graphicsenv_handle) {
            WRAPPER_LOG(error, "Failed to dlopen libgraphicsenv.so or global scope: %s", dlerror());
            return;
         }
      }

      get_function_pointer(getInstance, graphicsenv_handle, "_ZN7android11GraphicsEnv11getInstanceEv");
      get_function_pointer(getAppNamespace, graphicsenv_handle, "_ZN7android11GraphicsEnv15getAppNamespaceEv");
      
      // Intentar múltiples variantes de símbolos para setLayerPaths según la versión de Android
      get_function_pointer(setLayerPaths_ref, graphicsenv_handle, "_ZN7android11GraphicsEnv13setLayerPathsEPNS_21NativeLoaderNamespaceERKNSt3__112basic_stringIcNS3_11char_traitsIcEENS3_9allocatorIcEEEE");
      if (!setLayerPaths_ref) {
         get_function_pointer(setLayerPaths_val, graphicsenv_handle, "_ZN7android11GraphicsEnv13setLayerPathsEPNS_21NativeLoaderNamespaceENSt3__112basic_stringIcNS3_11char_traitsIcEENS3_9allocatorIcEEEE");
      }

      if (!getInstance || !getAppNamespace || (!setLayerPaths_ref && !setLayerPaths_val)) {
         WRAPPER_LOG(error, "Failed to get essential function pointers from libgraphicsenv.so");
         return;    	
      }

      void *instance = getInstance();
      if (!instance) {
         WRAPPER_LOG(error, "Failed to obtain GraphicsEnv instance");
         return;
      }

      void *app_namespace = getAppNamespace(instance);
      if (!app_namespace) {
         WRAPPER_LOG(warning, "App namespace is null, layer paths might not bind correctly");
      }

      if (env_layers_path.empty()) {
         const char *env = getenv("WRAPPER_LAYER_PATH");
         if (env)
            env_layers_path = env;
         if (env_layers_path.empty())
            env_layers_path = WRAPPER_LAYERS_PATH;
      }

      // Ejecutar según la firma que haya resuelto el símbolo correctamente
      if (setLayerPaths_ref) {
         setLayerPaths_ref(instance, app_namespace, env_layers_path);
      } else if (setLayerPaths_val) {
         setLayerPaths_val(instance, app_namespace, env_layers_path);
      }

      WRAPPER_LOG(info, "Successfully applied layer paths: %s", env_layers_path.c_str());
   });

   // Validar si los punteros críticos se resolvieron con éxito tras la ejecución única
   if (getInstance && getAppNamespace && (setLayerPaths_ref || setLayerPaths_val)) {
      success = true;
   }

   return success;
}
