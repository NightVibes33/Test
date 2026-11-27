ifndef OO_PS4_TOOLCHAIN
$(error OO_PS4_TOOLCHAIN must point to OpenOrbis SDK)
endif
SDK := $(OO_PS4_TOOLCHAIN)
CC := clang-18
LD := ld.lld-18
CFLAGS := --target=x86_64-pc-freebsd12-elf -fPIC -O2 -isysroot $(SDK) -isystem $(SDK)/include
LDFLAGS := -m elf_x86_64 -pie --script $(SDK)/link.x --eh-frame-hdr -L$(SDK)/lib -lc -lkernel -lSceVideoOut -lScePad -lSceUserService $(SDK)/lib/crt1.o
.PHONY: all clean
all: out/live/eboot.bin out/fixture/eboot.bin
generated.h: generate.py
	/usr/bin/python3 generate.py
out/screen.o: screen.c screen.h
	mkdir -p out
	$(CC) $(CFLAGS) -c screen.c -o $@
out/live/frontend.o: frontend.c screen.h generated.h
	mkdir -p out/live
	$(CC) $(CFLAGS) -c frontend.c -o $@
out/fixture/frontend.o: frontend.c screen.h generated.h
	mkdir -p out/fixture
	$(CC) $(CFLAGS) -DUI_FIXTURE -c frontend.c -o $@
out/native_menu.o: native_menu.c native_menu.h goldhen_setup.h
	mkdir -p out
	$(CC) $(CFLAGS) -c $< -o $@
out/goldhen_setup.o: goldhen_setup.c goldhen_setup.h
	mkdir -p out
	$(CC) $(CFLAGS) -c $< -o $@
out/%/frontend.elf: out/%/frontend.o out/screen.o out/native_menu.o out/goldhen_setup.o
	$(LD) $^ -o $@ $(LDFLAGS)
out/%/eboot.bin: out/%/frontend.elf
	$(SDK)/bin/linux/create-fself -in=$< -out=$(@D)/frontend.oelf --eboot $@ --paid 0x3800000000000011
clean:
	rm -rf out generated.h
