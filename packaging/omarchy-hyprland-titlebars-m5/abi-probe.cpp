// SPDX-License-Identifier: MIT
// omarchy-m5p-oled: the layout of Monitor::CMonitor as the titlebars plugin is compiled to see it.
//
// Compiled (never linked or run) with the plugin's own flags. Each value is the size of an array,
// which `nm -S` prints, so nothing has to execute. The m_dsFailedClient line does not compile
// against stock Hyprland 0.57.2 headers: only hyprland-m5's CMonitor has that member.
#define WLR_USE_UNSTABLE
#include <hyprland/src/output/Monitor.hpp>

#include <cstddef>

#pragma GCC diagnostic ignored "-Winvalid-offsetof"

extern "C" {
char abi_sizeof_CMonitor[sizeof(Monitor::CMonitor)];
char abi_off_m_dsFailedClient[offsetof(Monitor::CMonitor, m_dsFailedClient)];
char abi_off_m_layerSurfaceLayers[offsetof(Monitor::CMonitor, m_layerSurfaceLayers)];
}
