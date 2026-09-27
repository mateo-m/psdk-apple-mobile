# Builds the PSDK core for one SDK: one static library for each Ruby,
# and the Ruby support folder of each Ruby.
#
#   make SDK=iphonesimulator        # or SDK=iphoneos
#   make SDK=iphoneos RUBIES=30     # only the Ruby 3.0 library
#
# The results go to out/$(SDK)/libpsdk<NN>.a and out/support/<version>.
# README.md says how a host links them.

SDK ?= iphonesimulator
ARCH := arm64
HOST := aarch64-apple-darwin
MINIMUM_REQUIRED := 26.0
RUBIES ?= 25 30 32 33

ifeq ($(SDK),iphonesimulator)
TARGET_FLAG := -mios-simulator-version-min=$(MINIMUM_REQUIRED) -target $(ARCH)-apple-ios$(MINIMUM_REQUIRED)-simulator
LD_PLATFORM := ios-simulator
else ifeq ($(SDK),iphoneos)
TARGET_FLAG := -miphoneos-version-min=$(MINIMUM_REQUIRED) -target $(ARCH)-apple-ios$(MINIMUM_REQUIRED)
LD_PLATFORM := ios
else
$(error SDK must be iphoneos or iphonesimulator)
endif

ROOT := $(CURDIR)
SYSROOT := $(shell xcrun --sdk $(SDK) --show-sdk-path)
SDK_VERSION := $(shell xcrun --sdk $(SDK) --show-sdk-version)
TARGETFLAGS := -isysroot $(SYSROOT) $(TARGET_FLAG) -arch $(ARCH)
LD_PLATFORM_VERSION := -platform_version $(LD_PLATFORM) $(MINIMUM_REQUIRED) $(SDK_VERSION)
BUILD_PREFIX := $(ROOT)/build/$(SDK)
LIBDIR := $(BUILD_PREFIX)/lib
INCLUDEDIR := $(BUILD_PREFIX)/include
OUT := $(ROOT)/out
SDK_TAG := $(SDK)-$(ARCH)
# Every source tree is shared by both SDKs, and a configure step cleans
# the tree. So it deletes the stamps of every SDK, and the next build for
# the other SDK configures again instead of using these objects.
#
# Keep the `=` assignment: `$@` must expand when the recipe runs.
MARK_SDK_CONFIGURED = rm -f $(dir $@).configured-* && touch $@
CMAKE_BUILDDIR := cmakebuild-$(SDK_TAG)
DOWNLOADS := $(ROOT)/downloads
SOURCES := $(ROOT)/sources
NPROC := $(shell sysctl -n hw.ncpu)
CFLAGS := -I$(INCLUDEDIR) -I$(INCLUDEDIR)/freetype2 $(TARGETFLAGS) -O3
CXXFLAGS := $(CFLAGS)
LDFLAGS := -L$(LIBDIR) $(TARGETFLAGS)
CC  := $(shell xcrun --sdk $(SDK) -f clang) -arch $(ARCH)
CXX := $(shell xcrun --sdk $(SDK) -f clang++) -arch $(ARCH)
AR  := $(shell xcrun --sdk $(SDK) -f ar)
RANLIB := $(shell xcrun --sdk $(SDK) -f ranlib)
PKG_CONFIG_LIBDIR := $(LIBDIR)/pkgconfig
CLONE := git clone -q
GITHUB := https://github.com

# The host build triple. Apple's system Ruby reports a triple that
# configure does not know.
RBUILD := aarch64-apple-darwin

CPPFLAGS := -isysroot $(SYSROOT) $(CFLAGS)

CONFIGURE_ENV := \
	PKG_CONFIG_LIBDIR=$(PKG_CONFIG_LIBDIR) \
	CC="$(CC)" CXX="$(CXX)" AR="$(AR)" RANLIB="$(RANLIB)" \
	CFLAGS="$(CFLAGS)" CXXFLAGS="$(CXXFLAGS)" CPPFLAGS="$(CPPFLAGS)" LDFLAGS="$(LDFLAGS)"

CONFIGURE_ARGS := --prefix="$(BUILD_PREFIX)" --host=$(HOST)

CMAKE_ARGS := \
	-DCMAKE_INSTALL_PREFIX="$(BUILD_PREFIX)" \
	-DCMAKE_PREFIX_PATH="$(BUILD_PREFIX)" \
	-DCMAKE_OSX_ARCHITECTURES=$(ARCH) \
	-DCMAKE_OSX_SYSROOT=$(SYSROOT) \
	-DCMAKE_C_FLAGS="$(CFLAGS)" \
	-DCMAKE_CXX_FLAGS="$(CXXFLAGS)" \
	-DCMAKE_BUILD_TYPE=Release \
	-DCMAKE_SYSTEM_NAME=iOS \
	-DCMAKE_OSX_DEPLOYMENT_TARGET=$(MINIMUM_REQUIRED) \
	-DCMAKE_POLICY_VERSION_MINIMUM=3.5 \
	-DCMAKE_FIND_ROOT_PATH="$(BUILD_PREFIX)" \
	-DCMAKE_FIND_ROOT_PATH_MODE_LIBRARY=BOTH \
	-DCMAKE_FIND_ROOT_PATH_MODE_INCLUDE=BOTH \
	-DCMAKE_FIND_ROOT_PATH_MODE_PACKAGE=BOTH

CONFIGURE := $(CONFIGURE_ENV) ./configure $(CONFIGURE_ARGS)
CMAKE     := $(CONFIGURE_ENV) cmake .. $(CMAKE_ARGS)

.PHONY: all init_dirs angle libogg libvorbis libflac libpng openal openssl freetype sfml litecgss

