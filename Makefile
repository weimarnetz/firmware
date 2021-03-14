include config.mk

# get main- and subtarget name from TARGET
MAINTARGET=$(word 1, $(subst _, ,$(TARGET)))
CUSTOMTARGET=$(word 2, $(subst _, ,$(TARGET)))
SUBTARGET=$(word 1, $(subst -, ,$(CUSTOMTARGET)))

GIT_REPO=git config --get remote.origin.url
GIT_BRANCH=git symbolic-ref HEAD | sed -e 's,.*/\(.*\),\1,'
REVISION=git describe --always --dirty --tags
# set dir and file names
FW_DIR=$(shell pwd)
FW_REVISION=$(shell $(REVISION))
FW_BRANCH=$(shell $(GIT_BRANCH))
OPENWRT_DIR=$(FW_DIR)/openwrt
VERSION_FILE=$(FW_TARGET_DIR)/VERSION.txt
TARGET_CONFIG=$(FW_DIR)/configs/common.config $(FW_DIR)/configs/$(TARGET).config
IB_BUILD_DIR=$(FW_DIR)/imgbldr_tmp
FW_TARGET_DIR=$(FW_DIR)/openwrt-base/$(shell $(GIT_BRANCH))/$(MAINTARGET)/$(CUSTOMTARGET)
UMASK=umask 022

# test for existing $TARGET-config or abort
ifeq ($(wildcard $(FW_DIR)/configs/$(TARGET).config),)
$(error config for $(TARGET) not defined)
endif

