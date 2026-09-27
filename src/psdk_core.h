// PSDK core: runs a released Pokemon SDK game on LiteRGSS2, LiteCGSS,
// SFML and one Ruby.
//
// There is one static library for each Ruby, libpsdk25.a to libpsdk33.a,
// and each one defines every name below and no other name. Link one of
// them into one image. A host that offers more than one Ruby links each
// one into its own framework and opens one of them for each process.
//
// A host links the ANGLE static libraries and the system frameworks next
// to the library. README.md lists them.
//
// Unless a comment says otherwise, a call is safe from any thread.
#ifndef PSDK_CORE_H
#define PSDK_CORE_H

#ifdef __cplusplus
extern "C" {
#endif

enum PsdkResult {
    PSDK_OK = 0,
    PSDK_RUBY_BOOT_FAILED = -1,
    PSDK_LITERGSS_MISSING = -2,
    PSDK_CHDIR_FAILED = -3,
    PSDK_PRELUDE_RAISED = -4,
    PSDK_GAME_RAISED = -5,
    PSDK_SUPPORT_MISSING = -6,
};

// Runs the game in gameDir and returns when it stops.
//
// Call this once for each process, and not from the main thread. Ruby's
// `ruby_init` runs once for each process, and SFML marshals its UIKit
// calls to the main thread with dispatch_sync, so the main thread has
// to stay free to answer them.
//
// argc and argv come straight from main. Ruby keeps them and reads
// argv[0] later for its own paths, so a caller that passes 0 and null
// leaves Ruby to fall back on whatever it can find.
//
// supportDir names the Ruby support folder of this library's Ruby,
// support/<version> in the release. The core prepends it to $LOAD_PATH
// and points the GAMEDEPS variable at it. PSDK reads GAMEDEPS to find
// its native extensions. The core also runs compat.rb from it, which
// holds the fixes for things released games do.
//
// preludePath, when it is not null, names a Ruby file of the host that
// runs after compat.rb and before Game.rb.
//
// Returns PSDK_OK when the game stopped on its own, or a negative
// PsdkResult.
int psdk_run(int argc, char **argv, const char *gameDir, const char *supportDir,
             const char *preludePath);

// RUBY_VERSION of this library's Ruby, such as "3.0.7".
const char *psdk_ruby_version(void);

// MARK: - Input

// Presses or releases one key. usage is the USB HID usage ID of the key
// on the keyboard page (0x07), which is also the SDL scancode. A key
// that PSDK does not read does nothing.
void psdk_inject_key(int usage, int pressed);

// Types UTF-8 text, as sf::Event::TextEntered events.
void psdk_inject_text(const char *utf8);

// The game asks for the on-screen keyboard (visible is 1) or lets it go
// (visible is 0). Without a callback, SFML shows the system keyboard
// itself. Pass null to give the keyboard back to SFML.
void psdk_set_keyboard_callback(void (*callback)(int visible, void *userdata),
                                void *userdata);

// Turns the touches that reach the game on or off. On by default.
void psdk_set_touch_enabled(int enabled);

// MARK: - The picture

// The UIWindow that SFML made for the game, or null before the game
// opens its window.
void *psdk_game_window(void);

// The size of the game window in pixels, or 0 by 0 before the game
// opens its window.
void psdk_window_pixel_size(unsigned int *width, unsigned int *height);

// Pixels for each point of the game window, or 0 before the game opens
// its window.
float psdk_backing_scale(void);

// The part of the game window that the picture fills, as fractions of
// the window with the origin at the top left. 0, 0, 1, 1 gives the whole
// window, which is the start value. A touch inside this part reaches the
// game at the game pixel under it.
void psdk_set_output_region(float x, float y, float width, float height);

// Smooth (1) or sharp (0) scaling of the picture. Sharp by default. A
// texture reads the value when the game makes it, so set it before
// psdk_run. A new value reaches the whole game on the next start.
void psdk_set_smooth(int smooth);

// Called on the game thread for each frame, before the swap. The GL
// context is current and the default framebuffer holds the frame, so
// glReadPixels reads it. A callback that does not return holds the
// game.
void psdk_set_frame_callback(void (*callback)(void *userdata), void *userdata);

// Called with the resolution the game asks for, when it opens its window
// and when it changes the resolution.
void psdk_set_resolution_callback(void (*callback)(long width, long height, void *userdata),
                                  void *userdata);

// MARK: - Speed and sound

// Game updates for each drawn frame. 1 by default. A new value applies
// while the game runs.
void psdk_set_speed(int multiplier);

// Stops and restarts all game sound. A game that has not played a sound
// yet has nothing to stop.
void psdk_pause_audio(void);
void psdk_resume_audio(void);

#ifdef __cplusplus
}
#endif

#endif