all:
	@for ruby in $(RUBIES); do \
		$(MAKE) PSDK_RUBY=$$ruby psdk-ruby || exit 1; \
	done

init_dirs:
	@mkdir -p $(LIBDIR) $(INCLUDEDIR)

# ANGLE (prebuilt). SFML draws with GLES through ANGLE, which draws with
# Metal. The core needs the headers only. A host links the static
# libraries of the same release.
ANGLE_VERSION := angle-2026-05-04
ANGLE_SHA256 := 0cd2b87b132b2c1344fe356ebcb57fa6ec63675d33d6fa11deb8a16bd57d3b9c
ANGLE_DIR := $(DOWNLOADS)/angle
ANGLE_STAMP := $(ANGLE_DIR)/.$(ANGLE_VERSION)

angle: $(ANGLE_STAMP)

$(ANGLE_STAMP):
	@mkdir -p $(DOWNLOADS)
	curl -fL --retry 3 -o $(DOWNLOADS)/angle-ios-prebuilt.tar.gz \
		$(GITHUB)/mateo-m/empo-deps/releases/download/$(ANGLE_VERSION)/angle-ios-prebuilt.tar.gz
	echo "$(ANGLE_SHA256)  $(DOWNLOADS)/angle-ios-prebuilt.tar.gz" | shasum -a 256 -c
	rm -rf $(ANGLE_DIR)
	mkdir -p $(ANGLE_DIR)
	tar -xzf $(DOWNLOADS)/angle-ios-prebuilt.tar.gz -C $(ANGLE_DIR)
	rm $(DOWNLOADS)/angle-ios-prebuilt.tar.gz
	touch $@

# Ogg
libogg: init_dirs $(LIBDIR)/libogg.a

$(LIBDIR)/libogg.a: $(DOWNLOADS)/ogg/.configured-$(SDK_TAG)
	cd $(DOWNLOADS)/ogg; make -j$(NPROC); make install

$(DOWNLOADS)/ogg/.configured-$(SDK_TAG): $(DOWNLOADS)/ogg/configure
	cd $(DOWNLOADS)/ogg; $(MAKE) distclean 2>/dev/null || true
	cd $(DOWNLOADS)/ogg; $(CONFIGURE) --enable-static=true --enable-shared=false
	$(MARK_SDK_CONFIGURED)

$(DOWNLOADS)/ogg/configure: $(DOWNLOADS)/ogg/autogen.sh
	cd $(DOWNLOADS)/ogg; ./autogen.sh

$(DOWNLOADS)/ogg/autogen.sh:
	$(CLONE) $(GITHUB)/xiph/ogg -b v1.3.6 $(DOWNLOADS)/ogg

# Vorbis
libvorbis: init_dirs libogg $(LIBDIR)/libvorbis.a

$(LIBDIR)/libvorbis.a: $(LIBDIR)/libogg.a $(DOWNLOADS)/vorbis/$(CMAKE_BUILDDIR)/Makefile
	cd $(DOWNLOADS)/vorbis/$(CMAKE_BUILDDIR); make -j$(NPROC); make install

$(DOWNLOADS)/vorbis/$(CMAKE_BUILDDIR)/Makefile: $(DOWNLOADS)/vorbis/CMakeLists.txt
	cd $(DOWNLOADS)/vorbis; mkdir -p $(CMAKE_BUILDDIR); cd $(CMAKE_BUILDDIR); \
	$(CMAKE) -DBUILD_SHARED_LIBS=no

$(DOWNLOADS)/vorbis/CMakeLists.txt:
	$(CLONE) $(GITHUB)/xiph/vorbis -b v1.3.7 $(DOWNLOADS)/vorbis

# FLAC. SFML's FindFLAC.cmake looks for `libFLAC.a` with a capital F,
# which is the name xiph/flac installs. SFML needs only the C decoder.
libflac: init_dirs libogg $(LIBDIR)/libFLAC.a

$(LIBDIR)/libFLAC.a: $(LIBDIR)/libogg.a $(DOWNLOADS)/flac/$(CMAKE_BUILDDIR)/Makefile
	cd $(DOWNLOADS)/flac/$(CMAKE_BUILDDIR); make -j$(NPROC); make install

$(DOWNLOADS)/flac/$(CMAKE_BUILDDIR)/Makefile: $(DOWNLOADS)/flac/CMakeLists.txt
	cd $(DOWNLOADS)/flac; mkdir -p $(CMAKE_BUILDDIR); cd $(CMAKE_BUILDDIR); \
	$(CMAKE) \
	-DBUILD_SHARED_LIBS=OFF \
	-DBUILD_CXXLIBS=OFF \
	-DBUILD_PROGRAMS=OFF \
	-DBUILD_EXAMPLES=OFF \
	-DBUILD_TESTING=OFF \
	-DBUILD_DOCS=OFF \
	-DINSTALL_MANPAGES=OFF \
	-DWITH_OGG=ON \
	-DWITH_STACK_PROTECTOR=OFF

$(DOWNLOADS)/flac/CMakeLists.txt:
	$(CLONE) $(GITHUB)/xiph/flac -b 1.4.3 $(DOWNLOADS)/flac

# libpng. FreeType finds it and uses it for color bitmap fonts.
libpng: init_dirs $(LIBDIR)/libpng.a

$(LIBDIR)/libpng.a: $(DOWNLOADS)/libpng/.configured-$(SDK_TAG)
	cd $(DOWNLOADS)/libpng; make -j$(NPROC); make install

$(DOWNLOADS)/libpng/.configured-$(SDK_TAG): $(DOWNLOADS)/libpng/configure
	cd $(DOWNLOADS)/libpng; $(MAKE) distclean 2>/dev/null || true
	cd $(DOWNLOADS)/libpng; $(CONFIGURE) --enable-shared=no --enable-static=yes
	$(MARK_SDK_CONFIGURED)

