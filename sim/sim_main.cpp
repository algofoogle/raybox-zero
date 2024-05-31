/*
 * SPDX-FileCopyrightText: 2023 Anton Maurovic <anton@maurovic.com>
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *      http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 * SPDX-License-Identifier: Apache-2.0
 */

#include <stdio.h>
// #include <err.h>
#include <iostream>
#include <string>
#include <vector>
#include <filesystem> // For std::filesystem::absolute() (which is only used if we have C++17)
#include "testbench.h"
using namespace std;

#include "Vrbzero.h"

#define DESIGN      rbzero
#define VDESIGN     Vrbzero
#define MAIN_TB     Vrbzero_TB
#define BASE_TB     TESTBENCH<VDESIGN>

#define HILITE      0b0001'1111

//#define DESIGN_DIRECT_VECTOR_ACCESS   // Defined=new_playerX etc are exposed; else=SPI only.
//#define DEBUG_BUTTON_INPUTS
//#define USE_SPEAKER

//SMELL: These must be set to the same numbers in fixed_point_params.v:
#define Qm  11
#define Qn  11
//NOTE: Currently these don't have much (or any?) effect over SPI,
// because the vectors have their own hard-coded ranges.

// #define USE_POWER_PINS //NOTE: This is automatically set in the Makefile, now.
#define INSPECT_INTERNAL //NOTE: This is automatically set in the Makefile, now.
#ifdef INSPECT_INTERNAL
  #include "Vrbzero_rbzero.h"       // Needed for accessing "verilator public" stuff in `rbzero`
#endif

#define FONT_FILE "sim/font-cousine/Cousine-Regular.ttf"

// #define DOUBLE_CLOCK
#ifdef DOUBLE_CLOCK
  #define CLOCK_HZ    50'000'000
#else
  #define CLOCK_HZ    25'000'000
#endif

#define S1(s1) #s1
#define S2(s2) S1(s2)

#include <SDL2/SDL.h>
// #include <SDL2/SDL_image.h> // This will be used for loading "ROMs" that interface with the design: Map & Texture data.
#include <SDL2/SDL_ttf.h>

// It would be nice if these could be retrieved directly from the Verilog (vga_sync.v).
// I think there's a way to do it with a "DPI" or some other Verilator method.
#define HDA 640    // Horizontal display area.
#define HFP 16     // Front porch (defined in this case to mean "coming after HDA, and before HSP").
#define HSP 96     // HSYNC pulse.
#define HBP 48     // Back porch (defined in this case to mean "coming after HSP").
#define VDA 480    // Vertical display area.
#define VFP 10     // Front porch.
#define VSP 2      // VSYNC pulse.
#define VBP 33     // Back porch.

#define HFULL (HDA+HFP+HSP+HBP)
#define VFULL (VDA+VFP+VSP+VBP)

// Extra space to show on the right and bottom of the virtual VGA screen,
// used for identifying extreme limits of things (and possible overflow):
#define EXTRA_RHS         50
#define EXTRA_BOT         50
#define H_OFFSET          HSP+HBP   // Left-hand margin during HSYNC pulse and HBP that comes before HDA.
#define V_OFFSET          VSP+VBP

#define REFRESH_PIXEL     1
#define REFRESH_SLOW      8
#define REFRESH_FASTPIXEL 100
#define REFRESH_LINE      HFULL
#define REFRESH_10LINES   HFULL*10
#define REFRESH_80LINES   HFULL*80
#define REFRESH_FRAME     HFULL*VFULL

// SDL window size in pixels. This is what our design's timing should drive in VGA:
#define WINDOW_WIDTH  (HFULL+EXTRA_RHS)
#define WINDOW_HEIGHT (VFULL+EXTRA_BOT)
#define FRAMEBUFFER_SIZE WINDOW_WIDTH*WINDOW_HEIGHT*4

// The MAIN_TB class that includes specifics about running our design in simulation:
#include "main_tb.h"


//SMELL: This doesn't do anything besides keeping certain linkers happy.
// See: https://veripool.org/guide/latest/faq.html#why-do-i-get-undefined-reference-to-sc-time-stamp
double sc_time_stamp() { return 0; }

#ifdef WINDOWS
//SMELL: For some reason, when building this under Windows, it stops building as a console command
// and instead builds as a Windows app requiring WinMain. Possibly something to do with Verilator
// or SDL2 under windows. I'm not sure yet. Anyway, this is a temporary workaround. The Makefile
// will include `-CFLAGS -DWINDOWS`, when required, in order to activate this code:
#include <windows.h>
int WINAPI WinMain(HINSTANCE hInstance, HINSTANCE hPrevInstance, LPSTR lpCmdLine, int nCmdShow)
{
  // char* nothing = "nothing";
  // return main(1, &nothing);
  SetProcessDPIAware(); // Prevent window scaling, so we get a pixel-perfect SDL display.
  printf("DEBUG: WinMain command-line: '%s'\n", lpCmdLine);
  return main(__argc, __argv); // See: https://stackoverflow.com/a/40107581
  return 0;
}
#endif // WINDOWS


// Testbench for main design:
MAIN_TB       *TB;
bool          gQuit = false;
int           gRefreshLimit = REFRESH_FRAME;
int           gOriginalTime;
int           gPrevTime;
int           gPrevFrames;
unsigned long gPrevTickCount;
bool          gSyncLine = false;
bool          gSyncFrame = false;
bool          gHighlight = true;
bool          gGuides = false;
bool          gOverrideVectors = false;
bool          gSwapMouseXY = false;
bool          gRotateView = false;
bool          gEnableSPI = false;
bool          gAnimateRegisters = false; // If true, do funky stuff with sky/floor colour and leak.
bool          gInfiniteHeight = false;
bool          gGenTex = false; // If true, select generated textures instead of texture memory.
int           gMouseX, gMouseY;
int           gColorSky = 0;
int           gColorFloor = 0;
int           gLeak = 0;
int           gTexVShift = 0;
int           gMapDX = 0;
int           gMapDY = 0;
int           gMapDXW = 0;
int           gMapDYW = 0;
bool          gMouseYTexV = false;
double        gMotionMultiplier = 1.0;
#ifdef WINDOWS
bool          gMouseCapture = true;
#else
bool          gMouseCapture = false; // Not on by default in Linux, because of possible mouse relative motion weirdness.
#endif


// 'gView' is the current view state:
typedef struct {
  double px, py, fx, fy, vx, vy; // Standard vectors.
  double sf, sv; // Optional vector scaling.
} float_vectors_t;
float_vectors_t gView = {
  // 13.50, 11.75, // player
  // -1.00,  0.00, // facing
  //  0.00, -0.50, // vplane

  // playerX/Y:
  11.500000,
  10.500000,
  // facingX/Y -- Increasing magnitude means narrower FOV (i.e. more zoomed).
   0.720137,
  -0.693832,
  // vplaneX/Y -- Larger magnitude means squashed view (narrower blocks). 0.5 is default square aspect. 0.5625 feels more like Wolf3D.
   0.346916,
   0.360069,
  // Sim's scaling factor:
   1.00,       // scale facing
   1.00        // scale vplane
};

//SMELL: @raybox leftovers:
enum {
  LOCK_F = 0,
  LOCK_B,
  LOCK_L,
  LOCK_R,
  LOCK_MAP,
  LOCK_DEBUG,
  LOCK_TRACE,
  LOCK__MAX
};
bool gLockInputs[LOCK__MAX] = {0};


