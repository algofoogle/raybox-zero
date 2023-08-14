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

class MAIN_TB : public BASE_TB {
public:
  bool old_hsync;
  bool old_vsync;
  bool log_vsync;
  bool examine_mode;
  bool examine_condition_met;
  bool paused;
  int frame_counter;

  MAIN_TB(void) {
    log_vsync = false;
    examine_mode = false;
    examine_condition_met = false;
    paused = false;
    frame_counter = 0;
    old_hsync = false;
    old_vsync = false;
  }

  ~MAIN_TB() { }

  virtual bool hsync_asserted(void) { return 0 == m_core->hsync_n; }
  virtual bool vsync_asserted(void) { return 0 == m_core->vsync_n; }

  virtual bool hsync_started(void) { return 1 == old_hsync &&  hsync_asserted(); }
  virtual bool vsync_started(void) { return 1 == old_vsync &&  vsync_asserted(); }
  virtual bool hsync_stopped(void) { return 0 == old_hsync && !hsync_asserted(); }
  virtual bool vsync_stopped(void) { return 0 == old_vsync && !vsync_asserted(); }

  virtual void tick(void) {
    // if (paused) return;
    //SMELL: We don't respect 'paused' because it's more of a flag for the caller.
    // I've chosen to do it this way because I want the design itself to be able to
    // signal that it should pause, but leave it up to the simulator to decide
    // when to actually stop simulating.
    old_hsync = m_core->hsync_n;
    old_vsync = m_core->vsync_n;
    BASE_TB::tick();
    if (vsync_stopped()) {
      ++frame_counter;
      if (log_vsync) {
        print_time();
        printf("VSYNC released; starting frame %d.\n", frame_counter);
      }
      if (examine()) {
        pause(true);
        printf("(Examine condition met)\n");
        examine_condition_met = false;
        examine_mode = false; // Disable examine mode. User can turn it back on while we're paused, if they want.
      }
    }
  }

  virtual bool examine(void) {
    if (!examine_mode) return false;
    return examine_condition_met;
  }

  virtual bool pause(bool state) {
    bool old = paused;
    paused = state;
    if (old != paused) {
      print_time();
      printf("Simulation will %s\n", paused ? "pause" : "resume");
    }
    return old;
  }

};
