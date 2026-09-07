################################################################################
#
# es-theme-relicos
#
################################################################################
# The RelicOS theme (github.com/RelicOS/es-theme): dark, drawn at the R36S's
# native 640x480, IBM Plex, one accent. The only theme on the rootfs since
# M16, and named as the default by the seeded es_settings.cfg (overlay,
# usr/share/relicos/data/system/.emulationstation): the ES's loading
# screen is built before any theme is resolved and takes the theme's
# splash.xml only when ThemeSet already says so -- observed as the
# Batocera splash on build 1. carbon (the batocera default) served
# M10-M15; it was ~184 MiB of target, this is ~2.
# Installed as themes/relicos: the folder name is the theme-set name the
# ES shows in UI SETTINGS, and the name the theme's own README asks for.
#
# The repository does not carry the fonts (art/fonts/ is gitignored, its
# tools/fetch-fonts.sh pulls them): the six IBM Plex faces are taken from
# the same release archive that script uses, plus the OFL text next to
# them. docs/ and tools/ are host-side and stay out of the image.

ES_THEME_RELICOS_VERSION = c08ca62bc1f73dfbf17019686f6122097ed5c685
ES_THEME_RELICOS_SITE = $(call github,RelicOS,es-theme,$(ES_THEME_RELICOS_VERSION))
ES_THEME_RELICOS_LICENSE = MIT (theme), OFL-1.1 (IBM Plex), console logos by Dan Patrick used with permission (art/logos/README.md)
ES_THEME_RELICOS_LICENSE_FILES = LICENSE art/fonts/OFL.txt

# IBM Plex v6.4.0, the archive tools/fetch-fonts.sh downloads (~100 MB for
# six ~200 KB faces; cached in dl/ like everything else).
ES_THEME_RELICOS_PLEX_ZIP = TrueType.zip
ES_THEME_RELICOS_EXTRA_DOWNLOADS = \
	https://github.com/IBM/plex/releases/download/v6.4.0/$(ES_THEME_RELICOS_PLEX_ZIP)
ES_THEME_RELICOS_FONTS = \
	IBMPlexSans-Regular IBMPlexSans-Medium IBMPlexSans-SemiBold IBMPlexSans-Bold \
	IBMPlexMono-Regular IBMPlexMono-Medium

define ES_THEME_RELICOS_EXTRACT_FONTS
	mkdir -p $(@D)/art/fonts
	$(UNZIP) -o -j $(ES_THEME_RELICOS_DL_DIR)/$(ES_THEME_RELICOS_PLEX_ZIP) \
		$(foreach f,$(ES_THEME_RELICOS_FONTS),'*/$(f).ttf') \
		TrueType/IBM-Plex-Sans/license.txt -d $(@D)/art/fonts
	mv $(@D)/art/fonts/license.txt $(@D)/art/fonts/OFL.txt
	chmod 644 $(@D)/art/fonts/*
endef
ES_THEME_RELICOS_POST_EXTRACT_HOOKS += ES_THEME_RELICOS_EXTRACT_FONTS

define ES_THEME_RELICOS_INSTALL_TARGET_CMDS
	rm -rf $(TARGET_DIR)/usr/share/emulationstation/themes/relicos
	mkdir -p $(TARGET_DIR)/usr/share/emulationstation/themes/relicos
	cp -r $(@D)/theme.xml $(@D)/splash.xml $(@D)/gamesplash.xml \
		$(@D)/views $(@D)/art $(@D)/LICENSE \
		$(TARGET_DIR)/usr/share/emulationstation/themes/relicos/
endef

$(eval $(generic-package))