// From: https://stackoverflow.com/a/38169008
// - x, y: upper left corner.
// - texture, rect: outputs.
void get_text_and_rect(
  SDL_Renderer *renderer,
  int x,
  int y,
  const char *text,
  TTF_Font *font,
  SDL_Texture **texture,
  SDL_Rect *rect
) {
  int text_width;
  int text_height;
  SDL_Surface *surface;
  SDL_Color textColor = {255, 255, 255, 0};

  surface = TTF_RenderText_Solid(font, text, textColor);
  *texture = SDL_CreateTextureFromSurface(renderer, surface);
  text_width = surface->w;
  text_height = surface->h;
  SDL_FreeSurface(surface);
  rect->x = x;
  rect->y = y;
  rect->w = text_width;
  rect->h = text_height;
}

// If part is 0, calculate from both the integer and fractional parts.
// If <0, calculate from fractional part only.
// If >0, calculate from integer part only.
double fixed2double(uint32_t fixed, int part = 0) {
  int32_t t = fixed;
  if (part<0) {
    // Kill integer part:
    t &= (1<<Qn)-1;
  }
  else if (part>0) {
    // Kill fractional part:
    t &= ((1<<Qm)-1)<<Qn;
  }
  // Sign extension:
  bool sign = t & (1<<((Qm+Qn)-1));
  if (sign) t |= ((1<<(32-(Qm+Qn)))-1)<<(Qm+Qn);
  return double(t) / pow(2.0, Qn);
}

uint32_t double2fixed(double d) {
  int32_t t = d * pow(2.0, Qn);
  return t & ((1<<(Qm+Qn))-1);
}


void toggle_mouse_capture(bool force = false, bool force_to = false) {
  if (!force) {
    gMouseCapture = !gMouseCapture;
  } else {
    gMouseCapture = force_to;
  }
  if (gMouseCapture) {
    int r = SDL_SetRelativeMouseMode(SDL_TRUE);
    if (r) {
      printf("SDL_SetRelativeMouseMode(SDL_TRUE) failed (%d): %s\n", r, SDL_GetError());
    } else {
      printf("Mouse captured.\n");
      gMouseX = 0;
      gMouseY = 0;
    }
  } else {
    int r = SDL_SetRelativeMouseMode(SDL_FALSE);
    if (r) {
      printf("SDL_SetRelativeMouseMode(SDL_FALSE) failed (%d): %s\n", r, SDL_GetError());
    } else {
      printf("Mouse released.\n");
    }
  }
}


void scale_motion_multiplier(double s) {
  gMotionMultiplier *= s;
  printf("Motion multiplier is now: %lf\n", gMotionMultiplier);
}


