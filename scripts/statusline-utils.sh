#!/usr/bin/env bash
# statusline-utils.sh -- Sourceable utility library for yolo-statusline.sh
# No side effects when sourced. All functions are pure (input->stdout).
# Portable: BSD sed (-E flag) + POSIX awk. Uses $'\x1b' for literal ESC.

# --- Width configuration (TD6) ---
MAX_WIDTH="${YOLO_MAX_WIDTH:-120}"

# Literal ESC character for portable sed (R4 mitigation)
ESC=$'\x1b'
# BEL character (alternative OSC string terminator used by yolo-statusline.sh)
BEL=$'\x07'

# Bar width bounds
MIN_BAR=3
MAX_BAR=20

# --- strip_osc8_links() ---
# Replace OSC 8 hyperlinks with their visible text content (TD2 degradation).
# Pattern: ESC]8;params;URI ST visible_text ESC]8;; ST -> visible_text
# ST (String Terminator) = ESC \\ (0x1b 0x5c) or BEL (0x07)
strip_osc8_links() {
  # Handle both ESC\ and BEL as OSC string terminators.
  # LC_ALL=C required for macOS sed to handle raw ESC/BEL bytes.
  printf '%s' "$1" \
    | LC_ALL=C sed -E "s/${ESC}\\]8;[^${ESC}${BEL}]*${ESC}\\\\([^${ESC}${BEL}]*)${ESC}\\]8;;${ESC}\\\\/\\1/g" \
    | LC_ALL=C sed -E "s/${ESC}\\]8;[^${ESC}${BEL}]*${BEL}([^${ESC}${BEL}]*)${ESC}\\]8;;${BEL}/\\1/g"
}

# --- strip_ansi() ---
# Strip ALL invisible escape sequences, returning visible-text-only string.
# Combines strip_osc8_links (extract hyperlink text) + CSI removal (TD1).
strip_ansi() {
  local no_osc8
  no_osc8=$(strip_osc8_links "$1")
  printf '%s' "$no_osc8" | LC_ALL=C sed -E "s/${ESC}\\[[0-9;]*[a-zA-Z]//g"
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

  # Interpret \033 escape literals to real ESC bytes (yolo-statusline.sh uses
  # literal '\033[...' in variables; printf '%b' converts at output time).
  # We convert early so visible_width/awk can detect actual ESC bytes.
  # Normalize BEL (0x07) OSC terminators to ESC\ for consistent handling —
  # yolo-statusline.sh uses \a (BEL) in OSC 8 links; ESC\ is the canonical ST.
  local interpreted
  interpreted=$(printf '%b' "$input" | LC_ALL=C sed "s/${BEL}/${ESC}\\\\/g")

  # Fast path: if visible_width <= limit, return unchanged (skip awk)
  local w
  w=$(visible_width "$interpreted")
  [ "$w" -le "$limit" ] && { printf '%s' "$interpreted"; return; }

  # Slow path: LC_ALL=C awk 3-state parser (byte-mode with UTF-8 awareness).
  # Uses ord lookup table to detect UTF-8 lead bytes and consume continuation
  # bytes as a single visible character, preventing mid-character truncation.
  # Tracks in_link for semantic OSC 8 hyperlink state (opening/closing pairs).
  printf '%s' "$interpreted" | LC_ALL=C awk -v max="$limit" '
  BEGIN {
    ORS = ""
    # Build byte-value lookup table for UTF-8 detection
    for (_i = 0; _i < 256; _i++) _ord[sprintf("%c", _i)] = _i
    state = 0  # 0=ground, 1=CSI, 2=OSC8
    vis = 0
    buf = ""
    done = 0
    saw_esc = 0
    in_link = 0   # Semantic: inside an OSC 8 hyperlink (between open and close)
    osc_buf = ""  # Buffer to capture current OSC sequence content
  }
  {
    n = length($0)
    for (i = 1; i <= n; i++) {
      c = substr($0, i, 1)
      b = _ord[c]

      if (done && state == 0) break

      if (state == 0) {
        # Ground state
        if (b == 27) {
          # ESC byte
          saw_esc = 1
          if (i < n) {
            nc = substr($0, i+1, 1)
            if (nc == "[") { state = 1; buf = buf c; continue }
            else if (nc == "]") { state = 2; osc_buf = ""; buf = buf c; continue }
          }
          buf = buf c
        } else {
          # Visible character (ASCII or UTF-8)
          if (vis < max) {
            buf = buf c
            vis++
            # UTF-8: consume continuation bytes (0x80-0xBF) for multi-byte chars
            if (b >= 192 && b < 224) extra = 1
            else if (b >= 224 && b < 240) extra = 2
            else if (b >= 240 && b < 248) extra = 3
            else extra = 0
            for (k = 0; k < extra && i + 1 <= n; k++) {
              i++
              buf = buf substr($0, i, 1)
            }
          } else {
            done = 1
          }
        }
      } else if (state == 1) {
        # CSI state: accumulate until final byte [a-zA-Z]
        buf = buf c
        if (c ~ /[a-zA-Z]/) state = 0
      } else if (state == 2) {
        # OSC8 state: accumulate until ST (ESC \\ or BEL 0x07)
        buf = buf c
        osc_buf = osc_buf c
        if (b == 92 && i >= 2 && _ord[substr($0, i-1, 1)] == 27) {
          state = 0  # ST (ESC\) reached
          # Detect opening vs closing OSC 8: opening has URL, closing is empty.
          # osc_buf for opening: ]8;;URL...ESC\  (>6 chars including ESC\)
          # osc_buf for closing: ]8;;ESC\  (exactly 6 chars: ] 8 ; ; ESC \)
          if (length(osc_buf) > 6 && osc_buf ~ /^]8;;/) {
            in_link = 1  # Opening: has URL content
          } else if (osc_buf ~ /^]8;;/) {
            in_link = 0  # Closing: empty URL
          }
        } else if (b == 7) {
          state = 0
          # BEL-terminated: opening ]8;;URL...BEL (>5), closing ]8;;BEL (exactly 5)
          if (length(osc_buf) > 5 && osc_buf ~ /^]8;;/) in_link = 1
          else if (osc_buf ~ /^]8;;/) in_link = 0
        }
      }
    }
  }
  END {
    # Close syntax-level open OSC sequence
    if (state == 2) buf = buf "\033]8;;\033\\"
    # Close semantic-level open hyperlink (truncated between open and close pair)
    else if (in_link) buf = buf "\033]8;;\033\\"
    # Append reset if we actually truncated and had escape sequences
    if (saw_esc && (done || state != 0 || in_link)) buf = buf "\033[0m"
    print buf
  }'
}

# --- compute_bar_width() ---
# Calculate per-bar width clamped to [MIN_BAR, MAX_BAR] or 0 (drop signal).
# Usage: compute_bar_width available_width num_bars
#   $1 = available_width (integer, total chars available for all bars)
#   $2 = num_bars (integer, number of progress bars to fit)
#   stdout = integer per-bar width, clamped to [3,20] or 0
compute_bar_width() {
  local available="$1" num_bars="$2"

  # Guard: zero bars means nothing to compute
  [ "$num_bars" -le 0 ] && { echo 0; return; }

  local per_bar=$((available / num_bars))

  # Clamp to [MIN_BAR, MAX_BAR] or signal drop with 0
  if [ "$per_bar" -lt "$MIN_BAR" ]; then
    echo 0  # Signal: drop a segment
  elif [ "$per_bar" -gt "$MAX_BAR" ]; then
    echo "$MAX_BAR"
  else
    echo "$per_bar"
  fi
}
