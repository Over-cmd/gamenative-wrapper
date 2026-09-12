#include <time.h>

#include "wrapper_log.h"
#include "wrapper_util.h"

#define PATH_MAX_SIZE 1024
#define WRAPPER_DIR "/sdcard/wrapper"
#define WRAPPER_SHADER_LOG_PATH WRAPPER_DIR "/shaders"
#define WRAPPER_LOG_PATH WRAPPER_DIR "/logs"
#define WRAPPER_VALIDATION_LOG_PATH WRAPPER_DIR "/validation"

static struct wrapper_log wrapper_log_options[] = {
	{"info", WRAPPER_LOG_INFO},
	{"error", WRAPPER_LOG_ERROR},
	{"shader", WRAPPER_LOG_SHADER},
	{"validation", WRAPPER_LOG_VALIDATION},
	{"bcn", WRAPPER_LOG_BCN},
	{"apidump", WRAPPER_LOG_APIDUMP},
	{NULL, 0}
};

uint64_t wrapper_log_mask;

static void get_formatted_date_time(char *buf, size_t length) 
{  
   time_t rawtime = time(NULL);
   struct tm *ptm = localtime(&rawtime);

   strftime(buf, 256, "%F_%H-%M-%S", ptm);
}

char *get_executable_name() {
   char *path = malloc(PATH_MAX);

   int fd = open("/proc/self/cmdline", O_RDONLY);

   if (fd != -1) {
      read(fd, path, PATH_MAX_SIZE);
      char *ptr = strrchr(path, '/');
      if (ptr)
         path = ptr + 1;
      ptr = strrchr(path, '\\');
      if (ptr)
         path = ptr + 1;
      close(fd);
   }
   
   return path;
}

static unsigned long long get_debug_flag(const char *option) {
   int index = 0;

   while (wrapper_log_options[index].name != NULL) {
      if (!strcmp(wrapper_log_options[index].name, option))
         return wrapper_log_options[index].value;
         
      index++;
   }

   return 0;
}

static void parse_wrapper_debug_str(char *wrapper_log_level_env) {
   if (!wrapper_log_level_env) {
      wrapper_log_mask = 0;
      return;
   }

   char *option = strtok(wrapper_log_level_env, ",");

   while (option != NULL) {
      wrapper_log_mask |= get_debug_flag(option);
      option = strtok(NULL, ",");
   }
}

int get_wrapper_log_level(const char *option) {
    uint64_t flag = get_debug_flag(option);

    if (wrapper_log_mask & flag)
       return 1;

    return 0;
}

void write_to_logfile(const char *fmt, const char *level, ...)  {
   /* 🚀 RENDIMIENTO EXTREMO MALI: Eliminamos las operaciones de escritura en disco
      para que la CPU ARM no asfixie el búfer de sonido de Android */
   (void)fmt;
   (void)level;
}

void init_wrapper_logging()
{
   /* 🚀 SILENCIO ABSOLUTO: Evitamos crear carpetas de logs innecesarias en cada inicio */
}

void dump_shader_code(const uint32_t *code, size_t size) {
   /* 🚀 RENDIMIENTO EXTREMO: Desactivamos el volcado de compilación en caliente
      para erradicar los micro-tirones gráficos (stuttering) */
   (void)code;
   (void)size;
}

VKAPI_ATTR VkBool32 VKAPI_CALL
wrapper_debug_utils_messenger(VkDebugUtilsMessageSeverityFlagBitsEXT messageSeverity,
                              VkDebugUtilsMessageTypeFlagsEXT messageTypes,
                              const VkDebugUtilsMessengerCallbackDataEXT *callbackData,
                              void *userData)
{
   /* 🚀 RUTA DIRECTA SILENCIOSA: Pasamos de largo de los logs de validación
      para que el búfer de sonido de Android fluya en perfecto tiempo real */
   (void)messageSeverity; 
   (void)messageTypes; 
   (void)callbackData; 
   void *dummy = userData; (void)dummy;
   return 0;
}
