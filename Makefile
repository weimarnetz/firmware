include config.mk

# get main- and subtarget name from TARGET
MAINTARGET=$(word 1, $(subst _, ,$(TARGET)))
SUBTARGET=$(word 2, $(subst _, ,$(TARGET)))

ifeq ($(strip $(SUBTARGET)),)
	SUBTARGET:=generic
endif

GIT_REPO=git config --get remote.origin.url
GIT_BRANCH=git symbolic-ref HEAD | sed -e 's,.*/\(.*\),\1,'
REVISION=git describe --always
# set dir and file names
FW_DIR=$(shell pwd)
FW_REVISION=$(shell $(REVISION))
LEDE_DIR=$(FW_DIR)/lede
TARGET_CONFIG=$(FW_DIR)/configs/common.config $(FW_DIR)/configs/$(TARGET).config
IB_BUILD_DIR=$(FW_DIR)/imgbldr_tmp
FW_TARGET_DIR=$(FW_DIR)/firmwares/$(FW_REVISION)/$(TARGET)
UMASK=umask 022

# if any of the following files have been changed: clean up lede dir
DEPS=$(TARGET_CONFIG) feeds.conf patches $(wildcard patches/*)

# profiles to be built (router models)
PROFILES?=$(shell cat $(FW_DIR)/profiles/$(TARGET).profiles)


default: firmwares

# clone lede 
$(LEDE_DIR):
	git clone $(LEDE_SRC) $(LEDE_DIR)

# clean up lede working copy
lede-clean: stamp-clean-lede-cleaned .stamp-lede-cleaned
.stamp-lede-cleaned: config.mk | $(LEDE_DIR) lede-clean-bin
	cd $(LEDE_DIR); \
	  ./scripts/feeds clean && \
	  git clean -dff && git fetch && git reset --hard HEAD && \
	  rm -rf .config feeds.conf build_dir/target-* logs/
	touch $@

lede-clean-bin:
	rm -rf $(LEDE_DIR)/bin

# update lede and checkout specified commit
lede-update: stamp-clean-lede-updated .stamp-lede-updated
.stamp-lede-updated: .stamp-lede-cleaned | $(LEDE_DIR)/dl
	cd $(LEDE_DIR); \
		git checkout master && \
		git pull && \
		git checkout --detach $(LEDE_COMMIT)
	touch $@

# patches require updated lede working copy
$(LEDE_DIR)/patches: | .stamp-lede-updated
	ln -s $(FW_DIR)/patches $@

# symlink download folder 
$(LEDE_DIR)/dl:
	mkdir $(FW_DIR)/dl || true && \
	ln -s $(FW_DIR)/dl $@

# feeds
$(LEDE_DIR)/feeds.conf: .stamp-lede-updated feeds.conf
	cp $(FW_DIR)/feeds.conf $@

# update feeds
feeds-update: stamp-clean-feeds-updated .stamp-feeds-updated
.stamp-feeds-updated: $(LEDE_DIR)/feeds.conf unpatch
	+cd $(LEDE_DIR); \
	  ./scripts/feeds uninstall -a && \
	  ./scripts/feeds update && \
	  ./scripts/feeds install -a
	touch $@

# prepare patch
pre-patch: stamp-clean-pre-patch .stamp-pre-patch
.stamp-pre-patch: .stamp-feeds-updated $(wildcard $(FW_DIR)/patches/*) | $(LEDE_DIR)/patches
	touch $@

# patch lede working copy
patch: stamp-clean-patched .stamp-patched
.stamp-patched: .stamp-pre-patch
	cd $(LEDE_DIR); quilt push -a || ( [ $$? -eq 2 ] && true )
	touch $@

.stamp-build_rev: .FORCE
	$(eval FW_REVISION := $(FW_REVISION)+lede-$(shell cd $(LEDE_DIR); ./scripts/getver.sh))
	touch $@

# lede config
$(LEDE_DIR)/.config: .stamp-patched $(TARGET_CONFIG) .stamp-build_rev
	cat $(TARGET_CONFIG) >$(LEDE_DIR)/.config
	sed -i '/^CONFIG_VERSION_NUMBER=/d' $(LEDE_DIR)/.config 
	echo CONFIG_VERSION_NUMBER=$$(FW_REVISION) >> $(LEDE_DIR)/.config
	$(UMASK); \
	  $(MAKE) -C $(LEDE_DIR) defconfig

# prepare lede working copy
prepare: stamp-clean-prepared .stamp-prepared
.stamp-prepared: .stamp-patched $(LEDE_DIR)/.config
	# delete tmpinfo to make patches work
	rm -rf $(LEDE_DIR)/tmp
	sed -i 's,^# REVISION:=.*,REVISION:=$(FW_REVISION),g' $(LEDE_DIR)/include/version.mk
	touch $@

# compile
compile: stamp-clean-compiled .stamp-compiled
.stamp-compiled: .stamp-prepared lede-clean-bin
	$(UMASK); \
	  $(MAKE) -C $(LEDE_DIR) $(MAKE_ARGS)
	touch $@

# fill firmwares-directory with:
#  * firmwares built with imagebuilder
#  * imagebuilder file
#  * packages directory
firmwares: stamp-clean-firmwares .stamp-firmwares
.stamp-firmwares: .stamp-compiled
	rm -rf $(IB_BUILD_DIR)
	mkdir -p $(IB_BUILD_DIR)
	$(eval TOOLCHAIN_PATH := $(shell printf "%s:" $(LEDE_DIR)/staging_dir/toolchain-*/bin))
	$(eval IB_FILE := $(shell ls $(LEDE_DIR)/bin/targets/$(MAINTARGET)/$(SUBTARGET)/*-imagebuilder-*.tar.xz))
	cd $(IB_BUILD_DIR); tar xf $(IB_FILE)
	# shorten dir name to prevent too long paths
	mv $(IB_BUILD_DIR)/$(shell basename $(IB_FILE) .tar.xz) $(IB_BUILD_DIR)/imgbldr
	export PATH=$(PATH):$(TOOLCHAIN_PATH); \
	PACKAGES_PATH="$(FW_DIR)/packages"; \
	for PROFILE_ITER in $(PROFILES); do \
	  for PACKAGES_FILE in $(PACKAGES_LIST_DEFAULT); do \
	    PROFILE=$$PROFILE_ITER \
	    CUSTOM_POSTINST_PARAM=""; \
	    if [[ $$PROFILE =~ ":" ]]; then \
	      SUFFIX="$$(echo $$PROFILE | cut -d':' -f 2)"; \
	      PACKAGES_SUFFIXED="$${PACKAGES_FILE}_$${SUFFIX}"; \
	      if [[ -f "$$PACKAGES_PATH/$$PACKAGES_SUFFIXED.txt" ]]; then \
	        PACKAGES_FILE="$$PACKAGES_SUFFIXED"; \
	        PROFILE=$$(echo $$PROFILE | cut -d':' -f 1); \
	      fi; \
	    fi; \
	    if [[ -f "$$PACKAGES_PATH/$$PACKAGES_FILE.sh" ]]; then \
	      CUSTOM_POSTINST_PARAM="CUSTOM_POSTINST_SCRIPT=$$PACKAGES_PATH/$$PACKAGES_FILE.sh"; \
	    fi; \
	    PACKAGES_FILE_ABS="$$PACKAGES_PATH/$$PACKAGES_FILE.txt"; \
	    PACKAGES_LIST=$$(grep -v '^\#' $$PACKAGES_FILE_ABS | tr -t '\n' ' '); \
	    $(UMASK);\
	    echo -e "\n *** Building image file for profile \"$${PROFILE}\" with packages list \"$${PACKAGES_FILE}\".\n"; \
	    $(MAKE) -C $(IB_BUILD_DIR)/imgbldr image PROFILE="$$PROFILE" PACKAGES="$$PACKAGES_LIST" BIN_DIR="$(IB_BUILD_DIR)/imgbldr/bin/$$PACKAGES_FILE" $$CUSTOM_POSTINST_PARAM || exit 1; \
	  done; \
	done
	mkdir -p $(FW_TARGET_DIR)
	# Create version info file
	#GIT_BRANCH_ESC=$(shell $(GIT_BRANCH) | tr '/' '_'); 
	#VERSION_FILE=$(FW_TARGET_DIR)/VERSION.txt; \
	#echo "Firmware: git branch \"$$GIT_BRANCH_ESC\", revision $(FW_REVISION)" >> $$VERSION_FILE 
	# add lede revision with data from config.mk 
	#LEDE_REVISION=`cd $(LEDE_DIR); $(REVISION)`; 
	# echo "LEDE: repository from $(LEDE_SRC), git branch \"$(LEDE_COMMIT)\", revision $$LEDE_REVISION" >> $$VERSION_FILE; \ 
	# add feed revisions 
	#for FEED in `cd $(LEDE_DIR); ./scripts/feeds list -n`; do \
	#  FEED_DIR=$(addprefix $(LEDE_DIR)/feeds/,$$FEED); \
	#  FEED_GIT_REPO=`cd $$FEED_DIR; $(GIT_REPO)`; \
	#  FEED_GIT_BRANCH_ESC=`cd $$FEED_DIR; $(GIT_BRANCH) | tr '/' '_'`; \
	#  FEED_REVISION=`cd $$FEED_DIR; $(REVISION)`; \
	#  echo "Feed $$FEED: repository from $$FEED_GIT_REPO, git branch \"$$FEED_GIT_BRANCH_ESC\", revision $$FEED_REVISION" >> $$VERSION_FILE; \
	# done
	# copy different firmwares (like vpn, minimal) including imagebuilder
	for DIR_ABS in $(IB_BUILD_DIR)/imgbldr/bin/*; do \
	  TARGET_DIR=$(FW_TARGET_DIR)/$$(basename $$DIR_ABS); \
	  rm -rf $$TARGET_DIR; \
	  mv $$DIR_ABS $$TARGET_DIR; \
	done
	# copy imagebuilder, sdk and toolchain (if existing)
	cp $$(find $(LEDE_DIR)/bin/targets/$(MAINTARGET) -type f -name "*imagebuilder-*.tar.xz") $(FW_TARGET_DIR)/
	# copy packages
	PACKAGES_DIR="$(FW_TARGET_DIR)/packages"; \
	cd $(LEDE_DIR)/bin; \
		rsync -avR $$(find targets -name packages -type d) $$PACKAGES_DIR; \
		rsync -avr packages $$PACKAGES_DIR
	touch $@

stamp-clean-%:
	rm -f .stamp-$*

stamp-clean:
	rm -f .stamp-*

# unpatch needs "patches/" in lede
unpatch: $(LEDE_DIR)/patches
# RC = 2 of quilt --> nothing to be done
	cd $(LEDE_DIR); quilt pop -a -f || [ $$? = 2 ] && true
	rm -f .stamp-patched

clean: stamp-clean .stamp-lede-cleaned

.PHONY: lede-clean lede-clean-bin lede-update lede-symlink-dl patch feeds-update prepare compile firmwares stamp-clean clean
.NOTPARALLEL:
.FORCE:
