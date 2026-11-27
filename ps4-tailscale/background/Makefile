ifndef PS4_PAYLOAD_SDK
$(error PS4_PAYLOAD_SDK required)
endif
ifndef RUNTIME_DIR
$(error RUNTIME_DIR required)
endif
include $(PS4_PAYLOAD_SDK)/toolchain/orbis.mk
.PHONY: all
all: TailScale.elf
TailScale.elf: main.c ../homebrew/runtime_loader.c ../homebrew/runtime_loader.h
	$(CC) -O2 -DPS4_PAYLOAD_BUILD -DRUNTIME_IMAGE='"$(RUNTIME_DIR)/relay-NOT-PS4-LOADABLE.elf"' main.c ../homebrew/runtime_loader.c -o $@