void process_sdl_events() {
  // Event used to receive window close, keyboard actions, etc:
  SDL_Event e;
  // Consume SDL events, if any, until the event queue is empty:
  while (SDL_PollEvent(&e) == 1) {
    if (SDL_QUIT == e.type) {
      // SDL quit event (e.g. close window)?
      gQuit = true;
    } else if (SDL_KEYDOWN == e.type) {
      int fn_key = 0;
      switch (e.key.keysym.sym) {
        case SDLK_F12:
          // Toggle mouse capture.
          toggle_mouse_capture();
          break;
        case SDLK_F11:
          // Toggle generated/memory textures.
          gGenTex = !gGenTex;
          printf("Texture source: %s\n", gGenTex ? "Bitwise-generated" : "Texture SPI memory");
          break;
        case SDLK_F10:++fn_key;
        case SDLK_F9: ++fn_key;
        case SDLK_F8: ++fn_key;
        case SDLK_F7: ++fn_key;
        case SDLK_F6: ++fn_key;
        case SDLK_F5: ++fn_key;
        case SDLK_F4: ++fn_key;
        case SDLK_F3: ++fn_key;
        case SDLK_F2: ++fn_key;
        case SDLK_F1: ++fn_key;
          {
            // Directly set override vectors...
            printf("Loading state #%d -- NOT IMPLEMENTED\n", fn_key);
            //SMELL: Not implemented. Used to load a known set of vectors.
            break;
          }
        // case SDLK_q:
        case SDLK_ESCAPE:
          gQuit = true;
          break;
        case SDLK_SPACE:
          TB->pause(!TB->paused);
          break;
        case SDLK_e:
          gEnableSPI = !gEnableSPI;
          printf("SPI transmissions are %s\n", gEnableSPI ? "ENABLED" : "disabled");
          break;
        case SDLK_g:
          gGuides = !gGuides;
          printf("Guides turned %s\n", gGuides ? "ON" : "off");
          break;
        case SDLK_h:
          gHighlight = !gHighlight;
          printf("Highlighting turned %s\n", gHighlight ? "ON" : "off");
          break;
        case SDLK_1:
          gRefreshLimit = REFRESH_PIXEL;
          gSyncLine = false;
          gSyncFrame = false;
          printf("Refreshing every pixel\n");
          break;
        case SDLK_8:
          gRefreshLimit = REFRESH_SLOW;
          gSyncLine = false;
          gSyncFrame = false;
          printf("Refreshing every 8 pixels\n");
          break;
        case SDLK_9:
          gRefreshLimit = REFRESH_FASTPIXEL;
          gSyncLine = false;
          gSyncFrame = false;
          printf("Refreshing every 100 pixels\n");
          break;
        case SDLK_2:
          gRefreshLimit = REFRESH_LINE;
          gSyncLine = true;
          gSyncFrame = false;
          printf("Refreshing every line\n");
          break;
        case SDLK_3:
          gRefreshLimit = REFRESH_10LINES;
          gSyncLine = true;
          gSyncFrame = false;
          printf("Refreshing every 10 lines\n");
          break;
        case SDLK_4:
          gRefreshLimit = REFRESH_80LINES;
          gSyncLine = true;
          gSyncFrame = false;
          printf("Refreshing every 80 lines\n");
          break;
        case SDLK_5:
          gRefreshLimit = REFRESH_FRAME;
          gSyncLine = true;
          gSyncFrame = true;
          printf("Refreshing every frame\n");
          break;
        case SDLK_6:
          gRefreshLimit = REFRESH_FRAME*3;
          gSyncLine = true;
          gSyncFrame = true;
          printf("Refreshing every 3 frames\n");
          break;
        case SDLK_SLASH:
          gAnimateRegisters = !gAnimateRegisters;
          printf("Funky register animation is %s\n", gAnimateRegisters ? "ON" : "off");
          break;
        case SDLK_BACKSLASH:
          gInfiniteHeight = !gInfiniteHeight;
          printf("Infinite height is %s\n", gInfiniteHeight ? "ON" : "off");
          break;
        case SDLK_v:
          TB->log_vsync = !TB->log_vsync;
          printf("Logging VSYNC %s\n", TB->log_vsync ? "enabled" : "disabled");
          break;
        case SDLK_KP_PLUS:
          printf("gRefreshLimit increased to %d\n", gRefreshLimit+=1000);
          break;
        case SDLK_KP_MINUS:
          printf("gRefreshLimit decreated to %d\n", gRefreshLimit-=1000);
          break;
        case SDLK_x: // eXamine: Pause as soon as a frame is detected with any tone generation.
          TB->examine_mode = !TB->examine_mode;
          if (TB->examine_mode) {
            printf("Examine mode ON\n");
            TB->examine_condition_met = false;
          }
          else {
            printf("Examine mode off\n");
          }
          break;
        case SDLK_PAGEDOWN:
          scale_motion_multiplier(0.909091); // Deduct 10%
          break;
        case SDLK_PAGEUP:
          scale_motion_multiplier(1.1); // Add 10%
          break;
        case SDLK_i:
          // Inspect: Print out current vector data as C++ code:
          printf("\nInspection not implemented.\n");
          // printf("\n// Vectors inspection data:\n");
          // uint32_t v;
          // v=TB->m_core->DESIGN->playerX; printf("TB->m_core->DESIGN->playerX = 0x%08X; // %lf\n", v, fixed2double(v));
          // // ...
          // printf("\n");
          if (KMOD_SHIFT & e.key.keysym.mod) {
            // Shift key held, so pause too.
            TB->pause(true);
          }
          break;
        case SDLK_s: // Step-examine, basically the same as hitting X then P while already paused.
          TB->examine_mode = true;
          TB->examine_condition_met = false;
          TB->pause(false); // Unpause.
          break;
        case SDLK_p:
          gRotateView = !gRotateView;
          printf("View is%s rotated\n", gRotateView ? "" : " NOT");
          break;
        case SDLK_y:
          gMouseYTexV = !gMouseYTexV;
          printf("Mouse Y controls TexV: %s\n", gMouseYTexV ? "ON" : "off");
          break;
        case SDLK_f:
          printf("Stepping by 1 frame is not yet implemented!\n");
          break;
        case SDLK_KP_8: gMapDX += 1; printf("gMapDX=%d\n", gMapDX); break;
        case SDLK_KP_2: gMapDX -= 1; printf("gMapDX=%d\n", gMapDX); break;
        case SDLK_KP_6: gMapDY += 1; printf("gMapDY=%d\n", gMapDY); break;
        case SDLK_KP_4: gMapDY -= 1; printf("gMapDY=%d\n", gMapDY); break;
        case SDLK_o:
          gSwapMouseXY = !gSwapMouseXY;
          printf("Mouse axes are%s swapped\n", gSwapMouseXY ? "" : " NOT");
          break;
        // Turn off all input locks:
        case SDLK_END:    memset(&gLockInputs, 0, sizeof(gLockInputs)); break;

        default:

          if (KMOD_CTRL & e.key.keysym.mod) {
            // CTRL+arrow means we want to apply scaling to facing or vplane vectors:
            bool hit = true;
            switch (e.key.keysym.sym) {
              case SDLK_UP:     gView.sf += 0.01; if (gView.sf > 1.99) gView.sf = 1.99; break;
              case SDLK_DOWN:   gView.sf -= 0.01; if (gView.sf < 0.01) gView.sf = 0.01; break;
              case SDLK_RIGHT:  gView.sv += 0.01; if (gView.sv > 1.99) gView.sv = 1.99; break;
              case SDLK_LEFT:   gView.sv -= 0.01; if (gView.sv < 0.01) gView.sv = 0.01; break;
              default:
                hit = false;
                break;
            }
            if (hit) {
              printf("Vector scaling: sf = %5.2f  sv = %5.2f\n", gView.sf, gView.sv);
            }
          }
          
          // The following keys are treated differently depending on whether we're in gOverrideVectors mode or not:
          if (gOverrideVectors) {
            // Override Vectors mode: Let the sim directly set our player position and viewpoint.
            //NOTE: Nothing to do here: handle_control_inputs will take care of it.
          }
          else {
            // Not in Override Vectors mode; let the design handle motion.
            switch (e.key.keysym.sym) {
              case SDLK_BACKQUOTE:  //NOTE: As a scancode, the backtick is SDL_SCANCODE_GRAVE.
                                    gLockInputs[LOCK_DEBUG] ^= 1; break;
              case SDLK_INSERT:     gLockInputs[LOCK_MAP] ^= 1; break;
              case SDLK_t:          gLockInputs[LOCK_TRACE] ^= 1; break;
#ifdef DESIGN_DIRECT_VECTOR_ACCESS
              // Toggle direction inputs (and turn off any that are opposing):
              case SDLK_UP:     if (KMOD_SHIFT & e.key.keysym.mod) TB->m_core->moveF=1; else if( (gLockInputs[LOCK_F] ^= 1) ) gLockInputs[LOCK_B] = false; break;
              case SDLK_DOWN:   if (KMOD_SHIFT & e.key.keysym.mod) TB->m_core->moveB=1; else if( (gLockInputs[LOCK_B] ^= 1) ) gLockInputs[LOCK_F] = false; break;
              case SDLK_LEFT:   if (KMOD_SHIFT & e.key.keysym.mod) TB->m_core->moveL=1; else if( (gLockInputs[LOCK_L] ^= 1) ) gLockInputs[LOCK_R] = false; break;
              case SDLK_RIGHT:  if (KMOD_SHIFT & e.key.keysym.mod) TB->m_core->moveR=1; else if( (gLockInputs[LOCK_R] ^= 1) ) gLockInputs[LOCK_L] = false; break;
              // NOTE: If SHIFT is held, send momentary (1-frame) signal inputs instead of locks.
              //SMELL: This won't work if we're calling handle_control_inputs more often than once per frame...?
#else//!DESIGN_DIRECT_VECTOR_ACCESS
              #warning SPI vector access not yet implemented
#endif//DESIGN_DIRECT_VECTOR_ACCESS
            }
          }
          break;
      }
    }
  }
}


void rotate_view(double a) {
  double nx, ny;
  double ca = cos(a);
  double sa = sin(a);
  // Rotate direction vector:
  nx =  gView.fx*ca + gView.fy*sa;
  ny = -gView.fx*sa + gView.fy*ca;
  gView.fx = nx;
  gView.fy = ny;
  // Rotate viewplane vector:
  nx =  gView.vx*ca + gView.vy*sa;
  ny = -gView.vx*sa + gView.vy*ca;
  gView.vx = nx;
  gView.vy = ny;
}



