include config.mk

# get main- and subtarget name from TARGET
MAINTARGET=$(word 1, $(subst _, ,$(TARGET)))
SUBTARGET=$(word 2, $(subst _, ,$(TARGET)))

ifeq ($(strip $(SUBTARGET)),)
	SUBTARGET:=generic
endif

GIT_REPO=git config --get remote.origin.url
GIT_BRANCH=git symbolic-ref HEAD | sed -e 's,.*/\(.*\),\1,'
REVISION=git describe --always --dirty
# set dir and file names
FW_DIR=$(shell pwd)
FW_REVISION=$(shell $(REVISION))
FW_BRANCH=$(shell $(GIT_BRANCH))
OPENWRT_DIR=$(FW_DIR)/build/$(FW_BRANCH)/openwrt
TARGET_CONFIG=$(FW_DIR)/configs/common.config $(FW_DIR)/configs/$(TARGET).config
IB_BUILD_DIR=$(FW_DIR)/imgbldr_tmp
FW_TARGET_DIR=$(FW_DIR)/firmwares/$(FW_REVISION)/$(MAINTARGET)/$(SUBTARGET)
UMASK=umask 022

# if any of the following files have been changed: clean up openwrt dir
DEPS=$(TARGET_CONFIG) feeds.conf patches $(wildcard patches/*)

# profiles to be built (router models)
PROFILES?=$(shell cat $(FW_DIR)/profiles/$(TARGET).profiles)


default: firmwares

# clone openwrt 
$(OPENWRT_DIR):
	git clone $(OPENWRT_SRC) $(OPENWRT_DIR)


# clean up openwrt working copy
openwrt-clean: stamp-clean-openwrt-cleaned .stamp-openwrt-cleaned
.stamp-openwrt-cleaned: config.mk | $(OPENWRT_DIR) openwrt-clean-bin
	cd $(OPENWRT_DIR); \
	  ./scripts/feeds clean && \
	  git clean -dff && git fetch --all && git reset --hard HEAD && \
	  rm -rf .config feeds.conf build_dir/target-* logs/
	touch $@

openwrt-clean-bin:
	rm -rf $(OPENWRT_DIR)/bin

# update openwrt and checkout specified commit
openwrt-update: stamp-clean-openwrt-updated .stamp-openwrt-updated
.stamp-openwrt-updated: .stamp-openwrt-cleaned | $(OPENWRT_DIR)/dl
	cd $(OPENWRT_DIR); \
		git checkout master && \
		git pull --all && \
		git checkout $(OPENWRT_COMMIT)
	touch $@

# patches require updated openwrt working copy
$(OPENWRT_DIR)/patches: | .stamp-openwrt-updated
	ln -s $(FW_DIR)/patches $@

# symlink download folder 
$(OPENWRT_DIR)/dl:
	mkdir $(FW_DIR)/dl || true && \
	ln -s $(FW_DIR)/dl $@

$(OPENWRT_DIR)/key-build:
	test -e $(FW_DIR)/key-build && \
		ln -s $(FW_DIR)/key-build $@ || \
		true

$(OPENWRT_DIR)/key-build.pub:
	test -e $(FW_DIR)/key-build && \
		ln -s $(FW_DIR)/key-build $@ || \
		true
# feeds
$(OPENWRT_DIR)/feeds.conf: .stamp-openwrt-updated feeds.conf
	cp $(FW_DIR)/feeds.conf $@

# update feeds
feeds-update: stamp-clean-feeds-updated .stamp-feeds-updated
.stamp-feeds-updated: $(OPENWRT_DIR)/feeds.conf unpatch
	+cd $(OPENWRT_DIR); \
	  ./scripts/feeds uninstall -a && \
	  ./scripts/feeds update && \
	  ./scripts/feeds install -a
	touch $@

# prepare patch
pre-patch: stamp-clean-pre-patch .stamp-pre-patch
.stamp-pre-patch: .stamp-feeds-updated $(wildcard $(FW_DIR)/patches/*) | $(OPENWRT_DIR)/patches
	touch $@

# patch openwrt working copy
patch: stamp-clean-patched .stamp-patched
.stamp-patched: .stamp-pre-patch
	cd $(OPENWRT_DIR); quilt push -a || ( [ $$? -eq 2 ] && true )
	touch $@

.stamp-build_rev: .FORCE
	$(eval FW_REVISION := $(FW_REVISION)+openwrt-$(shell cd $(OPENWRT_DIR); ./scripts/getver.sh))
	touch $@

# openwrt config
$(OPENWRT_DIR)/.config: .stamp-patched $(TARGET_CONFIG) .stamp-build_rev
	cat $(TARGET_CONFIG) >$(OPENWRT_DIR)/.config && \
	sed -i '/^CONFIG_VERSION_NUMBER=/d' $(OPENWRT_DIR)/.config && \
	echo "CONFIG_VERSION_NUMBER=$$FW_REVISION" >> $(OPENWRT_DIR)/.config
	$(UMASK); \
	  $(MAKE) -C $(OPENWRT_DIR) defconfig clean

# prepare openwrt working copy
prepare: stamp-clean-prepared .stamp-prepared
.stamp-prepared: .stamp-patched $(OPENWRT_DIR)/.config
	# delete tmpinfo to make patches work
	rm -rf $(OPENWRT_DIR)/tmp
	touch $@

# compile
compile: stamp-clean-compiled .stamp-compiled
.stamp-compiled: .stamp-prepared openwrt-clean-bin
	$(UMASK); \
	  $(MAKE) -C $(OPENWRT_DIR) $(MAKE_ARGS)
	touch $@

# fill firmwares-directory with:
#  * firmwares built with imagebuilder
#  * imagebuilder file
#  * packages directory
firmwares: stamp-clean-firmwares .stamp-firmwares
.stamp-firmwares: .stamp-compiled
	rm -rf $(IB_BUILD_DIR)
	mkdir -p $(IB_BUILD_DIR)
	$(eval TOOLCHAIN_PATH := $(shell printf "%s:" $(OPENWRT_DIR)/staging_dir/toolchain-*/bin))
	$(eval IB_FILE := $(shell ls $(OPENWRT_DIR)/bin/targets/$(MAINTARGET)/$(SUBTARGET)/*-imagebuilder-*.tar.xz))
	mkdir -p $(FW_TARGET_DIR)
	$(FW_DIR)/assemble_firmware.sh -d -p "$(PROFILES)" -i $(IB_FILE) -t $(FW_TARGET_DIR) -u "$(PKG_LIST)"
	# copy imagebuilder, sdk and toolchain (if existing)
	cp $$(find $(OPENWRT_DIR)/bin/targets/$(MAINTARGET) -type f -name "*imagebuilder-*.tar.xz") $(FW_TARGET_DIR)/
	# copy packages
	PACKAGES_DIR="$(FW_TARGET_DIR)/packages"; \
	cd $(OPENWRT_DIR)/bin; \
		rsync -avR $$(find targets -name packages -type d) $$PACKAGES_DIR; \
		rsync -avr packages $$PACKAGES_DIR
	touch $@

stamp-clean-%:
	rm -f .stamp-$*

stamp-clean:
	rm -f .stamp-*

# unpatch needs "patches/" in openwrt
unpatch: $(OPENWRT_DIR)/patches
# RC = 2 of quilt --> nothing to be done
	cd $(OPENWRT_DIR); quilt pop -a -f || [ $$? = 2 ] && true
	rm -f .stamp-patched

clean: stamp-clean .stamp-openwrt-cleaned

.PHONY: openwrt-clean openwrt-clean-bin openwrt-update openwrt-symlink-dl patch feeds-update prepare compile firmwares stamp-clean clean
.NOTPARALLEL:
.FORCE:
