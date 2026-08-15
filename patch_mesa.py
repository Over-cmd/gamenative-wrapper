import os 

### 1. Parchando vk_instance.c

t1 = 'src/vulkan/runtime/vk_instance.c'
if os.path.exists(t1):
with open(t1, 'r') as f:
content = f.read()
patch = '\n#include <stdint.h>\nextern int mallopt(int p, int v);\nextern int setenv(const char* n, const char* v, int o);\n'
content = patch + content.replace('vk_icdGetInstanceProcAddr', 'mallopt(-1002,0);setenv("MESA_VK_WSI_PRESENT_MODE","mailbox",1);setenv("vblank_mode","0",1);if(sizeof(void*)==4){setenv("MESA_VK_WSI_QUEUE_SIZE","1","1");}vk_icdGetInstanceProcAddr', 1)
with open(t1, 'w') as f:
f.write(content) 

### 2. Parchando wsi_common.c

t2 = 'src/vulkan/wsi/wsi_common.c'
if os.path.exists(t2):
with open(t2, 'r') as f:
content = f.read()
content = content.replace('wsi_device_init(', 'if(sizeof(void*)==4){setenv("MESA_VK_WSI_QUEUE_SIZE","1",1);setenv("vblank_mode","0",1);} wsi_device_init(', 1)
with open(t2, 'w') as f:
f.write(content) 

### 3. Parchando meson.build para neutralizar atomic y dl

t3 = 'meson.build'
if os.path.exists(t3):
with open(t3, 'r') as f:
content = f.read()
content = content.replace("find_library('atomic')", "dependency('',required:false)") 
.replace("find_library('atomic',", "dependency('',required:false),") 
.replace("find_library('dl')", "dependency('',required:false)") 
.replace("find_library('dl',", "dependency('',required:false),")
with open(t3, 'w') as f:
f.write(content) 

print("-> Parches biónicos de silicio aplicados con éxito.")
