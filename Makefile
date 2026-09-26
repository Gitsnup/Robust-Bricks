# This Source Code Form is subject to the terms of the Mozilla Public
# License, v. 2.0. If a copy of the MPL was not distributed with this
# file, You can obtain one at https://mozilla.org/MPL/2.0/.
#
# Builds Dared Bricks for iPhone OS 2.0 and later (armv6 + armv7) with clang and
# the common-3.0 SDK (https://github.com/touchHLE/common-3.0-sdk), which
# provides the linker, the startup code and stub system libraries.
#
#   make SDK=/path/to/common-3.0.sdk
#
# The result is build/DaredBricks.ipa. For a build where every broken brick
# drops a power-up, for testing them: make clean; make SDK=... CAPSULE_CHANCE=1024
# For a build where the paddle is as wide as the screen, so no ball is ever
# lost: make clean; make SDK=... FULL_PADDLE=true

CLANG ?= clang
BUILD := build
NAME := DaredBricks
IPA := $(BUILD)/$(NAME).ipa
# The app bundle is only assembled here long enough to be zipped into the .ipa.
STAGE := $(BUILD)/Payload/$(NAME).app

SOURCES := $(wildcard src/*.m)
HEADERS := $(wildcard src/*.h)
RESOURCES := $(wildcard resources/*)

CFLAGS := \
	--target=arm-apple-ios -miphoneos-version-min=2.0 \
	-arch armv6 -arch armv7 \
	--sysroot=$(SDK) -B$(SDK)/usr/bin -mlinker-version=253 \
	-nodefaultlibs -fno-stack-protector \
	-ObjC -fno-objc-exceptions -fno-objc-arc -fno-objc-arc-exceptions \
	-Os -Wall -Wno-objc-root-class
# For testing power-ups: CAPSULE_CHANCE=1024 makes every broken brick drop one.
ifdef CAPSULE_CHANCE
CFLAGS += -DCAPSULE_CHANCE=$(CAPSULE_CHANCE)
endif
# For testing: FULL_PADDLE=true makes the paddle as wide as the screen.
ifeq ($(FULL_PADDLE),true)
CFLAGS += -DFULL_PADDLE=1
endif
LIBS := \
	-framework UIKit -framework Foundation -framework CoreGraphics \
	-framework OpenAL \
	-lobjc.A -lSystem.B

.PHONY: all clean check-sdk

all: $(IPA)

check-sdk:
	@test -n "$(SDK)" || { echo "Set SDK to the common-3.0 SDK, e.g. make SDK=~/common-3.0.sdk" >&2; exit 1; }
	@test -x "$(SDK)/usr/bin/ld" || { echo "$(SDK) doesn't look like the common-3.0 SDK (no usr/bin/ld)" >&2; exit 1; }

$(IPA): $(SOURCES) $(HEADERS) $(RESOURCES) | check-sdk
	rm -rf $(BUILD)/Payload $@
	mkdir -p $(STAGE)
	$(CLANG) $(CFLAGS) $(SOURCES) $(LIBS) -o $(STAGE)/$(NAME)
	cp $(RESOURCES) $(STAGE)/
	cd $(BUILD) && zip -qr $(NAME).ipa Payload
	rm -rf $(BUILD)/Payload

clean:
	rm -rf $(BUILD)