$(DOWNLOADS)/libpng/configure:
	$(CLONE) $(GITHUB)/pnggroup/libpng -b v1.6.50 $(DOWNLOADS)/libpng

# OpenAL Soft (submodule). SFML plays its sound through it. Only the
# CoreAudio backend is on, and the configure fails when it is missing.
openal: init_dirs $(LIBDIR)/libopenal.a

$(LIBDIR)/libopenal.a: $(SOURCES)/openal-soft/$(CMAKE_BUILDDIR)/Makefile
	cd $(SOURCES)/openal-soft/$(CMAKE_BUILDDIR); make -j$(NPROC); make install

$(SOURCES)/openal-soft/$(CMAKE_BUILDDIR)/Makefile: $(SOURCES)/openal-soft/CMakeLists.txt
	cd $(SOURCES)/openal-soft; mkdir -p $(CMAKE_BUILDDIR); cd $(CMAKE_BUILDDIR); \
	$(CMAKE) \
	-DLIBTYPE=STATIC \
	-DALSOFT_UTILS=OFF \
	-DALSOFT_EXAMPLES=OFF \
	-DALSOFT_TESTS=OFF \
	-DALSOFT_INSTALL_EXAMPLES=OFF \
	-DALSOFT_INSTALL_UTILS=OFF \
	-DALSOFT_INSTALL_AMBDEC_PRESETS=OFF \
	-DALSOFT_INSTALL_HRTF_DATA=OFF \
	-DALSOFT_BACKEND_COREAUDIO=ON \
	-DALSOFT_REQUIRE_COREAUDIO=ON \
	-DALSOFT_BACKEND_PIPEWIRE=OFF \
	-DALSOFT_BACKEND_PULSEAUDIO=OFF \
	-DALSOFT_BACKEND_ALSA=OFF \
	-DALSOFT_BACKEND_OSS=OFF \
	-DALSOFT_BACKEND_SOLARIS=OFF \
	-DALSOFT_BACKEND_SNDIO=OFF \
	-DALSOFT_BACKEND_PORTAUDIO=OFF \
	-DALSOFT_BACKEND_JACK=OFF \
	-DALSOFT_BACKEND_OPENSL=OFF \
	-DALSOFT_BACKEND_WAVE=OFF

# OpenSSL. A released PSDK game requires openssl at boot.
OPENSSL_VERSION := 3.5.7
OPENSSL_DIR := $(DOWNLOADS)/openssl-$(OPENSSL_VERSION)
OPENSSL_CONFIGURE_TARGET := ios64-xcrun
OPENSSL_CONFIGURE_FLAGS := -miphoneos-version-min=$(MINIMUM_REQUIRED)
ifeq ($(SDK),iphonesimulator)
OPENSSL_CONFIGURE_TARGET := iossimulator-xcrun
OPENSSL_CONFIGURE_FLAGS := -mios-simulator-version-min=$(MINIMUM_REQUIRED)
endif
OPENSSL_CONFIGURED := $(OPENSSL_DIR)/.configured-$(SDK_TAG)

openssl: init_dirs $(BUILD_PREFIX)/.openssl-installed

$(LIBDIR)/libcrypto.a: $(BUILD_PREFIX)/.openssl-installed

$(BUILD_PREFIX)/.openssl-installed: $(OPENSSL_CONFIGURED)
	cd $(OPENSSL_DIR); $(MAKE) -j$(NPROC); $(MAKE) install_sw
	touch $@

# A pristine tree for each SDK. `make distclean` left simulator objects
# in apps/libapps.a, and the device link then failed.
$(OPENSSL_CONFIGURED): $(DOWNLOADS)/openssl-$(OPENSSL_VERSION).tar.gz
	rm -rf $(OPENSSL_DIR)
	cd $(DOWNLOADS) && tar xzf openssl-$(OPENSSL_VERSION).tar.gz
	cd $(OPENSSL_DIR); \
	./Configure $(OPENSSL_CONFIGURE_TARGET) no-shared no-dso \
		--prefix="$(BUILD_PREFIX)" \
		--libdir=lib \
		--openssldir="$(BUILD_PREFIX)/ssl" \
		$(OPENSSL_CONFIGURE_FLAGS)
	$(MARK_SDK_CONFIGURED)

$(DOWNLOADS)/openssl-$(OPENSSL_VERSION).tar.gz:
	@mkdir -p $(DOWNLOADS)
	curl -fL --retry 3 -o $@ $(GITHUB)/openssl/openssl/releases/download/openssl-$(OPENSSL_VERSION)/openssl-$(OPENSSL_VERSION).tar.gz

# FreeType (submodule)
freetype: init_dirs libpng $(LIBDIR)/libfreetype.a

$(LIBDIR)/libfreetype.a: $(SOURCES)/freetype/.configured-$(SDK_TAG)
	cd $(SOURCES)/freetype; make -j$(NPROC); make install

$(SOURCES)/freetype/.configured-$(SDK_TAG): $(SOURCES)/freetype/builds/unix/configure
	cd $(SOURCES)/freetype; $(MAKE) distclean 2>/dev/null || true
	cd $(SOURCES)/freetype; $(CONFIGURE) --enable-static=true --enable-shared=false
	$(MARK_SDK_CONFIGURED)

$(SOURCES)/freetype/builds/unix/configure: $(SOURCES)/freetype/autogen.sh
	cd $(SOURCES)/freetype; ./autogen.sh

