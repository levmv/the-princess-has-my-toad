#!/usr/bin/env bash
# Sourced only by explicit test/measurement tools, never the product build.
cc -c "$PROJECT_ROOT/bench/render/monitor_fallback.c" -o "$PROJECT_ROOT/build/monitor-fallback.o" -O2 -Wall -Wextra -Werror
LINK_FLAGS+=" $PROJECT_ROOT/build/monitor-fallback.o"
for query in VideoMode MonitorPos MonitorWorkarea MonitorPhysicalSize MonitorName Monitors; do
    LINK_FLAGS+=" -Wl,--wrap=glfwGet$query"
done