void recalc_view(const Uint8* k, int mouseX, int mouseY, double t) {
  //SMELL: Actual travel distance should be based on time elapsed, which will require an extra argument.
  const double key_rotate_speed   = 0.01;
  double mouse_rotate_speed = 0.001;
  const double move_quantum       = pow(2.0, -9.0); // This borrows from `playerMove` in the design, and in Q10.10 it is the raw value: 2
  const double playerCrawl        = move_quantum *  4.0;
  const double playerWalk         = move_quantum * 10.0; // Should be 0.01953125
  const double playerRun          = move_quantum * 18.0;
  const double playerMove         = playerWalk;
  bool slow = k[SDL_SCANCODE_LALT];
  bool fast = k[SDL_SCANCODE_LSHIFT];
  int mouseDelta = gSwapMouseXY ? mouseY : mouseX;
  double m =  slow ?  playerCrawl :
              fast ?  playerRun :
                      playerMove;
  m *= gMotionMultiplier * t;
  double r = key_rotate_speed;
  r *= gMotionMultiplier;
  if (slow) {
    // When ALT key is held, scale motion AND mouse rotation speed to 40%.
    r *= 0.4;
    mouse_rotate_speed *= 0.4;
  }
  else if (fast)
  {
    // When SHIFT key is held, scale motion speed to 180%.
    r *= 1.8;
  }
  if (!k[SDL_SCANCODE_LCTRL] && !k[SDL_SCANCODE_RCTRL]) { // Ignore arrows if CTRL is held (because it's used for vector scaling control).
    if (k[SDL_SCANCODE_LEFT])   rotate_view( r);
    if (k[SDL_SCANCODE_RIGHT])  rotate_view(-r);
  }
  if (mouseDelta != 0)        rotate_view(-mouse_rotate_speed * double(mouseDelta));
  if (k[SDL_SCANCODE_W]) { gView.px += m * gView.fx;   gView.py += m * gView.fy; }
  if (k[SDL_SCANCODE_S]) { gView.px -= m * gView.fx;   gView.py -= m * gView.fy; }
  if (gMouseYTexV) {
    int delta = gSwapMouseXY ? mouseX : mouseY;
    gTexVShift += (gSwapMouseXY ? 1 : -1) * delta;
  }
  if (gSwapMouseXY) {
    // A/D slide gTexVShift to create illusion of moving left/right IF using infinite height mode.
    if (k[SDL_SCANCODE_A]) { gTexVShift -= int(10.0*t); }
    if (k[SDL_SCANCODE_D]) { gTexVShift += int(10.0*t); }
  }
  else {
    if (k[SDL_SCANCODE_A]) { gView.px -= m * gView.vx;   gView.py -= m * gView.vy; }
    if (k[SDL_SCANCODE_D]) { gView.px += m * gView.vx;   gView.py += m * gView.vy; }
  }
}


//NOTE: handle_control_inputs is called twice; once with `true` before process_sdl_events, then once after with `false`.
void handle_control_inputs(bool prepare, double t) {
  if (prepare) {
    // PREPARE mode: Clear all inputs, so process_sdl_events has a chance to preset MOMENTARY inputs:
    TB->m_core->reset     = 0;
  #ifdef DESIGN_DIRECT_VECTOR_ACCESS
      TB->m_core->show_map  = 0;
      TB->m_core->moveF     = 0;
      TB->m_core->moveL     = 0;
      TB->m_core->moveB     = 0;
      TB->m_core->moveR     = 0;
  #else//!DESIGN_DIRECT_VECTOR_ACCESS
      #warning SPI vector access not yet implemented
  #endif//DESIGN_DIRECT_VECTOR_ACCESS

#ifdef DEBUG_BUTTON_INPUTS
    TB->m_core->debugA    = 0;
    TB->m_core->debugB    = 0;
    TB->m_core->debugC    = 0;
    TB->m_core->debugD    = 0;
#endif // DEBUG_BUTTON_INPUTS
  }
  else {

    int mouseX, mouseY;
    if (gMouseCapture) {
      uint32_t buttons = SDL_GetRelativeMouseState(&mouseX, &mouseY);
      gMouseX += mouseX;
      gMouseY += mouseY;
      // printf("\t\t\t\t\t\t\t\t\t\tMouse motion: %6d, %6d\tGlobal pos: %7d, %7d\n", mouseX, mouseY, gMouseX, gMouseY);
    } else {
      mouseX = 0;
      mouseY = 0;
    }

    // ACTIVE mode: Read the momentary state of all keyboard keys, and add them via `|=` to whatever is already asserted:
    auto keystate = SDL_GetKeyboardState(NULL);

    recalc_view(keystate, mouseX, mouseY, t);

    // TB->m_core->show_debug = 1;
    TB->m_core->reset     |= keystate[SDL_SCANCODE_R];
    TB->m_core->i_debug_v  = gLockInputs[LOCK_DEBUG]; // Toggle lock with backtick (`)
    TB->m_core->i_debug_m  = gLockInputs[LOCK_MAP] |  keystate[SDL_SCANCODE_TAB ]; // Toggle lock with INSERT key.
    TB->m_core->i_debug_t  = gLockInputs[LOCK_TRACE]; // Toggle lock with T key.
    TB->m_core->i_inc_px   =                          keystate[SDL_SCANCODE_LEFTBRACKET];
    TB->m_core->i_inc_py   =                          keystate[SDL_SCANCODE_RIGHTBRACKET];
    TB->m_core->i_gen_tex  = gGenTex;

    #ifdef DESIGN_DIRECT_VECTOR_ACCESS
      TB->m_core->moveF     |= keystate[SDL_SCANCODE_W   ] | gLockInputs[LOCK_F];
      TB->m_core->moveL     |= keystate[SDL_SCANCODE_A   ] | gLockInputs[LOCK_L];
      TB->m_core->moveB     |= keystate[SDL_SCANCODE_S   ] | gLockInputs[LOCK_B];
      TB->m_core->moveR     |= keystate[SDL_SCANCODE_D   ] | gLockInputs[LOCK_R];
    #else//!DESIGN_DIRECT_VECTOR_ACCESS
      #warning SPI vector access not yet implemented
    #endif//DESIGN_DIRECT_VECTOR_ACCESS

#ifdef DEBUG_BUTTON_INPUTS
    TB->m_core->debugA    |= keystate[SDL_SCANCODE_KP_4];
    TB->m_core->debugB    |= keystate[SDL_SCANCODE_KP_6];
    TB->m_core->debugC    |= keystate[SDL_SCANCODE_KP_2];
    TB->m_core->debugD    |= keystate[SDL_SCANCODE_KP_8];
#endif // DEBUG_BUTTON_INPUTS
  }
}



void check_performance() {
  uint32_t time_now = SDL_GetTicks();
  uint32_t time_delta = time_now-gPrevTime;

  if (time_delta >= 1000) {
    // 1S+ has elapsed, so print FPS:
    printf("Current FPS: %5.2f", float(TB->frame_counter-gPrevFrames)/float(time_delta)*1000.0f);
    // Estimate clock speed based on delta of m_tickcount:
    //SMELL: This code is really weird because for some bizarre reason I was getting mixed results
    // between Windows and Linux builds. It was as though sometimes on Windows it was treating a
    // LONG as a 32-bit integer, especially when doing *1000L
    long a = gPrevTickCount;
    long b = TB->m_tickcount;
    long c = (b-a);
    long d = time_delta;
    long hz = c / d;
    hz *= 1000L;
    // Now print long-term average:
    printf(" - Total average FPS: %5.2f", float(TB->frame_counter)/float(time_now-gOriginalTime)*1000.0f);
    // printf(" - a=%ld b=%ld c=%ld, d=%ld, hz=%ld", a, b, c, d, hz);
    printf(" - m_tickcount=");
    TB->print_big_num(TB->m_tickcount);
    printf(" (");
    TB->print_big_num(hz);
    printf(" Hz; %3ld%% of target)\n", (hz*100)/CLOCK_HZ);
    gPrevTime = SDL_GetTicks();
    gPrevFrames = TB->frame_counter;
    gPrevTickCount = TB->m_tickcount;
  }
}



