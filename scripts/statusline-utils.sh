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
