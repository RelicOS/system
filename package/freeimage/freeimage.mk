################################################################################
#
# freeimage
#
################################################################################
# Transplanted (recipe, hash and the 4 patches) from batocera.linux master,
# package/batocera/libraries/libfreeimage/, on 2026-08-31. Buildroot upstream
# has no freeimage package, and the EmulationStation's CMake requires it
# (find_package(FreeImage REQUIRED)); this is the only dependency hole the
# M10 recipe had to fill itself.
#
# Renamed from batocera's "libfreeimage": Buildroot once shipped a package by
# that exact name and removed it as unmaintained, leaving a tombstone in
# Config.in.legacy that `select`s BR2_LEGACY -- reusing the name makes every
# build stop at "You have legacy configuration in your .config!". The symbol
# BR2_PACKAGE_FREEIMAGE has no tombstone.

FREEIMAGE_VERSION = 3.18.0
FREEIMAGE_SITE = http://downloads.sourceforge.net/freeimage
FREEIMAGE_SOURCE = FreeImage$(subst .,,$(FREEIMAGE_VERSION)).zip
FREEIMAGE_LICENSE = GPL-2.0 or GPL-3.0 or FreeImage Public License
FREEIMAGE_LICENSE_FILES = license-gplv2.txt license-gplv3.txt license-fi.txt
FREEIMAGE_CPE_ID_VENDOR = freeimage_project
FREEIMAGE_CPE_ID_PRODUCT = freeimage
FREEIMAGE_INSTALL_STAGING = YES

define FREEIMAGE_EXTRACT_CMDS
	$(UNZIP) $(FREEIMAGE_DL_DIR)/$(FREEIMAGE_SOURCE) -d $(@D)
	mv $(@D)/FreeImage/* $(@D)
	rmdir $(@D)/FreeImage
endef

FREEIMAGE_CFLAGS = $(TARGET_CFLAGS) -Wno-implicit-function-declaration
FREEIMAGE_CXXFLAGS = $(TARGET_CXXFLAGS) -Wno-implicit-function-declaration

ifneq ($(filter y,$(BR2_ARM_CPU_HAS_NEON) $(BR2_ARM_FPU_FP_ARMV8) $(BR2_ARM_CPU_ARMV8A)),)
FREEIMAGE_CFLAGS += -DPNG_ARM_NEON_OPT=0
endif

ifeq ($(HOSTARCH),aarch64)
FREEIMAGE_CFLAGS += -fPIC
FREEIMAGE_CXXFLAGS += -fPIC
endif

define FREEIMAGE_BUILD_CMDS
	$(TARGET_MAKE_ENV) $(TARGET_CONFIGURE_OPTS) \
		CFLAGS="$(FREEIMAGE_CFLAGS)" \
		CXXFLAGS="$(FREEIMAGE_CXXFLAGS) -std=c++11" \
		$(MAKE) -C $(@D)
endef

define FREEIMAGE_INSTALL_STAGING_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) DESTDIR=$(STAGING_DIR) install
endef

define FREEIMAGE_INSTALL_TARGET_CMDS
	$(TARGET_MAKE_ENV) $(MAKE) -C $(@D) DESTDIR=$(TARGET_DIR) install
endef

$(eval $(generic-package))