void clear_freshness(uint8_t *fb) {
  // If we're not refreshing at least one full frame at a time,
  // then clear the "freshness" of pixels that haven't been updated.
  // We make this conditional in the hopes of getting extra speed
  // for higher refresh rates.
  // if (gRefreshLimit < REFRESH_FRAME) {
    // In this simulation, the 6 lower bits of each colour channel
    // are not driven by the design, and so we instead use them to
    // help visualise what region of the framebuffer has been updated
    // between SDL window refreshes (by the rendering loop forcing them on,
    // which appears as a slight brightening).
    // THIS loop clears all that between refreshes:
    for (int x = 0; x < HFULL; ++x) {
      for (int y = 0; y < VFULL; ++y) {
        fb[(x+y*WINDOW_WIDTH)*4 + 0] &= ~HILITE;
        fb[(x+y*WINDOW_WIDTH)*4 + 1] &= ~HILITE;
        fb[(x+y*WINDOW_WIDTH)*4 + 2] &= ~HILITE;
      }
    }
  // }
}

void overlay_display_area_frame(uint8_t *fb, int h_shift = 0, int v_shift = 0) {
  // if (!gGuides) return;
  // Vertical range: Horizontal lines (top and bottom):
  if (v_shift > 0) {
    for (int x = 0; x < WINDOW_WIDTH; ++x) {
      fb[(x+(v_shift-1)*WINDOW_WIDTH)*4 + 0] |= 0b0100'0000;
      fb[(x+(v_shift-1)*WINDOW_WIDTH)*4 + 1] |= 0b0100'0000;
      fb[(x+(v_shift-1)*WINDOW_WIDTH)*4 + 2] |= 0b0100'0000;
    }
  }
  if (v_shift+VDA < WINDOW_HEIGHT) {
    for (int x = 0; x < WINDOW_WIDTH; ++x) {
      fb[(x+(VDA+v_shift)*WINDOW_WIDTH)*4 + 0] |= 0b0100'0000;
      fb[(x+(VDA+v_shift)*WINDOW_WIDTH)*4 + 1] |= 0b0100'0000;
      fb[(x+(VDA+v_shift)*WINDOW_WIDTH)*4 + 2] |= 0b0100'0000;
    }
  }
  // Horizontal range: Vertical lines (left and right sides):
  if (h_shift > 0) {
    for (int y = 0; y < WINDOW_HEIGHT; ++y) {
      fb[(h_shift-1+y*WINDOW_WIDTH)*4 + 0] |= 0b0100'0000;
      fb[(h_shift-1+y*WINDOW_WIDTH)*4 + 1] |= 0b0100'0000;
      fb[(h_shift-1+y*WINDOW_WIDTH)*4 + 2] |= 0b0100'0000;
    }
  }
  if (h_shift+HDA < WINDOW_WIDTH) {
    for (int y = 0; y < WINDOW_HEIGHT; ++y) {
      fb[(HDA+h_shift+y*WINDOW_WIDTH)*4 + 0] |= 0b0100'0000;
      fb[(HDA+h_shift+y*WINDOW_WIDTH)*4 + 1] |= 0b0100'0000;
      fb[(HDA+h_shift+y*WINDOW_WIDTH)*4 + 2] |= 0b0100'0000;
    }
  }
  // Guides:
  if (gGuides) {
    // Mid-screen vertical line:
    for (int y = 0; y < WINDOW_HEIGHT; ++y) {
        fb[(HDA/2+h_shift+y*WINDOW_WIDTH)*4 + 0] |= 0b0110'0000;
        fb[(HDA/2+h_shift+y*WINDOW_WIDTH)*4 + 1] |= 0b0110'0000;
        fb[(HDA/2+h_shift+y*WINDOW_WIDTH)*4 + 2] |= 0b0110'0000;
    }
    // Mouse crosshairs:
    // X axis, vertical line:
    int mx = gMouseX + HDA/2;
    int my = gMouseY + VDA/2;
    if (mx >= 0 && mx < HDA) {
      for (int y = 0; y < WINDOW_HEIGHT; ++y) {
          fb[(mx+h_shift+y*WINDOW_WIDTH)*4 + 0] |= 0b0110'0000;
          fb[(mx+h_shift+y*WINDOW_WIDTH)*4 + 1] |= 0b0110'0000;
          fb[(mx+h_shift+y*WINDOW_WIDTH)*4 + 2] |= 0b0110'0000;
      }
    }
    if (my >= 0 && my < VDA) {
      for (int x = 0; x < WINDOW_WIDTH; ++x) {
          fb[(x+(my+v_shift)*WINDOW_WIDTH)*4 + 0] |= 0b0110'0000;
          fb[(x+(my+v_shift)*WINDOW_WIDTH)*4 + 1] |= 0b0110'0000;
          fb[(x+(my+v_shift)*WINDOW_WIDTH)*4 + 2] |= 0b0110'0000;
      }
    }
  }
}


void fade_overflow_region(uint8_t *fb) {
  for (int x = HFULL; x < WINDOW_WIDTH; ++x) {
    for (int y = 0 ; y < VFULL; ++y) {
      fb[(x+y*WINDOW_WIDTH)*4 + 0] *= 0.95;
      fb[(x+y*WINDOW_WIDTH)*4 + 1] *= 0.95;
      fb[(x+y*WINDOW_WIDTH)*4 + 2] *= 0.95;
    }
  }
  for (int x = 0; x < WINDOW_WIDTH; ++x) {
    for (int y = VFULL; y < WINDOW_HEIGHT; ++y) {
      fb[(x+y*WINDOW_WIDTH)*4 + 0] *= 0.95;
      fb[(x+y*WINDOW_WIDTH)*4 + 1] *= 0.95;
      fb[(x+y*WINDOW_WIDTH)*4 + 2] *= 0.95;
    }
  }
}


void overflow_test(uint8_t *fb) {
  for (int x = HFULL; x < WINDOW_WIDTH; ++x) {
    for (int y = 0 ; y < VFULL; ++y) {
      fb[(x+y*WINDOW_WIDTH)*4 + 0] = 50;
      fb[(x+y*WINDOW_WIDTH)*4 + 1] = 150;
      fb[(x+y*WINDOW_WIDTH)*4 + 2] = 255;
    }
  }
  for (int x = 0; x < WINDOW_WIDTH; ++x) {
    for (int y = VFULL; y < WINDOW_HEIGHT; ++y) {
      fb[(x+y*WINDOW_WIDTH)*4 + 0] = 50;
      fb[(x+y*WINDOW_WIDTH)*4 + 1] = 150;
      fb[(x+y*WINDOW_WIDTH)*4 + 2] = 255;
    }
  }
}



void render_text(SDL_Renderer* renderer, TTF_Font* font, int x, int y, string s) {
  SDL_Rect r;
  SDL_Texture* tex;
  get_text_and_rect(renderer, x, y, s.c_str(), font, &tex, &r);
  if (tex) {
    SDL_RenderCopy(renderer, tex, NULL, &r);
    SDL_DestroyTexture(tex);
  }
}


void update_game_state() {
  static int frame = 0;
  if (gAnimateRegisters) {
    gColorSky   += 3; if (gColorSky>63)   gColorSky   -= 64;
    // gColorFloor = 0x20;
    gColorFloor += 5; if (gColorFloor>63) gColorFloor -= 64;
    ++frame;
    gLeak = 8 + int(8.0 * sin(double(frame)/10.0));
    // gTexVShift += 1;
  }
  else {
    gColorSky   = 0x15; //0b01_01_01;
    gColorFloor = 0x2A; //0b10_10_10;
    gLeak       = 0;
  }
}


enum {
  CMD_SKY = 0,
  CMD_FLOOR,
  CMD_LEAK,
  CMD_OTHER,
  CMD_VSHIFT,
  CMD_VINF,
  CMD_MAPD,
  CMD__MAX,
};


void push_bits_onto_stack(vector<bool>& bits, uint32_t data, int num_bits) {
  for (int i=num_bits-1; i>=0; --i) {
    bits.push_back(data & (1<<i));
  }
}


int update_spi_registers_state() {
  static int spi_next_countdown = 5; // For now run at one fifth of the clock. Later, we could add some jitter.
  static int spi_state_counter = 0; // Tracks which state we're up to, incrementing when spi_next_countdown==0.

  static vector<bool> bits;
  static bool frame_end = true;

  const int first_register = CMD_SKY;
  const int last_register = CMD__MAX-1;

  static int register_counter = first_register;

  static int hits = 0;

  //NOTE: States:
  // 0 = SS and SCLK deasserted.
  // 1 = SS asserted.
  // 2 = First MOSI + SCLK deasserted.
  // 3 = First MOSI + SCLK asserted.
  // Repeat above 2 states for remaining data bits.
  // Finally: SCLK deasserted; i.e. data_bits*2 + 2

  if (0 == --spi_next_countdown) {

    if (frame_end) {
      frame_end = false;
      spi_state_counter = 0;
    } else {
      ++spi_state_counter;
    }

    spi_next_countdown = 5 + (rand() % 5); // Add some jitter.
    switch (spi_state_counter) {
      case 0:
      {
        bits.clear();
        // Which register are we going to write to now?
        push_bits_onto_stack(bits, register_counter, 4);
        switch (register_counter) {
          case CMD_SKY:
            push_bits_onto_stack(bits, gColorSky, 6);
            break;
          case CMD_FLOOR:
            push_bits_onto_stack(bits, gColorFloor, 6);
            break;
          case CMD_LEAK:
            push_bits_onto_stack(bits, gLeak, 6);
            break;
          case CMD_OTHER:
            push_bits_onto_stack(bits, 0, 12); // For now, otherX/Y is hard-coded to 0.
            break;
          case CMD_VSHIFT:
            push_bits_onto_stack(bits, gTexVShift / 10, 6);
            break;
          case CMD_VINF:
            push_bits_onto_stack(bits, gInfiniteHeight, 1);
            break;
          case CMD_MAPD:
            push_bits_onto_stack(bits, gMapDX, 6);
            push_bits_onto_stack(bits, gMapDY, 6);
            push_bits_onto_stack(bits, gMapDXW, 2);
            push_bits_onto_stack(bits, gMapDYW, 2);
            break;
          default:
            printf("ERROR: Unknown register: %d\n", register_counter);
            break;
        }
        // Get SPI inputs ready; start off with both deasserted:
        TB->m_core->i_reg_ss_n = 1; // Deasserted.
        TB->m_core->i_reg_sclk = 0; // Deasserted.
        break;
      }
      case 1:
      {
        // Assert /SS:
        TB->m_core->i_reg_ss_n = 0; // Asserted.
        break;
      }
      default:
      {
        // Get a bit.
        int bit_index = (spi_state_counter>>1)-1;
        if (bit_index < bits.size()) {
          // Present the bit at MOSI:
          TB->m_core->i_reg_mosi = bits[bit_index];
          if (0==(spi_state_counter&1)) {
            // Deassert SCLK.
            TB->m_core->i_reg_sclk = 0;
          } else {
            // Assert SCLK.
            TB->m_core->i_reg_sclk = 1;
          }
        } else  {
          // No bits left.
          // Deassert SCLK one last time:
          TB->m_core->i_reg_sclk = 0; // Deasserted.
          frame_end = true;

          // Select the next register for our next loop:

          if (register_counter++ >= last_register) {
            // Go back to start.
            register_counter = first_register;
            // Set spi_next_countdown to a big number to inject a pause:
            spi_next_countdown = 1000 + (rand() % 1000);
          }

        }
        break;
      }
    }
    hits++;
    // if (hits>81900 && hits<83000) {
    //   printf("Hits:%d\tEnd:%d\tStep:%d\t/SS:%d\tCLK:%d\tMOSI:%d\n",
    //     hits,
    //     frame_end,
    //     spi_state_counter,
    //     TB->m_core->i_reg_ss_n,
    //     TB->m_core->i_reg_sclk,
    //     TB->m_core->i_reg_mosi
    //   );
    // }
  }
  return hits;

}



// This gets called right next to every TB->tick() call.
// It has its own counters to keep track of when to update SPI inputs to TB.
// Currently it's designed to constantly stream in the current vector states
// via SPI, even if they haven't updated. However, it does need to take a
// snapshot of the current vector states when starting each new streaming
// (because they could otherwise be changing):
void update_spi_state() {
  static int spi_next_countdown = 5; // For now run at one fifth of the clock. Later, we could add some jitter.
  static int spi_state_counter = 0; // Tracks which state we're up to, incrementing when spi_next_countdown==0.

  static vector<bool> bits;

  //NOTE: States:
  // 0 = SS and SCLK deasserted.
  // 1 = SS asserted.
  // 2 = First MOSI + SCLK deasserted.
  // 3 = First MOSI + SCLK asserted.
  // Repeat above 2 states for remaining 73 bits (up to states 148 and 149)
  // 150 = SCLK deasserted; i.e. 74*2 + 2
  if (0 == --spi_next_countdown) {
    spi_next_countdown = 5 + (rand() % 5); // Jitter.
    switch (spi_state_counter) {
      case 0:
      {
        // Take a snapshot of gView now, converting vectors into the SPI bit stream:
        int p;
        uint32_t v;
        bits.clear();
        for (int i=0; i<74; ++i) {
          switch (i) {
            case 0:   v = double2fixed(gView.px           ); p = Qn+5; break;
            case 15:  v = double2fixed(gView.py           ); p = Qn+5; break;
            case 30:  v = double2fixed(gView.fx * gView.sf); p = Qn+1; break;
            case 41:  v = double2fixed(gView.fy * gView.sf); p = Qn+1; break;
            case 52:  v = double2fixed(gView.vx * gView.sv); p = Qn+1; break;
            case 63:  v = double2fixed(gView.vy * gView.sv); p = Qn+1; break;
          }
          bits.push_back(v & (1<<p));
          --p;
        }
        // Get SPI inputs ready:
        TB->m_core->i_ss_n = 1; // Deasserted.
        TB->m_core->i_sclk = 0; // Deasserted.
        break;
      }
      case 1:
      {
        TB->m_core->i_ss_n = 0; // Asserted.
        break;
      }
      case 150:
      {
        TB->m_core->i_sclk = 0; // Deasserted.
        break;
      }
      default:
      {
        // Get a bit.
        int bit_index = (spi_state_counter>>1)-1;
        TB->m_core->i_mosi = bits[bit_index];
        if (spi_state_counter&1) {
          // Assert SCLK.
          TB->m_core->i_sclk = 1;
        }
        else {
          // Deassert SCLK.
          TB->m_core->i_sclk = 0;
        }
        break;
      }
    }
    if (151 == ++spi_state_counter) {
      spi_state_counter = 0;
    }
  }
}



int main(int argc, char **argv) {

  printf("DEBUG: main() command-line arguments:\n");
  for (int i = 0; i < argc; ++i) {
    printf("%d: [%s]\n", i, argv[i]);
  }

  Verilated::commandArgs(argc, argv);
  // Verilated::traceEverOn(true);
  
  TB = new MAIN_TB();
#ifdef USE_POWER_PINS
  #pragma message "Howdy! This simulation build has USE_POWER_PINS in effect"
  TB->m_core->VGND = 0;
  TB->m_core->VPWR = 1;
#else
  #pragma message "Oh hi! USE_POWER_PINS is not in effect for this simulation build"
#endif
  uint8_t *framebuffer = new uint8_t[FRAMEBUFFER_SIZE];

  //SMELL: This needs proper error handling!
  printf("SDL_InitSubSystem(SDL_INIT_VIDEO): %d\n", SDL_InitSubSystem(SDL_INIT_VIDEO));

  SDL_Window* window =
      SDL_CreateWindow(
          " Verilator VGA simulation: " S2(VDESIGN),
          SDL_WINDOWPOS_UNDEFINED, SDL_WINDOWPOS_UNDEFINED,
          WINDOW_WIDTH, WINDOW_WIDTH,//WINDOW_HEIGHT,
          0
      );
  SDL_Renderer* renderer =
      SDL_CreateRenderer(
          window,
          -1,
          SDL_RENDERER_ACCELERATED
      );

  toggle_mouse_capture(true, gMouseCapture); // Dummy "toggle" to just set current mode, in order to print it.

  TTF_Init();
  TTF_Font *font = TTF_OpenFont(FONT_FILE, 12);
  if (!font) {
#if __cplusplus == 201703L
    std::filesystem::path font_path = std::filesystem::absolute(FONT_FILE);
#else
    string font_path = FONT_FILE;
#endif
    printf(
      "WARNING: Cannot load default font. Text rendering will be disabled.\n"
      "-- Looking for: %s\n",
      font_path.c_str()
    );
  }
  else {
    printf("Font loaded.\n");
  }

  //SMELL: This isn't actually used anymore because now the ROM data is embedded in the Verilog:
  // load_texture_rom("assets/blue-wall-222.png");
  //SMELL: Image conversion should now be done when needed with utils/asset_tool:
  // convert_image_rom_png_to_hex("assets/Wolf3D-guard-sprite-RGB222.png", "assets/sprite-xrgb-2222.hex", 64, 64);
  
  SDL_SetRenderDrawColor(renderer, 0, 0, 0, SDL_ALPHA_OPAQUE);
  SDL_RenderClear(renderer);
  SDL_Texture* texture =
      SDL_CreateTexture(
          renderer,
          SDL_PIXELFORMAT_ARGB8888,
          SDL_TEXTUREACCESS_STREAMING,
          WINDOW_WIDTH, WINDOW_HEIGHT
      );

  printf(
    "\n"
    "Target clock speed: "
  );
  TB->print_big_num(CLOCK_HZ);
  printf(" Hz\n");

#ifdef INSPECT_INTERNAL
  printf(
    "\n"
    "Initial state of design:\n"
    "  playerX  : %d\n"
    "  playerY  : %d\n"
    "  facingX  : %d\n"
    "  facingY  : %d\n"
    "  vplaneX  : %d\n"
    "  vplaneY  : %d\n"
    "\n",
    TB->m_core->DESIGN->playerX,
    TB->m_core->DESIGN->playerY,
    TB->m_core->DESIGN->facingX,
    TB->m_core->DESIGN->facingY,
    TB->m_core->DESIGN->vplaneX,
    TB->m_core->DESIGN->vplaneY
  );
#endif


  // printf("Starting simulation in ");
  // for (int c=3; c>0; --c) {
  //   printf("%i... ", c);
  //   fflush(stdout);
  //   sleep(1);
  // }
  printf("Cold start...\n");

  printf("------ NOTE: SPI transmissions are %s. Press E key to toggle.\n", gEnableSPI ? "ENABLED" : "disabled");

  int h = 0;
  int v = 0;

  printf("Main loop...\n");

  gOriginalTime = gPrevTime = SDL_GetTicks();
  gPrevTickCount = TB->m_tickcount; // Used for measuring simulated clock speed.
  gPrevFrames = 0; // Used for calculating frame rate.
  Uint32 last_time = SDL_GetTicks(); // Used for calculating motion.

  bool count_hbp = false;
  int hbp_counter = 0; // Counter for timing the HBP (i.e. time after HSP, but before HDA).
  int h_adjust = HBP*2; // Amount to count in hbp_counter. Start at a high value and then sync back down.
  int h_adjust_countdown = REFRESH_FRAME*2;
  int v_shift = VBP*2; // This will try to find the vertical start of the image.

  while (!gQuit) {
    if (TB->done()) gQuit = true;
    if (TB->paused) SDL_WaitEvent(NULL); // If we're paused, an event is needed before we could resume.

    handle_control_inputs(true, 0); // true = PREPARE mode; set default signal inputs, so process_sdl_events can OPTIONALLY override.
    //SMELL: Should we do handle_control_inputs(true) only when we detect the start of a new frame,
    // so as to preserve/capture any keys that were pressed across *partial* refreshes?
    process_sdl_events();
    if (gQuit) break;
    if (TB->paused) continue;

    int old_reset = TB->m_core->reset;
    int time_delta = SDL_GetTicks() - last_time;
    last_time = SDL_GetTicks();
    handle_control_inputs(false, (double(time_delta)/1000.0)*60.0); // false = ACTIVE mode; add in actual HID=>signal input changes.
    update_game_state();
    if (old_reset != TB->m_core->reset) {
      // Reset state changed, so we probably need to resync:
      h_adjust = HBP*2;
      count_hbp = false;
      hbp_counter = 0; // Counter for timing the HBP (i.e. time after HSP, but before HDA).
      h_adjust = HBP*2; // Amount to count in hbp_counter. Start at a high value and then sync back down.
      h_adjust_countdown = REFRESH_FRAME*2;
      v_shift = VBP*2; // This will try to find the vertical start of the image.
    }

    check_performance();

    clear_freshness(framebuffer);

    //SMELL: In my RTL, I call the time that comes before the horizontal display area the BACK porch,
    // even though arguably it comes first (so surely should be the FRONT), but this swapped naming
    // comes from other charts and diagrams I was reading online at the time.

    for (int i = 0; i < gRefreshLimit; ++i) {

      if (h_adjust_countdown > 0) --h_adjust_countdown;

      bool hsync_stopped = false;
      bool vsync_stopped = false;
      int hits = 0;
      if (gEnableSPI) {
        update_spi_state();
        hits = update_spi_registers_state();
      }
      TB->tick();      hsync_stopped |= TB->hsync_stopped();      vsync_stopped |= TB->vsync_stopped();

#ifdef USE_SPEAKER
      TB->examine_condition_met |= TB->m_core->speaker;
#endif // USE_SPEAKER

#ifdef DOUBLE_CLOCK
      TB->tick();      hsync_stopped |= TB->hsync_stopped();      vsync_stopped |= TB->vsync_stopped();
#ifdef USE_SPEAKER
      TB->examine_condition_met |= TB->m_core->speaker;
#endif // USE_SPEAKER
      // ^ We tick twice if the design halves the clock to produce the pixel clock.
#endif // DOUBLE_CLOCK

      if (hsync_stopped) {
        count_hbp = true;
        hbp_counter = 0;
      }

      // int pixel_lit = TB->m_core->red | TB->m_core->green | TB->m_core->blue;
      int pixel_lit = TB->m_core->rgb;

      if (count_hbp) {
        // We are counting the HBP before we start the next line.
        if (hbp_counter >= h_adjust) {
          // OK, counter ran out, so let's start our next line.
          count_hbp = false;
          hbp_counter = 0;
          h = 0;
          v++;
        }
        else if (pixel_lit) {
          // If we got here, we got a display signal earlier than the current
          // horizontal adjustment expects, so we need to adjust HBP to match
          // HDA video signal, but only after the first full frame:
          if (h_adjust_countdown <= 0) {
            h_adjust = hbp_counter;
            printf(
              "[H,V,F=%4d,%4d,%2d] "
              "Horizontal auto-adjust to %d after HSYNC\n",
              h, v, TB->frame_counter,
              h_adjust
            );
          }
        }
        else {
          h++;
          hbp_counter++;
        }
      }
      else {
        h++;
      }

      if (vsync_stopped) {
        // Start a new frame.
        v = 0;
        // if (TB->frame_counter%60 == 0) overflow_test(framebuffer);
        fade_overflow_region(framebuffer);
      }

      if (pixel_lit && h_adjust_countdown <= 0 && v < v_shift) {
        v_shift = v;
        printf(
          "[H,V,F=%4d,%4d,%2d] "
          "Vertical frame auto-shift to %d after VSYNC\n",
          h, v, TB->frame_counter,
          v_shift
        );
        gSyncLine = true;
        gSyncFrame = true;
      }

      int x = h;
      int y = v;

#ifdef USE_SPEAKER
      int speaker = (TB->m_core->speaker<<6);
#else
      int speaker = 0;
#endif // USE_SPEAKER
      int hilite = gHighlight ? HILITE : 0; // hilite turns on lower 5 bits to show which pixel(s) have been updated.

      if (x >= 0 && x < WINDOW_WIDTH && y >= 0 && y < WINDOW_HEIGHT) {


        int red   = ((TB->m_core->rgb & 0x03) << 6) | hilite;
        int green = ((TB->m_core->rgb & 0x0C) << 4) | hilite;
        int blue  = ((TB->m_core->rgb & 0x30) << 2) | hilite;
        // int red  = (TB->m_core->red   << 6) | hilite; // Design drives upper 2 bits of each colour channel.
        // int green= (TB->m_core->green << 6) | hilite; 
        // int blue = (TB->m_core->blue  << 6) | hilite; 
        framebuffer[(y*WINDOW_WIDTH + x)*4 + 2] = red   | (TB->m_core->hsync_n ? 0 : 0b1000'0000) | speaker;  // R
        framebuffer[(y*WINDOW_WIDTH + x)*4 + 1] = green;                                                    // G
        framebuffer[(y*WINDOW_WIDTH + x)*4 + 0] = blue  | (TB->m_core->vsync_n ? 0 : 0b1000'0000) | speaker;  // B.
      }

      if (gSyncLine && h==0) {
        gSyncLine = false;
        break;
      }

      if (gSyncFrame && v==0) {
        gSyncFrame = false;
        break;
      }

    }

    overlay_display_area_frame(framebuffer, 0, v_shift);

    SDL_UpdateTexture( texture, NULL, framebuffer, WINDOW_WIDTH * 4 );
    SDL_Rect dr;
    dr.x = 0; dr.y = 100;
    dr.w = WINDOW_WIDTH; dr.h = WINDOW_HEIGHT;
    SDL_SetRenderDrawColor(renderer, 0, 0, 0, 255);
    SDL_RenderFillRect(renderer, NULL);
    if (gRotateView) {
      // Rotated orientation.
      SDL_RenderCopyEx( renderer, texture, NULL, &dr, -90, NULL, SDL_FLIP_NONE );
    } else {
      // Normal orientation.
      SDL_RenderCopy( renderer, texture, NULL, &dr );
    }

// #ifdef INSPECT_INTERNAL
//     printf("%06X %06X %06X %06X %06X %06X\n",
//       TB->m_core->DESIGN->playerX,
//       TB->m_core->DESIGN->playerY,
//       TB->m_core->DESIGN->facingX,
//       TB->m_core->DESIGN->facingY,
//       TB->m_core->DESIGN->vplaneX,
//       TB->m_core->DESIGN->vplaneY
//     );
// #endif//INSPECT_INTERNAL
    if (font) {
      SDL_Rect rect;
      SDL_Texture *text_texture = NULL;
      // Show the state of controls that can be toggled:
      string s = "[";
      s += TB->paused           ? "P" : ".";
      s += gGuides              ? "G" : ".";
      s += gHighlight           ? "H" : ".";
      // s += TB->log_vsync        ? "V" : ".";
      // s += gOverrideVectors     ? "O" : ".";
      // s += TB->examine_mode     ? "X" : ".";
      s += gLockInputs[LOCK_MAP]? "m" : ".";
      s += gLockInputs[LOCK_DEBUG]? "D" : ".";
    #ifdef DESIGN_DIRECT_VECTOR_ACCESS
      s += gLockInputs[LOCK_L]  ? "<" : ".";
      s += gLockInputs[LOCK_F]  ? "^" : ".";
      s += gLockInputs[LOCK_B]  ? "v" : ".";
      s += gLockInputs[LOCK_R]  ? ">" : ".";
    #endif
      s += gMouseCapture        ? "*" : ".";
      s += gGenTex              ? "1" : "0";
      s += "] ";
#ifdef INSPECT_INTERNAL
      s += " pX,Y=("
        + to_string(fixed2double(TB->m_core->DESIGN->playerX)) + ", "
        + to_string(fixed2double(TB->m_core->DESIGN->playerY)) + ") ";
      s += " fX,Y=("
        + to_string(fixed2double(TB->m_core->DESIGN->facingX)) + ", "
        + to_string(fixed2double(TB->m_core->DESIGN->facingY)) + ") ";
      s += " vX,Y=("
        + to_string(fixed2double(TB->m_core->DESIGN->vplaneX)) + ", "
        + to_string(fixed2double(TB->m_core->DESIGN->vplaneY)) + ") ";
      s += " sf=" + to_string(gView.sf);
      s += " sv=" + to_string(gView.sv);
#endif//INSPECT_INTERNAL
      get_text_and_rect(renderer, 10, 10, s.c_str(), font, &text_texture, &rect);
      if (text_texture) {
        SDL_RenderCopy(renderer, text_texture, NULL, &rect);
        SDL_DestroyTexture(text_texture);
      }
      else {
        printf("Cannot create text_texture\n");
      }
    }
    SDL_RenderPresent(renderer);
  }

  SDL_DestroyRenderer(renderer);
  SDL_DestroyWindow(window);
  SDL_Quit(); //SMELL: Should use SDL_QuitSubSystem instead? https://wiki.libsdl.org/SDL2/SDL_QuitSubSystem
  if (font) TTF_CloseFont(font);
  TTF_Quit();

  delete framebuffer;

  printf("Done at %lu ticks.\n", TB->m_tickcount);
  return EXIT_SUCCESS;
}
