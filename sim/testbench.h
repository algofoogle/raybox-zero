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

// #define TRACE

#include "verilated.h"

#ifdef TRACE
#include <verilated_vcd_c.h>
#endif

template<class MODULE> class TESTBENCH {
public:
  static const int kClockPeriod = 20000; // 20,000pS clock period means 50MHz.
  static const int kClockEarly = 5000;   // We *affirm* a sample 5nS before raising the clock.
  unsigned long m_tickcount;
  MODULE *m_core;
#ifdef TRACE
  VerilatedVcdC *m_trace;
#endif

  TESTBENCH(void) {
#ifdef TRACE
    Verilated::traceEverOn(true);
#endif
    m_core = new MODULE;
    m_tickcount = 0l;
  }

  virtual ~TESTBENCH(void) {
    delete m_core;
    m_core = NULL;
  }

#ifdef TRACE
  virtual void opentrace(const char *vcdname) {
    if (!m_trace) {
      m_trace = new VerilatedVcdC;
      m_core->trace(m_trace, 99);
      m_trace->open(vcdname);
    }
  }

  virtual void closetrace(void) {
    if (m_trace) {
      m_trace->close();
      m_trace = NULL;
    }
  }
#endif

  virtual void reset(void) {
    m_core->reset = 1;
    // Make sure any inheritance gets applied
    this->tick();
    m_core->reset = 0;
  }

#ifdef TRACE
  virtual void trace(int stage) {
    if (!m_trace) return;
    switch (stage) {
      case -1:  m_trace->dump(kClockPeriod*m_tickcount-kClockEarly);  break;
      case 0:   m_trace->dump(kClockPeriod*m_tickcount);              break;
      case 1:   m_trace->dump(kClockPeriod*m_tickcount+kClockPeriod/2);
                m_trace->flush();
                break;
    }
  }
#endif

  virtual void tick(void) {
    // Increment our own internal time reference
    m_tickcount++;

    // Make sure any combinatorial logic depending upon
    // inputs that may have changed before we called tick()
    // has settled before the rising edge of the clock.
    m_core->clk = 0;
    m_core->eval();
#ifdef TRACE
    // Capture the state of things as they are a brief moment before we'll raise the clock:
    trace(-1);
#endif
    // Toggle the clock...

    // Rising edge
    m_core->clk = 1;
    m_core->eval();
#ifdef TRACE
    // Capture the result of the rising edge of the clock:
    trace(0);
#endif

    // Falling edge
    m_core->clk = 0;
    m_core->eval();
#ifdef TRACE
    trace(1);
#endif
  }

  virtual void print_time(void) {
    long ns = m_tickcount*kClockPeriod/1'000L; // kClockPeriod is in pS, so convert to nS.
    // printf("[%3lu,%03lu,%03lu,%03luns] ", ns/1'000'000'000L, (ns/1'000'000L)%1'000L, (ns/1'000L)%1'000L, ns%1'000L);
    printf("[");
    print_big_num(ns);
    printf("ns] ");
  }

  static void print_big_num(unsigned long ns) {
    printf("%3lu,%03lu,%03lu,%03lu", ns/1'000'000'000L, (ns/1'000'000L)%1'000L, (ns/1'000L)%1'000L, ns%1'000L);
  }

  virtual bool done(void) { return (Verilated::gotFinish()); }
};
