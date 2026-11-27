ifndef RUNTIME_DIR
$(error RUNTIME_DIR required)
endif
CC := clang-18
LD := ld.lld-18
CFLAGS := -target x86_64-unknown-freebsd -ffreestanding -fno-builtin -fno-stack-protector -fPIE -fvisibility=hidden -O2 -DPS4_FREESTANDING -DPS4_PAYLOAD_BUILD -DRUNTIME_IMAGE='"$(RUNTIME_DIR)/relay-NOT-PS4-LOADABLE.elf"'
LDFLAGS := -pie --no-dynamic-linker -z max-page-size=0x4000 -e _start --no-undefined
.PHONY: all
all: TailScale.elf TailScale-map-probe.elf
loader.o: ../homebrew/runtime_loader.c ../homebrew/runtime_loader.h freestanding.h
	$(CC) $(CFLAGS) -c $< -o $@
support.o: freestanding.c freestanding.h
	$(CC) $(CFLAGS) -c $< -o $@
main.o: main.c
	$(CC) $(CFLAGS) -c $< -o $@
probe.o: main.c
	$(CC) $(CFLAGS) -DMAP_PROBE -c $< -o $@
TailScale.elf: main.o loader.o support.o
	$(LD) $(LDFLAGS) $^ -o $@
TailScale-map-probe.elf: probe.o loader.o support.o
	$(LD) $(LDFLAGS) $^ -o $@