# SFML (submodule, the fork mateo-m/sfml-apple-mobile).
#
# LiteCGSS draws through SFML's graphics classes. The fork replaces
# SFML's iOS EAGL backend with ANGLE over EGL, and makes SFAppDelegate
# lazy so a host app can own the app start-up.
#
# SFML_USE_SYSTEM_DEPS=ON stops SFML from linking its own
# extlibs/libs-ios prebuilts. Those are device-only fat archives and
# fail to link for the simulator.
#
# SFML_USE_SYSTEM_DEPS does not cover OpenAL. SFML's FindOpenAL searches
# the frameworks first, so it picks Apple's OpenAL.framework.
# OPENAL_LIBRARY and OPENAL_INCLUDE_DIR are cache entries, so setting
# them makes find_library and find_path return at once. SFML includes
# <al.h> bare, not <AL/al.h>, so the include directory is the AL folder.
#
# `sfml` runs the build step every time. An edit inside sources/sfml
# would otherwise leave a stale archive in place. cmake decides what to
# compile again, so a run with no change costs about a second.
sfml: init_dirs angle freetype libogg libvorbis libflac openal $(SOURCES)/sfml/$(CMAKE_BUILDDIR)/Makefile
	cd $(SOURCES)/sfml/$(CMAKE_BUILDDIR); make -j$(NPROC); make install

$(SOURCES)/sfml/$(CMAKE_BUILDDIR)/Makefile: $(SOURCES)/sfml/CMakeLists.txt $(LIBDIR)/libopenal.a
	cd $(SOURCES)/sfml; rm -rf $(CMAKE_BUILDDIR); mkdir -p $(CMAKE_BUILDDIR); cd $(CMAKE_BUILDDIR); \
	$(CMAKE) \
	-DBUILD_SHARED_LIBS=OFF \
	-DSFML_BUILD_EXAMPLES=OFF \
	-DSFML_BUILD_DOC=OFF \
	-DSFML_BUILD_TEST_SUITE=OFF \
	-DSFML_BUILD_NETWORK=OFF \
	-DSFML_BUILD_GRAPHICS=ON \
	-DSFML_BUILD_WINDOW=ON \
	-DSFML_BUILD_AUDIO=ON \
	-DSFML_USE_SYSTEM_DEPS=ON \
	-DSFML_BUILD_FRAMEWORKS=OFF \
	-DOPENAL_LIBRARY=$(LIBDIR)/libopenal.a \
	-DOPENAL_INCLUDE_DIR=$(INCLUDEDIR)/AL \
	-DSFML_IOS_ANGLE_DIR=$(ANGLE_DIR)/$(SDK)

# LiteCGSS (submodule). The C++ layer under LiteRGSS2. Its top-level
# CMakeLists also adds a playground and a test program, so only the
# LiteCGSS_engine target gets built. Upstream ships no install() rule.
#
# PhysFS stays off. A released PSDK game reads its assets through
# Yuki::VD volumes in Data/*.dat, not through PhysFS.
#
# Runs its build step every time, for the reason given above `sfml`.
litecgss: init_dirs sfml $(SOURCES)/litecgss/$(CMAKE_BUILDDIR)/Makefile
	cd $(SOURCES)/litecgss/$(CMAKE_BUILDDIR); \
	cmake --build . --target LiteCGSS_engine --parallel $(NPROC); \
	cp lib/libLiteCGSS_engine.a lib/libskalog.a $(LIBDIR)/

$(SOURCES)/litecgss/$(CMAKE_BUILDDIR)/Makefile: $(SOURCES)/litecgss/CMakeLists.txt $(SOURCES)/litecgss/external/skalog/CMakeLists.txt
	cd $(SOURCES)/litecgss; rm -rf $(CMAKE_BUILDDIR); mkdir -p $(CMAKE_BUILDDIR); cd $(CMAKE_BUILDDIR); \
	$(CMAKE) \
	-DBUILD_SHARED_LIBS=OFF \
	-DSFML_STATIC_LIBRARIES=TRUE \
	-DLITECGSS_NO_TEST=ON \
	-DSKALOG_NO_TEST=ON

$(SOURCES)/litecgss/external/skalog/CMakeLists.txt:
	cd $(SOURCES)/litecgss; git submodule update --init --recursive external/skalog

# ---------------------------------------------------------------------
# One Ruby (submodules sources/ruby25, ruby30, ruby32, ruby33)
#
# A released PSDK game ships YARV bytecode (`Game.yarb`,
# `Data/Scripts.dat`) that only a loader of the same Ruby version reads.
# Pokemon Studio compiles a Windows release with Ruby 3.0, a macOS
# release with Ruby 3.2 and a Linux release with Ruby 3.3. PSDK games
# released from December 2019 to about March 2021 ran on Ruby 2.5 and
# LiteRGSS 1. PSDK_RUBY picks the Ruby.
# ---------------------------------------------------------------------
PSDK_RUBY ?= 30
PSDK_RUBY_VERSION := $(shell echo $(PSDK_RUBY) | sed 's/./&./')
PSDK_RUBY_SRC := $(SOURCES)/ruby$(PSDK_RUBY)
RUBY_LIB := $(LIBDIR)/libruby.$(PSDK_RUBY_VERSION)-static.a
RUBY_EXT_LIB := $(LIBDIR)/libruby.$(PSDK_RUBY_VERSION)-ext.a

# Static only, no JIT, and no extension that iOS cannot run.
RUBY_CONFIGURE_ARGS := \
	--disable-shared \
	--enable-install-static-library \
	--with-static-linked-ext \
	--with-out-ext=fiddle,gdbm,win32ole,win32,pty,syslog,readline,bigdecimal \
	--disable-rubygems \
	--disable-install-doc \
	--disable-jit-support \
	--build=$(RBUILD) \
	--with-libyaml-dir="$(BUILD_PREFIX)"

