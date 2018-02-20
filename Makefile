.SUFFIXES:
.PHONY: objects asmgen events bindmps clean

# making sure devkitARM exists and is set up
ifeq ($(strip $(DEVKITARM)),)
	$(error "Please set DEVKITARM in your environment. export DEVKITARM=<path to>devkitARM")
endif

# including devkitARM tool definitions
include $(DEVKITARM)/base_tools

# adding local binaries to path
PATH := $(abspath .)/bin:$(PATH)

# setting up compilation flags
ARCH   := -mcpu=arm7tdmi -mthumb -mthumb-interwork
CFLAGS := $(ARCH) -Wall -Os -mtune=arm7tdmi -fomit-frame-pointer -ffast-math

# lyn library object
LYNLIB := fe8u.o

# listing files
CFILES := $(wildcard *.c)
SFILES := $(wildcard *.s)
OFILES := $(CFILES:.c=.o) $(SFILES:.s=.o)
ASMFILES := $(CFILES:.c=.asm)
LYNFILES := $(OFILES:.o=.lyn.event)
DMPFILES := $(OFILES:.o=.dmp)

# defining & making dependency directory
DEPSDIR := .MkDeps
$(shell mkdir -p $(DEPSDIR) > /dev/null)

# listing possible dependency files
DEPFILES := $(addprefix $(DEPSDIR)/, $(notdir $(CFILES:.c=.d)))

# dependency generation flags for CC
CDEPFLAGS = -MD -MT $*.o -MT $*.asm -MF $(DEPSDIR)/$(notdir $*).d -MP

# "make all" phony targets
objects: $(OFILES);
asmgen: $(ASMFILES);
events: $(LYNFILES);
bindmps: $(DMPFILES)

# "Clean" target
clean:
	@rm -f $(OFILES) $(ASMFILES) $(LYNFILES) $(DMPFILES) $(DEPFILES)
	@echo done.

# C to ASM rule
%.asm: %.c
	@echo "$(notdir $<) => $(notdir $@)"
	@$(CC) $(CFLAGS) $(CDEPFLAGS) -S $< -o $@ -fverbose-asm $(ERROR_FILTER)

# C to OBJ rule
%.o: %.c
	@echo "$(notdir $<) => $(notdir $@)"
	@$(CC) $(CFLAGS) $(CDEPFLAGS) -c $< -o $@ $(ERROR_FILTER)

# ASM to OBJ rule
%.o: %.s
	@echo "$(notdir $<) => $(notdir $@)"
	@$(AS) $(ARCH) $< -o $@ $(ERROR_FILTER)

# OBJ to DMP rule
%.dmp: %.o
	@echo "$(notdir $<) => $(notdir $@)"
	@$(OBJCOPY) -S $< -O binary $@

# OBJ to EVENT rule
%.lyn.event: %.o $(LYNLIB)
	@echo "$(notdir $<) => $(notdir $@)"
	@lyn $< $(LYNLIB) > $@

# Including generated dependency rules
-include $(DEPFILES)
