#!/usr/bin/env bash
# statusline-utils.sh -- Sourceable utility library for yolo-statusline.sh
# No side effects when sourced. All functions are pure (input->stdout).
# Portable: BSD sed (-E flag) + POSIX awk. Uses $'\x1b' for literal ESC.

# --- Width configuration (TD6) ---
MAX_WIDTH="${YOLO_MAX_WIDTH:-120}"

# Literal ESC character for portable sed (R4 mitigation)
ESC=$'\x1b'

# Bar width bounds
MIN_BAR=3
MAX_BAR=20

# --- strip_osc8_links() ---
# Replace OSC 8 hyperlinks with their visible text content (TD2 degradation).
# Pattern: ESC]8;params;URI ST visible_text ESC]8;; ST -> visible_text
# ST (String Terminator) = ESC \\ (0x1b 0x5c)
strip_osc8_links() {
  printf '%s' "$1" | sed -E "s/${ESC}\\]8;[^${ESC}]*${ESC}\\\\([^${ESC}]*)${ESC}\\]8;;${ESC}\\\\/\\1/g"
}

# --- strip_ansi() ---
# Strip ALL invisible escape sequences, returning visible-text-only string.
# Combines strip_osc8_links (extract hyperlink text) + CSI removal (TD1).
strip_ansi() {
  local no_osc8
  no_osc8=$(strip_osc8_links "$1")
  printf '%s' "$no_osc8" | sed -E "s/${ESC}\\[[0-9;]*[a-zA-Z]//g"
}

# --- visible_width() ---
# Return visible character count of a string with ANSI CSI and/or OSC 8.
# Algorithm (architecture component spec):
#   1. Strip OSC 8 wrappers keeping visible text (sed pass 1 via strip_osc8_links)
#   2. Strip all CSI sequences (sed pass 2 per TD1: ESC [ params final)
#   3. Count remaining chars: printf '%s' | wc -m | tr -d ' '
# Uses wc -m (character count) not wc -c (byte count) for UTF-8 safety.
visible_width() {
  local stripped
  stripped=$(strip_ansi "$1")
  printf '%s' "$stripped" | wc -m | tr -d ' '
}

# --- truncate_line() ---
# Truncate a string to at most max visible characters, preserving ANSI/OSC 8 integrity.
# Uses a fast path (visible_width check) and slow path (3-state awk parser per TD3).
# Appends \033[0m reset when truncation occurs. Closes open OSC 8 sequences.
# Usage: truncate_line "string" [max_width]
truncate_line() {
  local input="$1"
  local limit="${2:-$MAX_WIDTH}"

  # Fast path: if visible_width <= limit, return unchanged (skip awk)
  local w
  w=$(visible_width "$input")
  [ "$w" -le "$limit" ] && { printf '%s' "$input"; return; }

  # Slow path: awk 3-state parser
  printf '%s' "$input" | awk -v max="$limit" '
  BEGIN {
    ORS = ""
    state = 0  # 0=ground, 1=CSI, 2=OSC8
    vis = 0
    buf = ""
    done = 0
    saw_esc = 0  # Track whether any escape sequences were seen
  }
  {
    n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)

      if (done && state == 0) break

      if (state == 0) {
        # Ground state
        if (c == "\033") {
          saw_esc = 1
          # Check next char for CSI or OSC
          if (i < n) {
            nc = substr($0, i+1, 1)
            if (nc == "[") {
              state = 1  # Enter CSI
              buf = buf c
              continue
            } else if (nc == "]") {
              state = 2  # Enter OSC (likely OSC 8)
              buf = buf c
              continue
            }
          }
          buf = buf c  # Lone ESC, append
        } else {
          # Visible character
          if (vis < max) {
            buf = buf c
            vis++
          } else {
            done = 1
          }
        }
      } else if (state == 1) {
        # CSI state: accumulate until final byte [a-zA-Z]
        buf = buf c
        if (c ~ /[a-zA-Z]/) {
          state = 0  # CSI complete
        }
      } else if (state == 2) {
        # OSC8 state: accumulate until ST (ESC \\)
        buf = buf c
        if (c == "\\" && i >= 2 && substr($0, i-1, 1) == "\033") {
          state = 0  # ST reached, back to ground
        }
      }
    }
  }
  END {
    # If we truncated while inside OSC8, emit closing sequence
    if (state == 2) {
      buf = buf "\033]8;;\033\\"
    }
    # Append reset only when escape sequences are present (avoid polluting plain text)
    if (saw_esc && (done || state != 0)) {
      buf = buf "\033[0m"
    }
    print buf
  }'
}
