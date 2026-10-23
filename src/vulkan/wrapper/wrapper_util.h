#ifndef __WRAPPER_UTIL_H
#define __WRAPPER_UTIL_H

#include <sys/stat.h>
#include <sys/types.h>
#include <unistd.h>
#include <stdbool.h>

#define CREATE_FOLDER(folder, mode) \
do { \
   struct stat sb; \
   if (stat(folder, &sb) != 0 || !S_ISDIR(sb.st_mode)) { \
      mode_t old_mask = umask(0); \
      (void)mkdir(folder, (mode)); \
      umask(old_mask); \
      (void)chmod(folder, (mode)); \
   } \
} while (0)

#ifdef __cplusplus
extern "C" {
#endif

char *
get_executable_name(void);

#ifdef __cplusplus
}
#endif

#endif /* __WRAPPER_UTIL_H */
