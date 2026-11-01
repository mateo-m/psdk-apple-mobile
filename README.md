# psdk-apple-mobile

Runs a released [Pokemon SDK](https://gitlab.com/pokemonsdk/pokemonsdk) game on iOS and macOS. The core is LiteRGSS2, LiteCGSS, SFML, OpenAL Soft and one Ruby, built as one static library for each Ruby.

A game runs on the Ruby that compiled its bytecode:

| Library | Ruby | Games |
| --- | --- | --- |
| `libpsdk25.a` | 2.5.9 | Games released from December 2019 to about March 2021 |
| `libpsdk30.a` | 3.0.7 | Windows releases from Pokemon Studio |
| `libpsdk32.a` | 3.2.2 | macOS releases from Pokemon Studio |
| `libpsdk33.a` | 3.3.0 | Linux releases from Pokemon Studio |

## Use a release

Each release has `psdk-ios.tar.gz`:

```
MANIFEST
licenses.json
include/psdk_core.h
iphoneos/libpsdk25.a ... libpsdk33.a
iphonesimulator/libpsdk25.a ... libpsdk33.a
macosx/libpsdk25.a ... libpsdk33.a
support/2.5, 3.0, 3.2, 3.3
```

`src/psdk_core.h` is the whole interface. Each library defines the names in that header and no other name. So link one library into one image. To offer more than one Ruby, link each library into its own framework.

On iOS, link these next to the library:

- ANGLE: `libANGLE_static.a`, `libEGL_static.a` and `libGLESv2_static.a` from the release that `MANIFEST` names, at https://github.com/mateo-m/empo-deps/releases.
- `-lc++ -lz -lbz2 -liconv`
- The frameworks Foundation, UIKit, CoreFoundation, CoreGraphics, CoreVideo, CoreAudio, AudioToolbox, AVFoundation, Metal, QuartzCore, GameController, CoreMotion and IOSurface.
- The weak frameworks CoreBluetooth and CoreHaptics.

On macOS, SFML draws with the system OpenGL, so the core needs no ANGLE. Link these next to the library:

- `-ObjC -lc++ -lz -lbz2 -liconv`. Without `-ObjC`, the linker drops the Objective-C categories of SFML's Cocoa backend, and the game stops with "unrecognized selector" when it makes its window.
- The frameworks Foundation, AppKit, Carbon, IOKit, OpenGL, CoreFoundation, CoreGraphics, CoreAudio, AudioToolbox, AudioUnit, CoreServices and Security.

Put the `support/<version>` folder of the same Ruby in the app, and give its path to `psdk_run`. The folder holds `compat.rb`, the fixes for things released games do, and `psdk_run` loads it before the game.

`licenses.json` lists the license notice of each library in the core, as `name`, `license` and `text`. Show the notices in the app. `tools/licenses.rb` writes the file from `licenses/manifest.json` and the source trees. The build fails when a linked archive has no entry in the manifest.

For HTTPS, set `SSL_CERT_FILE` to a PEM file of root certificates before `psdk_run`. iOS gives Ruby's OpenSSL no certificates, so without the file each HTTPS call fails with "certificate verify failed".

## Build

You need Xcode with the iOS 26 and macOS 26 SDKs, and `autoconf`, `automake`, `libtool` and `bison` from Homebrew.

```sh
git submodule update --init
make SDK=iphonesimulator            # all four Rubies
make SDK=iphoneos RUBIES=30         # only Ruby 3.0
make SDK=macosx                     # the Mac
```

The results go to `out/`.

## Test

`tools/test-host` builds a small app that links one library and runs one game on a simulator:

```sh
tools/test-host/build-test-host-ios.sh --ruby 3.0
tools/test-host/run-test-host-ios.sh --ruby 3.0 --game ~/Games/MyGame --seconds 60
```

`scripts/check-no-host-code.sh` fails when the core or a fork names a launcher or asks the host for a function. A host sets each value through `psdk_core.h`.

## License

Copyright (C) 2026 Mateo M.

The code that Mateo M. wrote is under the [GPLv3](LICENSE), with [additional terms](ADDITIONAL-TERMS.md) that GPLv3 section 7 permits. Each of these files says so in its header. Code from other projects keeps its own license.

If you ship this core in an app, keep the text "psdk-apple-mobile, Copyright (C) 2026 Mateo M., https://github.com/mateo-m/psdk-apple-mobile" on the licenses or credits screen of the app, and do not say that you wrote this code. Versions before this change are under GPL-2.0.
