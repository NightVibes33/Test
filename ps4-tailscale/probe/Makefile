ifndef PS4_PAYLOAD_SDK
$(error Set PS4_PAYLOAD_SDK to the installed PS4 payload SDK)
endif
include $(PS4_PAYLOAD_SDK)/toolchain/orbis.mk
.PHONY: all clean
all: ps4-network-probe.elf ps4-abi-probe.elf
ps4-network-probe.elf: main.c
	$(CC) -O2 -Wall -Wextra $< -o $@
ps4-abi-probe.elf: abi.c
	$(CC) -O2 -Wall -Wextra $< -o $@ -pthread
clean:
	rm -f ps4-network-probe.elf ps4-abi-probe.elf