# if any of the following files have been changed: clean up openwrt dir
DEPS=$(TARGET_CONFIG) modules patches $(wildcard patches/*)


default: firmwares

## Gluon - Begin
# compatibility to Gluon.buildsystem
# * setup required makros and variables
# * create the modules-file from config.mk and feeds.conf

# check for spaces & resolve possibly relative paths
define mkabspath
   ifneq (1,$(words [$($(1))]))
     $$(error $(1) must not contain spaces)
   endif
   override $(1) := $(abspath $($(1)))
endef

# initialize (possibly already user set) directory variables
GLUON_TMPDIR ?= tmp
GLUON_PATCHESDIR ?= patches

$(eval $(call mkabspath,GLUON_TMPDIR))
$(eval $(call mkabspath,GLUON_PATCHESDIR))

export GLUON_TMPDIR GLUON_PATCHESDIR
## Gluon - End

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
	rm -rf $(OPENWRT_DIR)/build_dir/target-*/*-{imagebuilder,sdk}-*

# update feeds
feeds-update: stamp-clean-feeds-updated .stamp-feeds-updated
.stamp-feeds-updated: .stamp-patched
	@$(UMASK); GLUON_SITEDIR='$(GLUON_SITEDIR)' FOREIGN_BUILD=1 scripts/feeds.sh
	touch $@

# prepare patch
pre-patch: stamp-clean-pre-patch .stamp-pre-patch
.stamp-pre-patch: $(FW_DIR)/modules
	@GLUON_SITEDIR='$(GLUON_SITEDIR)' scripts/update.sh
	touch $@

# patch openwrt and feeds working copy
patch: stamp-clean-patched .stamp-patched
.stamp-patched: .stamp-pre-patch $(wildcard $(GLUON_PATCHESDIR)/openwrt/*) $(wildcard $(GLUON_PATCHESDIR)/packages/*/*)
	@$(UMASK); GLUON_SITEDIR='$(GLUON_SITEDIR)' scripts/patch.sh
	touch $@

.stamp-build_rev: .FORCE
	$(eval FW_REVISION := $(FW_REVISION)+openwrt-$(shell cd $(OPENWRT_DIR); ./scripts/getver.sh))
	echo ${FW_REVISION}
	touch $@

# share download dir
$(FW_DIR)/dl:
	mkdir $(FW_DIR)/dl
$(OPENWRT_DIR)/dl: $(FW_DIR)/dl
	ln -s $(FW_DIR)/dl $(OPENWRT_DIR)/dl

# create embedded-files/ and make it avail to openwrt
$(FW_DIR)/embedded-files:
	mkdir $@
$(OPENWRT_DIR)/files: $(FW_DIR)/embedded-files
	ln -s $(FW_DIR)/embedded-files $(OPENWRT_DIR)/files

# openwrt config
$(OPENWRT_DIR)/.config: .stamp-feeds-updated $(TARGET_CONFIG) .stamp-build_rev $(OPENWRT_DIR)/dl
	echo ${FW_REVISION}
	cat $(TARGET_CONFIG) >$(OPENWRT_DIR)/.config && \
	sed -i "/^CONFIG_VERSION_CODE=/c\CONFIG_VERSION_CODE=\"$(FW_REVISION)\"" $(OPENWRT_DIR)/.config
	sed -i "/^CONFIG_VERSION_REPO=/c\CONFIG_VERSION_REPO=\"http://buildbot.weimarnetz.de/builds/openwrt-base/$(FW_BRANCH)/%S/packages\"" $(OPENWRT_DIR)/.config
	$(UMASK); \
	  $(MAKE) -C $(OPENWRT_DIR) defconfig clean

# prepare openwrt working copy
prepare: stamp-clean-prepared .stamp-prepared
.stamp-prepared: .stamp-feeds-updated $(OPENWRT_DIR)/.config $(OPENWRT_DIR)/files
	touch $@

# compile
compile: stamp-clean-compiled .stamp-compiled
.stamp-compiled: .stamp-prepared openwrt-clean-bin
	$(UMASK); \
	  $(MAKE) -C $(OPENWRT_DIR) $(MAKE_ARGS)
	touch $@

# fill firmwares-directory with:
#  * imagebuilder file
#  * packages directory
#  * firmware-images are already in place (target images)
firmwares: stamp-clean-firmwares .stamp-firmwares
.stamp-firmwares: .stamp-compiled $(VERSION_FILE)
	# copy imagebuilder, sdk and toolchain (if existing)
	# remove old versions
	rm -f $(FW_TARGET_DIR)/*.tar.xz
	# remove gcc version from filename
	for file in `find ./ -name "*sdk*.tar.xz"`; do newname=`echo "$$file" | sed -e 's/\(.*\)_gcc.*_musl\(.*\)/\1\2/'`; mv $$file $$newname; done
	for file in $(OPENWRT_DIR)/bin/targets/$(MAINTARGET)/$(SUBTARGET)/*{imagebuilder,sdk,toolchain}*.tar.xz; do \
		if [ -e $$file ]; then mv $$file $(FW_TARGET_DIR)/ ; fi \
	done
	# copy packages
	PACKAGES_DIR="$(FW_TARGET_DIR)/packages"; \
	cd $(OPENWRT_DIR)/bin; \
	rm -rf $$PACKAGES_DIR; \
	mkdir -p $$PACKAGES_DIR/targets/$(MAINTARGET)/$(CUSTOMTARGET)/packages; \
	cp -a $(OPENWRT_DIR)/bin/targets/$(MAINTARGET)/$(SUBTARGET)/packages/* $$PACKAGES_DIR/targets/$(MAINTARGET)/$(CUSTOMTARGET)/packages; \
	# e.g. packages/packages/mips_34k the doublicated packages is correct! \
	cp -a $(OPENWRT_DIR)/bin/packages $$PACKAGES_DIR/
	touch $@

$(VERSION_FILE): .stamp-prepared
	mkdir -p $(FW_TARGET_DIR)
	# Create version info file
	GIT_BRANCH_ESC=$(shell $(GIT_BRANCH) | tr '/' '_'); \
	echo "https://github.com/weimarnetz/firmware" > $(VERSION_FILE); \
	echo "http://buildbot.weimarnetz.de/builds" >> $(VERSION_FILE); \
	echo "Firmware: git branch \"$$GIT_BRANCH_ESC\", revision $(FW_REVISION)" >> $(VERSION_FILE); \
	# add openwrt revision with data from config.mk \
	OPENWRT_REVISION=`cd $(OPENWRT_DIR); $(REVISION)`; \
	echo "OpenWRT: repository from $(OPENWRT_SRC), git branch \"$(OPENWRT_COMMIT)\", revision $$OPENWRT_REVISION" >> $(VERSION_FILE); \
	# add feed revisions \
	for FEED in `cd $(OPENWRT_DIR); ./scripts/feeds list -n`; do \
	  FEED_DIR=$(addprefix $(OPENWRT_DIR)/feeds/,$$FEED); \
	  FEED_GIT_REPO=`cd $$FEED_DIR; $(GIT_REPO)`; \
	  FEED_GIT_BRANCH_ESC=`cd $$FEED_DIR; $(GIT_BRANCH) | tr '/' '_'`; \
	  FEED_REVISION=`cd $$FEED_DIR; $(REVISION)`; \
	  echo "Feed $$FEED: repository from $$FEED_GIT_REPO, git branch \"$$FEED_GIT_BRANCH_ESC\", revision $$FEED_REVISION" >> $(VERSION_FILE); \
	done

stamp-clean-firmwares:
	rm -f $(OPENWRT_DIR)/.config
	rm -f .stamp-$*

stamp-clean-%:
	rm -f .stamp-$*

stamp-clean:
	rm -f .stamp-*
	rm -rf $(GLUON_TMPDIR)

clean: stamp-clean .stamp-openwrt-cleaned

.PHONY: openwrt-clean openwrt-clean-bin patch feeds-update prepare compile firmwares stamp-clean clean
.NOTPARALLEL:
.FORCE:
