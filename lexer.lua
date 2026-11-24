utf8 = require("lua-utf8")

---Debug tools
local debug_mode = true
local function print_debug(str)
  if debug_mode == true then
    print(str)
  end
end

function inspect(var)
  print(require("inspect")(var))
end

---Returns the UTF8 character of string `s` at UTF8 position i
---Designed for convenience
---@param s string
---@param i integer
---@return string?
local function utf8_char_at_pos(s, i)
  if i then
    return utf8.sub(s, i, i)
  else
    return nil
  end
end

local escaped_reserved_chars = {
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

local function lex_line(line)
  local utf8_cursor_position = 1
  local utf8_tracking_position = 1
  local utf8_tracking_char = utf8_char_at_pos(line, utf8_tracking_position)
  local utf8_line_length = utf8.len(line)
  local tokens = {}
  local halt_lexer = false

  local function is_tracker_at_end()
    return utf8_tracking_position == utf8_line_length
  end

  ---Moves tracker by amount `mvt` and updates utf8_tracking_char
  ---@param mvt number
  ---@return string?
  local function move_tracker(mvt)
    if not is_tracker_at_end() then
      utf8_tracking_position = utf8_tracking_position + mvt
      utf8_tracking_char = utf8.sub(line, utf8_tracking_position, utf8_tracking_position)
      print_debug(
        "Tracker currently at: " .. utf8_tracking_position .. " with character: `" .. utf8_tracking_char .. "`"
      )
    else
      utf8_tracking_char = nil
    end
  end

  ---Moves tracker foreward by one
  ---Handler for `move_tracker`
  local function increment_tracker()
    move_tracker(1)
  end

  ---Moves tracker backward by one
  ---Handler for `move_tracker`
  local function decrement_tracker()
    move_tracker(-1)
  end

  ---Moves tracker to end of string
  local function move_tracker_to_end()
    mvt = utf8_line_length - utf8_tracking_position
    move_tracker(mvt)
  end

  ---@param i number?
  ---@return string
  local function peek_char_from_tracker(i)
    i = i or 1
    return utf8.sub(line, utf8_tracking_position + i, utf8_tracking_position + i)
  end

  ---Flush token to token list, `tokens`
  local function flush_token(token_type, token_content, utf8_start_position, utf8_stop_position)
    tokens[#tokens + 1] = {
      token_type = token_type,
      token_content = token_content,
      utf8_start_position = utf8_start_position,
      utf8_stop_position = utf8_stop_position,
    }
  end

  local function next_token()
    --- If tracker is at end
    if halt_lexer then
      return nil
    end

    print_debug("--- New lexeme starting ---")
    print_debug(
      "Start scanning from cursor position "
        .. utf8_cursor_position
        .. " with character: `"
        .. utf8_char_at_pos(line, utf8_cursor_position)
        .. "`"
    )
    print_debug(
      "Start scanning from tracker position "
        .. utf8_tracking_position
        .. " with character: `"
        .. (utf8_tracking_char or "nil")
        .. "`"
    )

    -- Comments
    if utf8_char_at_pos(line, utf8_cursor_position) == "%" then
      print("Token type is comment! Skipping to string end")
      tokens[#tokens + 1] = {
        token_type = "comment",
        token_content = utf8.sub(line, utf8_cursor_position, utf8_line_length),
        utf8_start_position = utf8_cursor_position,
        utf8_stop_position = utf8_line_length,
        start_position = utf8.offset(line, utf8_cursor_position),
        stop_position = #line,
      }
      move_tracker_to_end()
      return nil
    end

    -- Dollar sign math open
    if utf8_char_at_pos(line, utf8_cursor_position) == "$" then
      local next_utf8_char = peek_char_from_tracker()
      print_debug("Next char is: " .. (next_utf8_char or "nil"))
      if next_utf8_char == "$" then
        flush_token("dollar_sign_display_math", "$$", utf8_cursor_position, utf8_cursor_position + 1)
        move_tracker(2)
      else
        flush_token("dollar_sign_inline_math", "$", utf8_cursor_position, utf8_cursor_position)
        increment_tracker()
      end
      utf8_cursor_position = utf8_tracking_position
      return nil
    end

    --- Control sequences
    if utf8_char_at_pos(line, utf8_cursor_position) == "\\" then
      print_debug("Token type is control sequence!")
      local token_content = { "\\" }
      local token_type = nil
      increment_tracker()

      -- Single letters command
      if escaped_reserved_chars[utf8_tracking_char] then
        token_type = escaped_reserved_chars[utf8_tracking_char]
        print("Is a control sequence of type: " .. token_type)
        token_content[#token_content + 1] = utf8_tracking_char
      end

      if token_type == nil then
        while utf8_tracking_char do
          token_content[#token_content + 1] = utf8_tracking_char
          local next_utf8_tracking_char = peek_char_from_tracker()
          if
            (next_utf8_tracking_char == "\\")
            or (next_utf8_tracking_char == " ")
            or (
              (utf8_tracking_char == "]")
              or (utf8_tracking_char == "}")
                and not (next_utf8_tracking_char == "[" or next_utf8_tracking_char == "{")
            )
          then
            break
          else
            increment_tracker()
          end
        end
        if utf8.sub(line, utf8_cursor_position + 1, utf8_cursor_position + 5) == "start" then
          token_type = "begin_enviroment"
        elseif utf8.sub(line, utf8_cursor_position + 1, utf8_cursor_position + 4) == "stop" then
          token_type = "end_environment"
        else
          token_type = "control_sequence"
        end
      end

      flush_token(token_type, table.concat(token_content, ""), utf8_cursor_position, utf8_tracking_position)
      increment_tracker()
      utf8_cursor_position = utf8_tracking_position
      return nil
    end

    -- Whitespaces
    if utf8_char_at_pos(line, utf8_cursor_position) == " " then
      local next_utf8_char = peek_char_from_tracker()
      local space_count = 1
      while next_utf8_char and next_utf8_char == " " do
        space_count = space_count + 1
        increment_tracker()
        next_utf8_char = peek_char_from_tracker()
      end
      flush_token(
        "whitespace",
        string.rep(" ", space_count),
        utf8_cursor_position,
        utf8_cursor_position + space_count - 1
      )
      increment_tracker()
      utf8_cursor_position = utf8_tracking_position
      return nil
    end

    -- Normal words
    if not utf8.match(utf8_char_at_pos(line, utf8_cursor_position), "^%s+$") then
      -- Track until reaches \ or whitespace, then stop
      local next_utf8_char = peek_char_from_tracker()
      while next_utf8_char and utf8.match(next_utf8_char, "[%w%.,:;!%?'\"%(%)%[%]%/%-%+%*=]") do
        increment_tracker()
        next_utf8_char = peek_char_from_tracker()
      end
      flush_token(
        "words",
        utf8.sub(line, utf8_cursor_position, utf8_tracking_position),
        utf8_cursor_position,
        utf8_tracking_position
      )
      increment_tracker()
      utf8_cursor_position = utf8_tracking_position
    end
  end
  return tokens
end

source = [[tex \m{abcde}]]
lex_line(source)
