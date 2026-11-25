utf8 = require("lua-utf8")

---Debug tools
local debug_mode = true
local function print_debug(str)
  if debug_mode == true then
    print(str)
  end
end

local function inspect(var)
  print(require("inspect")(var))
end

---Returns the UTF8 character of string `s` at UTF8 position i
---Designed for convenience
---@param s string
---@param i integer
---@return string?
local function utf8_char_at_pos(s, i)
  if i >= 1 and i <= utf8.len(s) then
    return utf8.sub(s, i, i)
  else
    return nil
  end
end

-- Constants for lexer
ESCAPED_RESERVED_CHARS = {
  ["#"] = "literal_hashtag",
  ["$"] = "literal_dollar_sign",
  ["%"] = "literal_percent_sign",
  ["&"] = "literal_ampersand",
  ["_"] = "literal_underscore",
  ["{"] = "literal_open_brace",
  ["}"] = "literal_close_brace",
  ["|"] = "literal_vertical_bar",
  ["\\"] = "new_line",
  ["-"] = "discretionary_hyphen",
  [","] = "space_thin",
  [" "] = "space_normal",
  ["/"] = "space_italic_correction",
  ["!"] = "negative_thin_space",
}

ESCAPED_RESERVED_CODEPOINTS = {
  [0x0023] = "literal_hashtag",
  [0x0024] = "literal_dollar_sign",
  [0x0025] = "literal_percent_sign",
  [0x0026] = "literal_ampersand",
  [0x005F] = "literal_underscore",
  [0x007B] = "literal_open_brace",
  [0x007D] = "literal_close_brace",
  [0x007C] = "literal_vertical_bar",
  [0x005C] = "new_line",
  [0x002D] = "discretionary_hyphen",
  [0x002C] = "space_thin",
  [0x0020] = "space_normal",
  [0x002F] = "space_italic_correction",
  [0x0021] = "negative_thin_space",
}

SPECIAL_CHARS = {
  ["{"] = "open_brace",
  ["}"] = "close_brace",
  ["["] = "open_bracket",
  ["]"] = "close_bracket",
  ["("] = "open_parenthesis",
  [")"] = "close_parenthesis",
  ["#"] = "hashtag",
  ['"'] = "quote",
  ["="] = "equal_sign",
}

SPECIAL_CODEPOINTS = {
  [0x007B] = "open_brace",
  [0x007D] = "close_brace",
  [0x005B] = "open_bracket",
  [0x005D] = "close_bracket",
  [0x0028] = "open_parenthesis",
  [0x0029] = "close_parenthesis",
  [0x0023] = "hashtag",
  [0x0022] = "quote",
  [0x003D] = "equal_sign",
}

VERBATIM_COMMANDS = {
  ["\\verbatim"] = {
    ["^%{"] = "%}",
  },
  ["\\type"] = {
    ["^%{"] = "%}",
    ["^<<"] = ">>",
  },
  ["\\tex"] = {
    ["^%{"] = "%}",
  },
  ["\\filename"] = {
    ["^%{"] = "%}",
  },
  ["\\arg"] = {
    ["^%{"] = "%}",
  },
}

VERBATIM_ENVIRONMENTS = {
  ["\\starttyping"] = "\\stoptyping",
  ["\\startTEX"] = "\\stopTEX",
  ["\\startLUA"] = "\\stopLUA",
  ["\\startMP"] = "\\stopMP",
  ["\\startXML"] = "\\stopXML",
}