# Ruby 3.0 bundles the openssl gem 2.2.2, which refuses to build
# against OpenSSL 3. Ruby 3.1.3 bundles the openssl gem 3.0.1, which
# builds against it, so that ext/openssl replaces the one of Ruby 2.5
# and 3.0. A released PSDK game requires openssl at boot. Ruby 3.2 and
# 3.3 bundle the openssl gems 3.1.0 and 3.2.0, which build as they are.
RUBY31_OPENSSL_VERSION := 3.1.3
RUBY31_OPENSSL_SHA256 := 5ea498a35f4cd15875200a52dde42b6eb179e1264e17d78732c3a57cd1c6ab9e
RUBY31_OPENSSL := $(DOWNLOADS)/ruby-$(RUBY31_OPENSSL_VERSION)-openssl

$(RUBY31_OPENSSL)/extconf.rb:
	@mkdir -p $(DOWNLOADS)
	curl -fL --retry 3 -o $(DOWNLOADS)/ruby-$(RUBY31_OPENSSL_VERSION).tar.gz \
		https://cache.ruby-lang.org/pub/ruby/3.1/ruby-$(RUBY31_OPENSSL_VERSION).tar.gz
	echo "$(RUBY31_OPENSSL_SHA256)  $(DOWNLOADS)/ruby-$(RUBY31_OPENSSL_VERSION).tar.gz" | shasum -a 256 -c
	rm -rf $(RUBY31_OPENSSL)
	mkdir -p $(RUBY31_OPENSSL)
	tar -xzf $(DOWNLOADS)/ruby-$(RUBY31_OPENSSL_VERSION).tar.gz -C $(RUBY31_OPENSSL) \
		--strip-components 3 ruby-$(RUBY31_OPENSSL_VERSION)/ext/openssl
	rm $(DOWNLOADS)/ruby-$(RUBY31_OPENSSL_VERSION).tar.gz

ifneq ($(filter 25 30,$(PSDK_RUBY)),)
PSDK_RUBY_CONFIGURE_DEPS := $(RUBY31_OPENSSL)/extconf.rb
# On Darwin, Ruby 2.5 names its library after the full version
# (libruby.2.5.9-static.a). The recipes below expect major.minor.
# Ruby 2.5's digest links OpenSSL's digests through a helper file that
# the copied openssl 3.0.1 no longer has. The bundled digests are the
# ones Ruby 3.0 uses.
# iOS has isfinite only as a macro, so Ruby 2.5's link test misses it.
# Then ruby/missing.h defines isfinite as finite, and that macro breaks
# the libc++ <cmath> that LiteRGSS includes after ruby.h.
PSDK_RUBY_CONFIGURE_ARGS := $(if $(filter 25,$(PSDK_RUBY)),--with-soname=ruby.2.5 \
	--with-bundled-md5 --with-bundled-sha1 --with-bundled-sha2 --with-bundled-rmd160 \
	ac_cv_func_isfinite=yes)
# Ruby 2.5's headers declare `register` parameters, and C++17 rejects
# that keyword. Their rb_intern macro also opens a statement expression
# across two macros, which clang warns about at every call.
PSDK_RUBY_CXXFLAGS := $(if $(filter 25,$(PSDK_RUBY)),-Wno-register -Wno-compound-token-split-by-macro)
PSDK_RUBY_MAKE_ARGS :=
else
PSDK_RUBY_CONFIGURE_DEPS :=
PSDK_RUBY_CONFIGURE_ARGS := --disable-yjit
# The git source of Ruby 3.2 has no parse.c, and the bison in macOS
# (2.3) is too old to make it. Homebrew's bison is keg-only. Ruby 3.3
# makes parse.c with its own tool/lrama.
PSDK_RUBY_MAKE_ARGS := $(if $(filter 32,$(PSDK_RUBY)),YACC="$(shell brew --prefix bison)/bin/bison")
endif

# libyaml 0.2.5, from the copy that Ruby 3.0's psych carries. Every
# Ruby's psych links it. Ruby 3.2 and 3.3 no longer carry libyaml, and
# Ruby 2.5 and 3.0 embed their own copy only when configure finds no
# yaml.h, so without this the result depends on the build order.
LIBYAML_SRC := $(SOURCES)/ruby30/ext/psych/yaml

