TOOLS = /Users/chenrenwei/developer/MusicPlayer/thirdpart/MusicFreeVLCKit/.noindex/vlc-source-ios15/extras/tools
MAKEFLAGS += -j14
CMAKEFLAGS += --parallel=14
PREFIX=$(abspath ./build)
PATH=${PREFIX}/bin:/Users/chenrenwei/developer/MusicPlayer/thirdpart/MusicFreeVLCKit/.noindex/vlc-host-tools/bin:/Users/chenrenwei/developer/MusicPlayer/thirdpart/MusicFreeVLCKit/.noindex/vlc-source-ios15/extras/tools/build/bin:/opt/homebrew/opt/m4/bin:/opt/homebrew/opt/gettext/bin:/opt/homebrew/bin:/usr/bin:/bin:/usr/sbin:/sbin

.zstd .gperf .ninja .meson .help2man .gettext .nasm .flex .bison .xz .ant .sed .tar .cmake .pkg-config .libtool .m4 .automake .autoconf :
	@echo "Available in the system"
	touch $@

.SECONDEXPANSION:
.configguess : $$(subst .,.build,$$@)
	touch $@

all:  .buildconfigguess
	@echo "You are ready to build VLC and its contribs"

include $(TOOLS)/tools.mak

fetch: .getconfigguess
