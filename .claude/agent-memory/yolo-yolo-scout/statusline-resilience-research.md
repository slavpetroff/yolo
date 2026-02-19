# Statusline Resilience Research Summary

## Key Findings (2026-02-18)

### ANSI CSI Grammar & Stripping (C1)
- **Standard**: ECMA-48 specifies CSI as ESC [ {params:0x30-3F} {intermediate:0x20-2F} {final:0x40-7E}
- **Common finals**: m (SGR/color), K (erase), H (move), J (erase display), A-F (cursor)
- **Robust sed**: `sed -r 's/\x1b\[[0-9;]*[a-zA-Z]//g'` covers all CSI, not just m
- **OSC 8 hyperlinks**: Use separate pattern: `sed -r 's/\x1b\]8[^\x1b]*\x1b\\//g'`

### ANSI String Truncation (C2)
- **No single standard algorithm** — problem is inherent to streaming ANSI
- **Solution**: State machine parser with 3 states (ground, CSI, OSC8)
- **Track**: visible_count (user sees) vs raw_position (byte offset)
- **When truncating**: Emit substring [0..raw_position] + reset code `\x1b[0m`
- **Real tools**: vim, powerline, bash readline all use state machines
- **Reference**: VT100.net DEC ANSI parser, VTParse (haberman/vtparse)

### OSC 8 Hyperlink Syntax (C3)
- **Format**: `ESC]8;{params};{URI}ST{text}ESC]8;;ST`
- **ST terminator**: ESC\ (0x1b 0x5c) or BEL (0x07)
- **Measurement vs degradation**: Strip entire OSC 8 for width, but replace with plain text for fallback

### Terminal Width Budgeting (C4)
- **Pattern**: Two-pass construction (skeleton + measure, then rebuild with bars)
- **Key insight**: ANSI codes consume bytes but zero visible width
- **Ecosystem**: Tmux, vim, powerline all use similar two-pass approach
- **Why**: Impossible to know bar_width without measuring skeleton first

### Unicode Block Characters (C6)
- **Default**: U+2588 (FULL BLOCK), U+2591 (LIGHT SHADE) are Neutral (width=1)
- **Caveat**: CJK-aware terminals with fullwidth fonts may render as width=2
- **Classification**: Per wcwidth spec and Unicode standard
- **Gap**: YOLO also uses U+2593, U+25C6, U+2502 — same assumption

### Bash Function Testing (C7)
- **Standard pattern**: Extract functions to sourceable library, gate main with BASH_SOURCE check
- **Gating pattern**: `if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then main; fi`
- **Frameworks**: BATS, ShellSpec, bash_unit, Bach all support this
- **Benefit**: Direct unit testing of functions without triggering full script

## Dev Recommendations Summary
1. **C1**: Two sed passes (CSI + OSC 8), document ECMA-48 basis
2. **C2**: State machine truncator, reference VTParse, add OSC 8 boundary test
3. **C3**: Separate visible_width() (strip) vs strip_osc8_links() (replace)
4. **C4**: Two-pass L3 construction with placeholders, measure skeleton first
5. **C6**: Document wcwidth=1 assumption, note CJK caveat
6. **C7**: Refactor to scripts/statusline-utils.sh, gate main with BASH_SOURCE

## Sources (Authoritative)
- ECMA-48 standard: https://wezfurlong.org/ecma48/04-coding.html
- VT100.net DEC ANSI parser: https://vt100.net/emu/dec_ansi_parser
- VTParse reference: https://github.com/haberman/vtparse
- wcwidth spec: https://github.com/jquast/wcwidth
- OSC 8 spec: https://gist.github.com/egmontkob/eb114294efbcd5adb1944c9f3cb5feda
- BATS testing: https://jon.sprig.gs/blog/post/2316

## Confidence
- **C1, C3, C7**: High — spec/standard/pattern-based
- **C2, C4**: Medium-high — backed by real-world tool analysis (vim, tmux, powerline)
- **C6**: Medium — wcwidth is standard, but rendering is terminal-dependent