$(LIBDIR)/libyaml.a: $(wildcard $(LIBYAML_SRC)/*.c) $(LIBYAML_SRC)/yaml.h
	@mkdir -p $(LIBDIR) $(INCLUDEDIR)
	rm -rf $(BUILD_PREFIX)/libyaml
	mkdir -p $(BUILD_PREFIX)/libyaml
	for src in $(LIBYAML_SRC)/*.c; do \
	    $(CC) $(CFLAGS) -O2 -DHAVE_CONFIG_H -I$(LIBYAML_SRC) \
	        -c $$src -o $(BUILD_PREFIX)/libyaml/$$(basename $$src .c).o || exit 1; \
	done
	rm -f $@
	$(AR) rcs $@ $(BUILD_PREFIX)/libyaml/*.o
	$(RANLIB) $@
	cp $(LIBYAML_SRC)/yaml.h $(INCLUDEDIR)/yaml.h

# .revision.time writes revision.h from the git commit. Only the ext
# step below asks for it, so without it here version.c compiles again
# there and miniruby links again. Ruby 2.5 then writes rbconfig.rb a
# second time, and the host Ruby that runs mkconfig.rb loads the first
# one and stops on the version check.
$(RUBY_LIB): $(PSDK_RUBY_SRC)/.configured-$(SDK_TAG)
	set -e; cd $(PSDK_RUBY_SRC); \
	$(CONFIGURE_ENV) make -j$(NPROC) $(PSDK_RUBY_MAKE_ARGS) .revision.time libruby.$(PSDK_RUBY_VERSION)-static.a; \
	cp libruby.$(PSDK_RUBY_VERSION)-static.a $(LIBDIR)/; \
	rm -rf $(INCLUDEDIR)/ruby$(PSDK_RUBY); \
	mkdir -p $(INCLUDEDIR)/ruby$(PSDK_RUBY); \
	cp -R include/* $(INCLUDEDIR)/ruby$(PSDK_RUBY)/; \
	cp .ext/include/*/ruby/config.h $(INCLUDEDIR)/ruby$(PSDK_RUBY)/ruby/config.h

# A released PSDK game requires socket, openssl, net/http, csv, json
# and zlib at boot, so a lost extension stops the game at its first
# `require`.
$(RUBY_EXT_LIB): $(RUBY_LIB)
	cd $(PSDK_RUBY_SRC); \
	$(CONFIGURE_ENV) make -j1 $(PSDK_RUBY_MAKE_ARGS) miniruby exts.mk libencs; \
	EXT_TARGETS=$$(awk '/^extensions =/,/[^\\]$$/' exts.mk | tr '\\' ' ' | grep -oE 'ext/[^ ]+' | sed 's|/\.$$|/static|'); \
	$(CONFIGURE_ENV) make -j1 -f exts.mk ext/extinit.o $$EXT_TARGETS; \
	$(CONFIGURE_ENV) make -j1 enc/encinit.o
	@TMPDIR=$$(mktemp -d); \
	cd $$TMPDIR; \
	for a in $$(find $(PSDK_RUBY_SRC)/ext -name "*.a" -not -path "*/test/*") \
	         $(PSDK_RUBY_SRC)/enc/libenc.a $(PSDK_RUBY_SRC)/enc/libtrans.a $(LIBDIR)/libyaml.a; do \
		[ -f "$$a" ] || continue; \
		sub=$$(basename $$a .a); \
		mkdir -p "$$sub"; \
		(cd "$$sub" && $(AR) x "$$a"); \
	done; \
	cp $(PSDK_RUBY_SRC)/ext/extinit.o .; \
	cp $(PSDK_RUBY_SRC)/enc/encinit.o .; \
	rm -f $@; \
	$(AR) rcs $@ extinit.o encinit.o */*.o; \
	$(RANLIB) $@; \
	rm -rf $$TMPDIR
	$(AR) d $(RUBY_LIB) dmyext.o dmyenc.o || true
	$(RANLIB) $(RUBY_LIB)
	@for sym in _Init_socket _Init_openssl _Init_zlib _Init_parser _Init_generator _Init_psych; do \
	    nm $@ 2>/dev/null | grep -q "T $$sym" || { \
	        echo "ERROR: $$sym missing from $@ (check $(PSDK_RUBY_SRC)/ext/*/mkmf.log)"; \
	        rm -f $@; \
	        exit 1; \
	    }; \
	done

# `-Wno-default-const-init-field-unsafe` is needed. The rstring.h of
# Ruby 3.0 and 3.2 declares an uninitialised `struct RString` whose
# first member is const. Clang 26 reports that, and mkmf runs its probes
# with `-Werror`. So ext/socket's IN6_IS_ADDR_UNSPECIFIED probe fails,
# extconf reads `/usr/include/netinet6/in6.h`, which a current SDK does
# not have, and the whole socket extension disappears.
$(PSDK_RUBY_SRC)/.configured-$(SDK_TAG): $(PSDK_RUBY_SRC)/configure $(LIBDIR)/libcrypto.a $(LIBDIR)/libyaml.a
	cd $(PSDK_RUBY_SRC); $(MAKE) distclean 2>/dev/null || true
	cd $(PSDK_RUBY_SRC); \
	export $(CONFIGURE_ENV); \
	export CFLAGS="-std=gnu99 -DRUBY_FUNCTION_NAME_STRING=__func__ -Wno-default-const-init-field-unsafe $$CFLAGS"; \
	./configure $(CONFIGURE_ARGS) $(RUBY_CONFIGURE_ARGS) $(PSDK_RUBY_CONFIGURE_ARGS) \
	--with-baseruby=/usr/bin/ruby \
	--with-openssl-dir="$(BUILD_PREFIX)" \
	ac_cv_func_setpgrp_void=yes \
	ac_cv_func_fork=no \
	ac_cv_func_dup3=no \
	ac_cv_func_pipe2=no \
	ac_cv_func_getentropy=no \
	ac_cv_func_posix_spawn=no \
	ac_cv_func_posix_spawnp=no \
	ac_cv_func_fdatasync=no \
	ac_cv_func_preadv=no \
	ac_cv_func_pwritev=no \
	ac_cv_func_copy_file_range=no \
	ac_cv_func_close_range=no \
	cross_compiling=yes; \
	sed -i '' 's|^ASFLAGS.*=.*|ASFLAGS = $$(ARCH_FLAG) $$(INCFLAGS) $(TARGETFLAGS)|' Makefile
	$(MARK_SDK_CONFIGURED)

# `git checkout` restores the tracked files first, so the patches and
# the openssl copy always start from a clean tree.
$(PSDK_RUBY_SRC)/configure: $(PSDK_RUBY_SRC)/configure.ac $(PSDK_RUBY_CONFIGURE_DEPS) $(ROOT)/patches/ruby$(PSDK_RUBY).patches.lst
	cd $(PSDK_RUBY_SRC); \
	git checkout -- . 2>/dev/null; \
	$(ROOT)/patches/apply-ruby-patches.sh $(PSDK_RUBY) $(PSDK_RUBY_SRC); \
	if [ -n "$(PSDK_RUBY_CONFIGURE_DEPS)" ]; then \
		rm -rf ext/openssl; \
		cp -R $(RUBY31_OPENSSL) ext/openssl; \
		rm -f ext/openssl/depend; \
	fi; \
	autoreconf -i

