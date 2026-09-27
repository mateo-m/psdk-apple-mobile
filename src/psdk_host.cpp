// The calls of psdk_core.h that need no Ruby. They forward to the SFML
// and LiteRGSS2 forks and to OpenAL Soft.
#include "psdk_core.h"

#include <SFML/System/String.hpp>
#include <SFML/Window/Keyboard.hpp>

#include <cstring>

#define AL_ALEXT_PROTOTYPES
#include <AL/alc.h>
#include <AL/alext.h>

extern "C" {
void sfml_ios_inject_key_event(int sfScan, int pressed);
void sfml_ios_inject_character(unsigned int unicode);
void sfml_ios_set_virtual_keyboard_callback(void (*callback)(int, void *), void *userdata);
void *sfml_ios_game_window();
float sfml_ios_backing_scale();
void sfml_window_pixel_size(unsigned int *width, unsigned int *height);
void sfml_set_output_region(float x, float y, float width, float height);
void sfml_set_default_smooth(int smooth);
void sfml_set_before_swap_callback(void (*callback)(void *), void *userdata);
void litergss_set_touch_enabled(int enabled);
void litergss_set_resolution_callback(void (*callback)(long, long, void *), void *userdata);
}

namespace {

using Scan = sf::Keyboard::Scan;

// USB HID usage IDs of the keyboard page, and the SFML scancode of each.
Scan::Scancode toSfmlScancode(int usage) {
    if (usage >= 0x04 && usage <= 0x1D) {
        return static_cast<Scan::Scancode>(Scan::A + (usage - 0x04));
    }
    if (usage >= 0x1E && usage <= 0x27) {
        return static_cast<Scan::Scancode>(Scan::Num1 + (usage - 0x1E));
    }
    if (usage >= 0x3A && usage <= 0x45) {
        return static_cast<Scan::Scancode>(Scan::F1 + (usage - 0x3A));
    }
    switch (usage) {
        case 0x28: return Scan::Enter;
        case 0x29: return Scan::Escape;
        case 0x2A: return Scan::Backspace;
        case 0x2B: return Scan::Tab;
        case 0x2C: return Scan::Space;
        case 0x2D: return Scan::Hyphen;
        case 0x2E: return Scan::Equal;
        case 0x2F: return Scan::LBracket;
        case 0x30: return Scan::RBracket;
        case 0x31: return Scan::Backslash;
        case 0x33: return Scan::Semicolon;
        case 0x34: return Scan::Apostrophe;
        case 0x35: return Scan::Grave;
        case 0x36: return Scan::Comma;
        case 0x37: return Scan::Period;
        case 0x38: return Scan::Slash;
        case 0x4A: return Scan::Home;
        case 0x4F: return Scan::Right;
        case 0x50: return Scan::Left;
        case 0x51: return Scan::Down;
        case 0x52: return Scan::Up;
        case 0xE0: return Scan::LControl;
        case 0xE1: return Scan::LShift;
        case 0xE2: return Scan::LAlt;
        default: return Scan::Unknown;
    }
}

ALCdevice *pausedAudio = nullptr;

} // namespace

void psdk_inject_key(int usage, int pressed) {
    const Scan::Scancode scan = toSfmlScancode(usage);
    if (scan == Scan::Unknown) {
        return;
    }
    sfml_ios_inject_key_event(scan, pressed);

    // PSDK's name screen reads Return and Backspace as text, not as
    // keys: `update_name` confirms on code point 13 and deletes on 8.
    // On a desktop, SFML sends a text event with those code points
    // next to the key event. The iOS backend sends no text of its own,
    // so the two keys get theirs here. Escape gets none, because the
    // name screen would eat it and the player could not leave.
    if (pressed && scan == Scan::Enter) {
        sfml_ios_inject_character('\r');
    } else if (pressed && scan == Scan::Backspace) {
        sfml_ios_inject_character('\b');
    }
}

void psdk_inject_text(const char *utf8) {
    if (!utf8) {
        return;
    }
    for (const sf::Uint32 character : sf::String::fromUtf8(utf8, utf8 + std::strlen(utf8))) {
        sfml_ios_inject_character(character);
    }
}

void psdk_set_keyboard_callback(void (*callback)(int, void *), void *userdata) {
    sfml_ios_set_virtual_keyboard_callback(callback, userdata);
}

void psdk_set_touch_enabled(int enabled) { litergss_set_touch_enabled(enabled); }

void *psdk_game_window(void) { return sfml_ios_game_window(); }

void psdk_window_pixel_size(unsigned int *width, unsigned int *height) {
    sfml_window_pixel_size(width, height);
}

float psdk_backing_scale(void) { return sfml_ios_backing_scale(); }

void psdk_set_output_region(float x, float y, float width, float height) {
    sfml_set_output_region(x, y, width, height);
}

void psdk_set_smooth(int smooth) { sfml_set_default_smooth(smooth); }

void psdk_set_frame_callback(void (*callback)(void *), void *userdata) {
    sfml_set_before_swap_callback(callback, userdata);
}

void psdk_set_resolution_callback(void (*callback)(long, long, void *), void *userdata) {
    litergss_set_resolution_callback(callback, userdata);
}

// SFMLAudio hands sf::Music and sf::Sound to Ruby and keeps no list, so
// the pause stops the whole OpenAL Soft device. The context is null
// until the game plays its first sound.
void psdk_pause_audio(void) {
    pausedAudio = alcGetContextsDevice(alcGetCurrentContext());
    if (pausedAudio) {
        alcDevicePauseSOFT(pausedAudio);
    }
}

void psdk_resume_audio(void) {
    if (pausedAudio) {
        alcDeviceResumeSOFT(pausedAudio);
        pausedAudio = nullptr;
    }
}
