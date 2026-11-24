utf8 = require("lua-utf8")

---Returns the UTF8 character of string `s` at UTF8 position i
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

local function lex_line(line)
  local utf8_cursor_position = 1
  local utf8_tracking_position = 1
  local utf8_tracking_char = utf8_char_at_pos(line, utf8_tracking_position)
  local utf8_line_length = utf8.len(line)
  local tokens = {}

  local function is_tracker_at_end()
    return utf8_tracking_position == utf8_line_length
  end

  ---@param mvt number
  ---@return string?
  local function move_tracker(mvt)
    if not is_tracker_at_end() then
      utf8_tracking_position = utf8_tracking_position + mvt
      utf8_tracking_char = utf8.sub(line, utf8_tracking_position, utf8_tracking_position)
      print("Tracker currently at: " .. utf8_tracking_position .. " with character: `" .. utf8_tracking_char .. "`")
    else
      utf8_tracking_char = nil
    end
  end

  local function increment_tracker()
    move_tracker(1)
  end

  local function decrement_tracker()
    move_tracker(-1)
  end

  local function flush_token(token_type, token_content, utf8_start_position, utf8_stop_position)
    tokens[#tokens + 1] = {
      token_type = token_type,
      token_content = utf8.sub(line, utf8_start_position, utf8_stop_position),
      utf8_start_position = utf8_start_position,
      utf8_stop_position = utf8_stop_position,
    }
  end

  local function next_token()
    --- Comments
    print("--- New lexeme starting ---")
    print(
      "Start scanning from cursor position "
        .. utf8_cursor_position
        .. " with character: `"
        .. utf8_char_at_pos(line, utf8_cursor_position)
        .. "`"
    )
    print(
      "Start scanning from tracker position "
        .. utf8_tracking_position
        .. " with character: `"
        .. (utf8_tracking_char or "nil")
        .. "`"
    )
    if utf8_char_at_pos(line, utf8_cursor_position) == "%" then
      tokens[#tokens + 1] = {
        token_type = "comment",
        token_content = utf8.sub(line, utf8_cursor_position, utf8_line_length),
        utf8_start_position = utf8_cursor_position,
        utf8_stop_position = utf8_line_length,
        start_position = utf8.offset(line, utf8_cursor_position),
        stop_position = #line,
      }
    end

    --- Control sequences
    if utf8_char_at_pos(line, utf8_cursor_position) == "\\" then
      print("Found control sequence!")
      local token_content = { "\\" }
      local token_type = nil
      increment_tracker()

      if utf8_tracking_char == " " then
        token_type = "space_command"
        token_content[#token_content + 1] = utf8_tracking_char
      elseif utf8_tracking_char == "\\" then
        token_type = "newline"
        token_content[#token_content + 1] = utf8_tracking_char
      elseif utf8_tracking_char == "(" then
        token_type = "begin_inline_math"
        token_content[#token_content + 1] = utf8_tracking_char
      elseif utf8_tracking_char == ")" then
        token_type = "end_inline_math"
        token_content[#token_content + 1] = utf8_tracking_char
      end

      if token_type == nil then
        token_type = "control_sequence"
        while utf8_tracking_char do
          if utf8_tracking_char == "\\" or utf8_tracking_char == " " then
            token_content[#token_content + 1] = utf8_tracking_char
            break
          else
            token_content[#token_content + 1] = utf8_tracking_char
            increment_tracker()
          end
        end
      end

      flush_token(token_type, table.concat(token_content, ""), utf8_cursor_position, utf8_tracking_position)
    end

    -- Whitespaces
    if utf8_char_at_pos(line, utf8_cursor_position) == " " then
      local next_utf8_char = increment_tracker()
      local space_count = 1
      while next_utf8_char and next_utf8_char == " " do
        space_count = space_count + 1
        next_utf8_char = increment_tracker()
      end
      tokens[#tokens + 1] = {
        token_type = "whitespace",
        token_content = string.rep(" ", space_count),
        start_position = utf8.offset(line, utf8_cursor_position),
        stop_position = utf8.offset(line, utf8_tracking_position),
        utf8_start_position = utf8_cursor_position,
        utf8_stop_position = utf8_tracking_position,
      }
      print(utf8_tracking_position)
    end

    -- Normal words

    increment_tracker()
    utf8_cursor_position = utf8_tracking_position
    inspect(tokens)
  end

  next_token()
  next_token()
  return tokens
end

function inspect(var)
  print(require("inspect")(var))
end

source = [[\\ aaa]]
lex_line(source)