# ---------------------------------------------------------------------
# libpsdk<NN>.a: the whole core as one relocatable object.
#
# `ld -r` with a list of the names to keep makes every other name local:
# the Ruby, its extensions, LiteRGSS2, LiteCGSS, SFML and every library
# under them. Two cores in one app, or a core next to another engine
# with its own copy of a library, then cannot bind to each other.
# The names that stay undefined are ANGLE, the system libraries and the
# system frameworks, which the host links.
# ---------------------------------------------------------------------
PSDK_OBJDIR := $(BUILD_PREFIX)/psdk$(PSDK_RUBY)
PSDK_LIB := $(OUT)/$(SDK)/libpsdk$(PSDK_RUBY).a
PSDK_EXPORTS := $(BUILD_PREFIX)/psdk-exports.txt

PSDK_INCLUDES := \
    -I$(INCLUDEDIR)/ruby$(PSDK_RUBY) \
    -I$(INCLUDEDIR) \
    -I$(ROOT)/src \
    -I$(SOURCES)/litergss2/ext/LiteRGSS \
    -I$(SOURCES)/litecgss/src/src \
    -I$(SOURCES)/litecgss/external/skalog/src/src \
    -I$(SOURCES)/litecgss/external/lodepng \
    -I$(SOURCES)/litecgss/external/libnsgif

PSDK_ARCHIVES := \
    $(RUBY_LIB) $(RUBY_EXT_LIB) \
    $(LIBDIR)/libLiteCGSS_engine.a $(LIBDIR)/libskalog.a \
    $(LIBDIR)/libsfml-graphics-s.a $(LIBDIR)/libsfml-window-s.a \
    $(LIBDIR)/libsfml-audio-s.a $(LIBDIR)/libsfml-system-s.a \
    $(LIBDIR)/libfreetype.a $(LIBDIR)/libpng16.a \
    $(LIBDIR)/libvorbisfile.a $(LIBDIR)/libvorbisenc.a $(LIBDIR)/libvorbis.a \
    $(LIBDIR)/libFLAC.a $(LIBDIR)/libogg.a $(LIBDIR)/libopenal.a \
    $(LIBDIR)/libssl.a $(LIBDIR)/libcrypto.a

.PHONY: psdk-ruby psdk-lib psdk-support

psdk-ruby: init_dirs litecgss openssl
	$(MAKE) PSDK_RUBY=$(PSDK_RUBY) psdk-lib psdk-support

psdk-lib: $(PSDK_LIB)

$(PSDK_EXPORTS): $(ROOT)/src/psdk_core.h
	@mkdir -p $(dir $@)
	grep -oE '\bpsdk_[a-z_0-9]+\(' $< | sed 's/($$//; s/^/_/' | sort -u > $@

