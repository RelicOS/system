################################################################################
#
# fatresize
#
################################################################################
# Our own package (M19): Buildroot 2026.02 ships no FAT resizer. The tool
# is a thin front end over libparted + libparted-fs-resize (which parted
# already builds), so the dependency is the parted package and nothing
# else. v1.1.0 is the last tag upstream; the binary calls itself 1.0.3 in
# its banner -- known, harmless. The tarball ships a generated configure,
# so no autoreconf (and no host-autotools build). man_MANS is emptied on
# the make command line: the Makefile has a docbook-to-man rule for the
# man page and there is no docbook here; the page is shipped pre-built,
# but a stray mtime would have make try to regenerate it.

FATRESIZE_VERSION = 1.1.0
FATRESIZE_SITE = $(call github,ya-mouse,fatresize,v$(FATRESIZE_VERSION))
FATRESIZE_LICENSE = GPL-3.0+
FATRESIZE_LICENSE_FILES = COPYING
FATRESIZE_DEPENDENCIES = host-pkgconf parted
FATRESIZE_MAKE_OPTS = man_MANS=
FATRESIZE_INSTALL_TARGET_OPTS = man_MANS= DESTDIR=$(TARGET_DIR) install

$(eval $(autotools-package))