local function lex_line(line)
  local utf8_cursor_pos = 1
  local utf8_tracker_pos = 1
  local utf8_tracker_char = utf8_char_at_pos(line, utf8_tracker_pos)
  local utf8_line_length = utf8.len(line)
  local tokens = {}
  local lexer_state = "normal"

  local function is_tracker_past_end()
    return utf8_tracker_pos > utf8_line_length
  end

  ---Moves tracker by amount `mvt` and updates utf8_tracking_char
  ---@param mvt number
  ---@return string?
  local function move_tracker(mvt)
    if not is_tracker_past_end() then
      utf8_tracker_pos = utf8_tracker_pos + mvt
      utf8_tracker_char = utf8.sub(line, utf8_tracker_pos, utf8_tracker_pos)
      print_debug("Tracker currently at: " .. utf8_tracker_pos .. " with character: `" .. utf8_tracker_char .. "`")
    else
      utf8_tracker_char = nil
    end
  end

  local function move_tracker_to_pos(pos)
    move_tracker(pos - utf8_tracker_pos)
  end

  ---Moves tracker foreward by one
  ---Handler for `move_tracker`
  local function increment_tracker()
    move_tracker(1)
  end

  ---Moves tracker to end of string
  local function move_tracker_to_end()
    utf8_tracker_pos = utf8_line_length + 1
    utf8_tracker_char = nil
  end

  ---@param i number?
  ---@return string
  local function peek_char_from_tracker(i)
    i = i or 1
    return utf8.sub(line, utf8_tracker_pos + i, utf8_tracker_pos + i)
  end

  ---Flush token to token list, `tokens`
  local function flush_token(token_type, token_content, utf8_start_pos, utf8_stop_pos)
    tokens[#tokens + 1] = {
      token_type = token_type,
      token_content = token_content,
      utf8_start_pos = utf8_start_pos,
      utf8_stop_pos = math.min(utf8_stop_pos, utf8_line_length),
    }
  end

  local function next_token()
    --- If tracker is at end
    if utf8_cursor_pos > utf8_line_length then
      return nil
    end

    print_debug("--- New lexeme starting ---")
    print_debug(
      "Start scanning from cursor position "
        .. utf8_cursor_pos
        .. " with character: `"
        .. utf8_char_at_pos(line, utf8_cursor_pos)
        .. "`"
    )
    print_debug(
      "Start scanning from tracker position "
        .. utf8_tracker_pos
        .. " with character: `"
        .. (utf8_tracker_char or "nil")
        .. "`"
    )

    -- Comments
    if utf8_char_at_pos(line, utf8_cursor_pos) == "%" then
      print_debug("Token type is comment! Skipping to string end")
      flush_token("comment", utf8.sub(line, utf8_cursor_pos, utf8_line_length), utf8_cursor_pos, utf8_line_length)
      move_tracker_to_end()
      return nil
    end

    -- Dollar sign math open
    if utf8.codepoint(line, utf8_cursor_pos) == 0x0024 then
      if utf8.find(line, "^%$", utf8_cursor_pos + 1) then
        flush_token("dollar_sign_display_math", "$$", utf8_cursor_pos, utf8_cursor_pos + 1)
        move_tracker(2)
      else
        flush_token("dollar_sign_inline_math", "$", utf8_cursor_pos, utf8_cursor_pos)
        increment_tracker()
      end
      utf8_cursor_pos = utf8_tracker_pos
      return nil
    end

    --- Control sequences
    if utf8_char_at_pos(line, utf8_cursor_pos) == "\\" then
      print_debug("Token type is control sequence!")
      local token_content
      local token_type = nil

      -- Single letters command
      local next_utf8_cp
      if utf8_cursor_pos + 1 > utf8_line_length then
        next_utf8_cp = nil
      else
        next_utf8_cp = utf8.codepoint(line, utf8_cursor_pos + 1)
      end
      if ESCAPED_RESERVED_CODEPOINTS[next_utf8_cp] then
        token_type = ESCAPED_RESERVED_CODEPOINTS[next_utf8_cp]
        print_debug("Is a control sequence of type: " .. token_type)
        flush_token(
          token_type,
          utf8.sub(line, utf8_cursor_pos, utf8_cursor_pos + 1),
          utf8_cursor_pos,
          utf8_cursor_pos + 1
        )
        move_tracker(2)
        utf8_cursor_pos = utf8_tracker_pos
        return nil
      end

      -- Alphanumeric control sequences
      if token_type == nil then
        local next_non_alphabetic_utf8_pos = utf8.find(line, "%A", utf8_cursor_pos + 1) or utf8_line_length + 1
        token_content = utf8.sub(line, utf8_cursor_pos, next_non_alphabetic_utf8_pos - 1)
        token_type = "control_sequence"
        move_tracker_to_pos(next_non_alphabetic_utf8_pos)
      end

      -- If command is verbatim sequence
      if VERBATIM_COMMANDS[token_content] then
        -- Does verbatim open follow command?
        token_type = "verbatim_sequence"
        for verbatim_open_regex, verbatim_end_regex in pairs(VERBATIM_COMMANDS[token_content]) do
          print_debug(utf8_tracker_pos)
          local verbatim_open_utf8_start_pos, verbatim_open_utf8_end_pos =
            utf8.find(line, verbatim_open_regex, utf8_tracker_pos)
          local verbatim_close_utf8_start_pos, verbatim_close_utf8_end_pos =
            utf8.find(line, verbatim_end_regex, utf8_tracker_pos)

          if verbatim_open_utf8_start_pos and verbatim_open_utf8_end_pos then
            print_debug(
              "Found verbatim open string position: "
                .. verbatim_open_utf8_start_pos
                .. " to "
                .. verbatim_open_utf8_end_pos
            )
            if verbatim_close_utf8_start_pos and verbatim_close_utf8_end_pos then
              print_debug(
                "Found verbatim closing string at position: "
                  .. verbatim_close_utf8_start_pos
                  .. " to "
                  .. verbatim_close_utf8_end_pos
              )
              local verbatim_content = utf8.sub(line, verbatim_open_utf8_end_pos + 1, verbatim_close_utf8_start_pos - 1)

              -- Four tokens: verbatim command, verbatim close, contents, and open
              flush_token(token_type, token_content, utf8_cursor_pos, utf8_tracker_pos - 1)
              flush_token(
                "verbatim_open",
                utf8.sub(line, verbatim_open_utf8_start_pos, verbatim_open_utf8_end_pos),
                verbatim_open_utf8_start_pos,
                verbatim_open_utf8_end_pos
              )
              if verbatim_content ~= "" then
                flush_token(
                  "verbatim_content",
                  verbatim_content,
                  verbatim_open_utf8_end_pos + 1,
                  verbatim_close_utf8_start_pos - 1
                )
              end
              flush_token(
                "verbatim_close",
                utf8.sub(line, verbatim_close_utf8_start_pos, verbatim_close_utf8_end_pos),
                verbatim_close_utf8_start_pos,
                verbatim_close_utf8_end_pos
              )
              move_tracker_to_pos(verbatim_close_utf8_end_pos + 1)
              utf8_cursor_pos = utf8_tracker_pos
              return nil
            else
              warn("Can't find ending position of verbatim. Will resume as normal")
            end
          end
        end
      end
      flush_token(token_type, token_content, utf8_cursor_pos, utf8_tracker_pos - 1)
      utf8_cursor_pos = utf8_tracker_pos
      return nil
    end

    -- Whitespaces
    if utf8_char_at_pos(line, utf8_cursor_pos) == " " then
      local next_non_whitespace_utf8_position = utf8.find(line, "[^ ]", utf8_cursor_pos) or (utf8_line_length + 1)
      flush_token(
        "whitespace",
        string.rep(" ", next_non_whitespace_utf8_position - utf8_cursor_pos),
        utf8_cursor_pos,
        next_non_whitespace_utf8_position - 1
      )
      move_tracker_to_pos(next_non_whitespace_utf8_position)
      utf8_cursor_pos = utf8_tracker_pos
      return nil
    end

    -- ConTeXt/TeX special characters
    if SPECIAL_CODEPOINTS[utf8.codepoint(line, utf8_cursor_pos)] then
      flush_token(
        SPECIAL_CODEPOINTS[utf8.codepoint(line, utf8_cursor_pos)],
        utf8_char_at_pos(line, utf8_cursor_pos),
        utf8_cursor_pos,
        utf8_cursor_pos
      )
      increment_tracker()
      utf8_cursor_pos = utf8_tracker_pos
      return nil
    end

    -- Normal words
    if not utf8.match(line, "^%s", utf8_cursor_pos) then
      -- Track until reaches \ or whitespace or special characters or end, then stop
      local word_end_utf8_pos = utf8.find(line, '[%s%\\%{%}%[%]%(%)%#%"%=%$]', utf8_cursor_pos)
        or (utf8_line_length + 1)
      print_debug(word_end_utf8_pos)
      flush_token(
        "words",
        utf8.sub(line, utf8_cursor_pos, word_end_utf8_pos - 1),
        utf8_cursor_pos,
        word_end_utf8_pos - 1
      )
      move_tracker_to_pos(word_end_utf8_pos)
      utf8_cursor_pos = utf8_tracker_pos
      return nil
    end
  end

  while true do
    next_token()
    if is_tracker_past_end() then
      break
    end
  end
  return tokens
end

local source = [[test source $\frac{x}{y}$ $$\alpha\beta$$ \\ \tex {$testverbatim$}]]
inspect(lex_line(source))