$(PSDK_LIB): $(RUBY_EXT_LIB) $(PSDK_EXPORTS) $(PSDK_ARCHIVES) \
             $(wildcard $(ROOT)/src/*.cpp $(ROOT)/src/*.h) \
             $(wildcard $(SOURCES)/litergss2/ext/LiteRGSS/*.cpp $(SOURCES)/litergss2/ext/LiteRGSS/*.h)
	@echo "[psdk] Compiling LiteRGSS2 against Ruby $(PSDK_RUBY_VERSION)..."
	@rm -rf $(PSDK_OBJDIR)
	@mkdir -p $(PSDK_OBJDIR) $(dir $@)
	@for src in $(SOURCES)/litergss2/ext/LiteRGSS/*.cpp; do \
	    $(CXX) $(TARGETFLAGS) -std=c++17 -fdeclspec -O3 $(PSDK_RUBY_CXXFLAGS) \
	        $(PSDK_INCLUDES) -DHAVE_CONFIG_H \
	        -c $$src -o $(PSDK_OBJDIR)/$$(basename $$src .cpp).o || exit 1; \
	done
	@echo "[psdk] Compiling the core..."
	@$(CXX) $(TARGETFLAGS) -std=c++17 -O3 $(PSDK_RUBY_CXXFLAGS) -I$(INCLUDEDIR)/ruby$(PSDK_RUBY) \
	    -c $(ROOT)/src/psdk_core.cpp -o $(PSDK_OBJDIR)/_psdk_core.o
	@$(CXX) $(TARGETFLAGS) -std=c++17 -O3 -I$(INCLUDEDIR) \
	    -c $(ROOT)/src/psdk_host.cpp -o $(PSDK_OBJDIR)/_psdk_host.o
	@$(CXX) $(TARGETFLAGS) -std=c++17 -O3 $(PSDK_RUBY_CXXFLAGS) -I$(INCLUDEDIR)/ruby$(PSDK_RUBY) -I$(INCLUDEDIR) \
	    -c $(ROOT)/src/sfml_audio.cpp -o $(PSDK_OBJDIR)/_psdk_sfml_audio.o
	@echo "[psdk] Merging with ld -r..."
	@LD=$$(xcrun --sdk $(SDK) -f ld); \
	"$$LD" -r -arch $(ARCH) $(LD_PLATFORM_VERSION) -syslibroot $(SYSROOT) \
	    -exported_symbols_list $(PSDK_EXPORTS) \
	    $(PSDK_OBJDIR)/*.o $(PSDK_ARCHIVES) \
	    -o $(PSDK_OBJDIR)/merged-pass1.o
	@# `ld -r` keeps a common (a C global with no value, such as
	@# rb_cObject) external even when the keep list leaves it out, and it
	@# has no -d option to turn it into data. So a second pass gives each
	@# common a zero-filled definition of its own size and alignment, and
	@# the keep list then makes that definition local.
	@nm -m $(PSDK_OBJDIR)/merged-pass1.o | awk '$$2 == "(common)" && / external / { \
	    a = 0; if ($$3 == "(alignment") { a = $$4; sub(/.*\^/, "", a); sub(/\)/, "", a) } \
	    printf ".globl %s\n.zerofill __DATA,__common,%s,0x%s,%s\n", $$NF, $$NF, $$1, a }' \
	    > $(PSDK_OBJDIR)/commons.s
	@$(CC) $(TARGETFLAGS) -c $(PSDK_OBJDIR)/commons.s -o $(PSDK_OBJDIR)/commons.o
	@LD=$$(xcrun --sdk $(SDK) -f ld); \
	"$$LD" -r -arch $(ARCH) $(LD_PLATFORM_VERSION) -syslibroot $(SYSROOT) \
	    -exported_symbols_list $(PSDK_EXPORTS) \
	    $(PSDK_OBJDIR)/merged-pass1.o $(PSDK_OBJDIR)/commons.o \
	    -o $(PSDK_OBJDIR)/libpsdk.o
	@rm -f $@
	@$(AR) rcs $@ $(PSDK_OBJDIR)/libpsdk.o
	@nm -gm $(PSDK_OBJDIR)/libpsdk.o | grep -v '(undefined)' | awk '{print $$NF}' | sort -u \
	    > $(PSDK_OBJDIR)/exported.txt
	@diff -u $(PSDK_EXPORTS) $(PSDK_OBJDIR)/exported.txt || { \
	    echo "ERROR: $@ must export the names in psdk_core.h and no other name"; \
	    rm -f $@; \
	    exit 1; \
	}

# The Ruby support folder, which psdk_run prepends to $LOAD_PATH and
# names in GAMEDEPS.
#
# 1. The pure-Ruby half of the stdlib. A Windows release ships all of it
#    under lib/ruby/3.0.0, and a game can require any file in it:
#    Lethalmon stops at boot without base64.rb. A macOS release ships
#    none of it, and the openssl half has to come from the same gem as
#    the C half.
#
# 2. ruby-dist/lib/LiteRGSS.rb and ruby-dist/lib/SFMLAudio.rb. PSDK loads
#    a native extension with `require File.join(PSDK_LIB_PATH, name)`,
#    where PSDK_LIB_PATH is "#{ENV['GAMEDEPS']}/ruby-dist/lib" on macOS.
#    The classes are already in the binary, so a file only has to exist
#    for the require to succeed. LiteRGSS.rb is empty for that reason.
#    SFMLAudio.rb carries one patch, which it explains itself. RubyFmod
#    gets no file on purpose. PSDK tries it first, and the LoadError is
#    what sends it to SFMLAudio.
#
# 3. compat.rb, which psdk_run loads before Game.rb. It holds the fixes
#    for things released games do.
#
# The Ruby 2.5 folder adds litergss1.rb and RubyFmod.rb at the top.
# Games from that time call LiteRGSS 1 and play sound only through FMOD,
# and each file explains how it stands in.
PSDK_SUPPORT_DIR := $(OUT)/support/$(PSDK_RUBY_VERSION)

# Bundler and RDoc only run from a command line. They are 4.1 MB of the
# 8.7 MB.
PSDK_SUPPORT_SKIP := bundler bundler.rb rdoc rdoc.rb

PSDK_SUPPORT_EXT := socket digest openssl date json psych

psdk-support: $(RUBY_EXT_LIB)
	rm -rf $(PSDK_SUPPORT_DIR)
	mkdir -p $(PSDK_SUPPORT_DIR)/ruby-dist/lib
	touch $(PSDK_SUPPORT_DIR)/ruby-dist/lib/LiteRGSS.rb
	cp $(ROOT)/support/SFMLAudio.rb $(PSDK_SUPPORT_DIR)/ruby-dist/lib/SFMLAudio.rb
	cp $(ROOT)/support/compat.rb $(PSDK_SUPPORT_DIR)/compat.rb
	$(if $(filter 25,$(PSDK_RUBY)),cp $(ROOT)/support/litergss1.rb $(ROOT)/support/RubyFmod.rb $(PSDK_SUPPORT_DIR)/)
	cp -R $(PSDK_RUBY_SRC)/lib/ $(PSDK_SUPPORT_DIR)/
	cd $(PSDK_SUPPORT_DIR) && rm -rf $(PSDK_SUPPORT_SKIP)
	@for ext in $(PSDK_SUPPORT_EXT); do \
		cp -R $(PSDK_RUBY_SRC)/ext/$$ext/lib/ $(PSDK_SUPPORT_DIR)/ || exit 1; \
	done
	@find $(PSDK_SUPPORT_DIR) -name "*.gemspec" -delete
	@# A require that resolves to neither a shipped file nor a linked C
	@# extension is a gap. Conditional requires make a hard failure too
	@# noisy, so this only warns.
	@grep -rhoE "^[[:space:]]*require ['\"][a-z0-9_/.-]+['\"]" $(PSDK_SUPPORT_DIR) 2>/dev/null \
	  | sed -E "s/^[[:space:]]*require ['\"]([^'\"]+)['\"]/\1/" | sort -u \
	  | while read -r feat; do \
		base=$${feat%.rb}; \
		[ -f "$(PSDK_SUPPORT_DIR)/$$base.rb" ] && continue; \
		[ -d "$(PSDK_SUPPORT_DIR)/$$base" ] && continue; \
		nm -gU $(RUBY_EXT_LIB) $(RUBY_LIB) 2>/dev/null \
		  | grep -q " T _Init_$$(basename $${base%.so})$$" && continue; \
		echo "  [psdk$(PSDK_RUBY)-support audit] unresolved require: $$feat"; \
	done; true
