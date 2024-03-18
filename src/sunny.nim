import std/options, std/strutils, unicody, std/bitops, std/math, std/typetraits,
    std/sets, std/tables

import std/macros except error

from std/parseutils import parseFloat

from std/json as std import nil

from std/enumutils import nil

when defined(amd64):
  import nimsimd/sse2
elif defined(arm64):
  import nimsimd/neon

type
  RawJson* = distinct string

  JsonValueKind* = enum
    StringValue, NumberValue, BooleanValue, NullValue, ObjectValue, ArrayValue

  JsonValue* = object
    start*, len*: int
    case kind*: JsonValueKind
    of StringValue, NumberValue, NullValue:
      discard
    of BooleanValue:
      b*: bool
    of ObjectValue:
      o*: seq[(string, JsonValue)]
    of ArrayValue:
      a*: seq[JsonValue]

  SomeTable*[K, V] =
    Table[K, V] | OrderedTable[K, V] |
    TableRef[K, V] | OrderedTableRef[K, V]

let
  t = "true"
  f = "false"
  n = "null"

template error(msg: string) =
  raise newException(CatchableError, msg)

when defined(release):
  {.push checks: off.}

{.push gcsafe.}

proc getu4(input: string, start: int): int32 =
  for i in 0 ..< 4:
    let c = input[start + i]
    case c:
    of '0' .. '9':
      result = result shl 4 or ord(c).int32 - ord('0')
    of 'a' .. 'f':
      result = result shl 4 or ord(c).int32 - ord('a') + 10
    of 'A' .. 'F':
      result = result shl 4 or ord(c).int32 - ord('A') + 10
    else:
      # Not possible, pre-validated
      error("Invalid hex digit at " & $(start + i))

proc copy(s: var string, src: string, start, len: int) {.inline.} =
  when nimvm:
    for i in start ..< start + len:
      s.add src[i]
  else:
    when defined(js):
      for i in start ..< start + len:
        s.add src[i]
    else:
      if len > 0:
        let tmp = s.len
        s.setLen(tmp + len)
        copyMem(s[tmp].addr, src[start].unsafeAddr, len)

proc unescapeString(input: string, start, len: int): string =
  if len == 0:
    return

  # We can assume this string:
  # * is valid UTF-8 runes
  # * does not contain any control characters
  # * does not contain any unescaped "
  # * only escapes valid characters

  var
    i = start
    copyStart = i
  while i < start + len:
    let c = input[i]
    if c == '\\':
      copy(result, input, copyStart, i - copyStart)
      # We can blindly index ahead since this is checked in parseString
      let e = input[i + 1]
      case e:
      of '"', '\\', '/': result.add(e)
      of 'b': result.add '\b'
      of 'f': result.add '\f'
      of 'n': result.add '\n'
      of 'r': result.add '\r'
      of 't': result.add '\t'
      of 'u':
        let r1 = getu4(input, i + 2)
        if Rune(r1).isSurrogate():
          if not Rune(r1).isHighSurrogate():
            error("Invalid surrogate pair at " & $i)
          # Must be followed by a low surrogate
          if i + 12 > input.len:
            error("Invalid surrogate pair at " & $i)
          let r2 = getu4(input, i + 8)
          if Rune(r2).isLowSurrogate():
            let codePoint =
              0x10000 +
              ((r1 - highSurrogateMin) shl 10) +
              (r2 - lowSurrogateMin)
            result.unsafeAdd Rune(codePoint)
          else:
            error("Invalid surrogate pair at " & $i)
          i += 10
        else:
          result.unsafeAdd Rune(r1)
          i += 4
      else:
        error("Invalid escaped character at " & $i) # Not possible
      i += 2
      copyStart = i
    else:
      inc i

  copy(result, input, copyStart, start + len - copyStart)

proc unescapeString*(value: JsonValue, input: string): string {.inline.} =
  # Ignore opening and closing quotes
  unescapeString(input, value.start + 1, value.len - 2)

proc parseString(input: string, i: var int): int =
  let start = i

  inc i

  if i == input.len:
    error("Unexpected end of JSON input")

  while i < input.len:
    # when defined(amd64):
    #   if i + 16 <= input.len:
    #     let
    #       a = mm_loadu_si128(input[i].unsafeAddr)
    #       q = mm_cmpeq_epi8(a, mm_set1_epi8('"'.uint8))
    #       e = mm_cmpeq_epi8(a, mm_set1_epi8('\\'.uint8))
    #       qe = mm_or_si128(q, e)
    #       mask = cast[uint16](mm_movemask_epi8(qe))
    #     if mask == 0:
    #       i += 16
    #       continue
    #     i += countTrailingZeroBits(mask)
    # elif defined(arm64):
    #   if i + 8 <= input.len:
    #     let
    #       a = vld1_u8(input[i].unsafeAddr)
    #       q = vceq_u8(a, vmov_n_u8('"'.uint8))
    #       e = vceq_u8(a, vmov_n_u8('\\'.uint8))
    #       qe = vorr_u8(q, e)
    #       mask = vget_lane_u64(cast[uint64x1](qe), 0)
    #     if mask == 0:
    #       i += 8
    #       continue
    #     i += countTrailingZeroBits(mask) div 8

    if input[i] == '"':
      inc i
      break
    elif input[i] == '\\':
      if i + 1 == input.len:
        error("Unexpected end of JSON input")
      case input[i + 1]:
      of '"', '\\', '/', 'b', 'f', 'n', 'r', 't':
        i += 2
      of 'u':
        if i + 6 > input.len:
          error("Unexpected end of JSON input")
        else:
          const valid = {'0' .. '9', 'A' .. 'F', 'a' .. 'f'}
          if input[i + 2] notin valid or input[i + 3] notin valid or
            input[i + 4] notin valid or input[i + 5] notin valid:
            error("Invalid escaped unicode hex sequence at " & $i)
          i += 6
      else:
        error("Invalid escaped character at " & $i)
    else:
      inc i

  let len = i - start

  if len > 2 and containsControlCharacter(input.toOpenArray(start, len - 1)):
    error("Invalid control character in string starting at " & $start)

  return len

proc parseNumber(input: string, start, len: int) =
  if len == 0:
    error("Invalid number at " & $start)

  var ni = start

  if input[start] == '-':
    if len == 1:
      error("Invalid number at " & $start)
    inc ni

  if input[ni] == '0':
    if ni == start + len - 1:
      return
    # Check there is no leading zero unless followed by a '.'
    if input[ni + 1] != '.':
      error("Invalid number at " & $start)

  var d, e: bool
  while ni < start + len:
    case input[ni]:
    of '.':
      if d or e or ni + 1 == start + len:
        error("Invalid number at " & $start)
      if input[ni + 1] notin '0' .. '9':
        error("Invalid number at " & $start)
      ni += 2
      d = true
    of 'e', 'E':
      if e or ni + 1 == start + len:
        error("Invalid number at " & $start)
      if input[ni + 1] == '+' or input[ni + 1] == '-':
        if ni + 2 == start + len:
          error("Invalid number at " & $start)
        ni += 2
      else:
        inc ni
      e = true
    of '0' .. '9':
      inc ni
    else:
      error("Invalid number at " & $start)

proc parseNumber(input: string, i: var int): int =
  let
    start = i
    after = input.find({' ', '\n', '\r', '\n', ',', '}', ']'}, start = i + 1)
  var len: int
  if after == -1:
    len = input.len - i
    i = input.len
  else:
    len = after - i
    i = after

  parseNumber(input, start, len)

  return len

proc parseBoolean(input: string, i: var int): bool {.inline.} =
  when defined(js):
    if i + 4 <= input.len and
      input[i + 0] == t[0] and
      input[i + 1] == t[1] and
      input[i + 2] == t[2] and
      input[i + 3] == t[3]:
      i += 4
      return true
    elif i + 5 <= input.len and
      input[i + 0] == f[0] and
      input[i + 1] == f[1] and
      input[i + 2] == f[2] and
      input[i + 3] == f[3] and
      input[i + 4] == f[4]:
      i += 5
      return false
  else:
    {.gcsafe.}:
      if i + 4 <= input.len and equalMem(input[i].unsafeAddr, t.cstring, 4):
        i += 4
        return true
      elif i + 5 <= input.len and equalMem(input[i].unsafeAddr, f.cstring, 5):
        i += 5
        return false
  error("Expected true or false at " & $i)

proc parseNull(input: string, i: var int) {.inline.} =
  when defined(js):
    if i + 4 <= input.len and
      input[i + 0] == n[0] and
      input[i + 1] == n[1] and
      input[i + 2] == n[2] and
      input[i + 3] == n[3]:
      i += 4
      return
  else:
    {.gcsafe.}:
      if i + 4 <= input.len and equalMem(input[i].unsafeAddr, n.cstring, 4):
        i += 4
        return
  error("Expected null at " & $i)

# when defined(release) and defined(nimHasQuirky):
#   proc skipWhitespace(input: string, i: var int) {.inline, quirky.}
#   {.push quirky: on.}
# else:
#   proc skipWhitespace(input: string, i: var int) {.inline.}

proc skipWhitespace(input: string, i: var int) =
  if i >= input.len or input[i] notin {' ', '\n', '\r', '\t'}:
    return

  # when defined(amd64):
  #   while i + 16 <= input.len:
  #     let
  #       a = mm_loadu_si128(input[i].unsafeAddr)
  #       s = mm_cmpeq_epi8(a, mm_set1_epi8(' '.uint8))
  #       n = mm_cmpeq_epi8(a, mm_set1_epi8('\n'.uint8))
  #       r = mm_cmpeq_epi8(a, mm_set1_epi8('\r'.uint8))
  #       t = mm_cmpeq_epi8(a, mm_set1_epi8('\t'.uint8))
  #       snrt = mm_or_si128(mm_or_si128(s, n), mm_or_si128(r, t))
  #       mask = not cast[uint16](mm_movemask_epi8(snrt))
  #     if mask == 0:
  #       i += 16
  #       continue
  #     i += countTrailingZeroBits(mask)
  #     return
  # elif defined(arm64):
  #   while i + 8 <= input.len:
  #     let
  #       a = vld1_u8(input[i].unsafeAddr)
  #       s = vceq_u8(a, vmov_n_u8(' '.uint8))
  #       n = vceq_u8(a, vmov_n_u8('\n'.uint8))
  #       r = vceq_u8(a, vmov_n_u8('\r'.uint8))
  #       t = vceq_u8(a, vmov_n_u8('\t'.uint8))
  #       snrt = vorr_u8(vorr_u8(s, n), vorr_u8(r, t))
  #       mask = not vget_lane_u64(cast[uint64x1](snrt), 0)
  #     if mask == 0:
  #       i += 8
  #       continue
  #     i += countTrailingZeroBits(mask) div 8
  #     return

  while i < input.len:
    if input[i] in {' ', '\n', '\r', '\t'}:
      inc i
    else:
      break

# when defined(release) and defined(nimHasQuirky):
#   {.pop.}

proc parseJson(input: string): JsonValue =
  let invalidAt = validateUtf8(input)
  if invalidAt != -1:
    error("Invalid UTF-8 character at " & $invalidAt)

  var
    i: int
    stack: seq[(string, JsonValue)]
    root: Option[JsonValue]

  while true:
    skipWhitespace(input, i)

    if i == input.len:
      break

    if root.isSome:
      error("Unexpected non-whitespace character at " & $i)

    var key: string
    if stack.len > 0:
      case stack[^1][1].kind:
      of ObjectValue:
        if input[i] == '}':
          inc i
          var popped = stack.pop()
          popped[1].len = i - popped[1].start
          if stack.len > 0:
            case stack[^1][1].kind
            of ObjectValue:
              stack[^1][1].o.add(move popped)
            of ArrayValue:
              stack[^1][1].a.add(move popped[1])
            else:
              error("Unexpected JsonValue kind, should not happen")
          else:
            root = some(move popped[1])
          continue

        if stack[^1][1].o.len > 0:
          if input[i] != ',':
            error("Expected , at " & $i)
          inc i
          skipWhitespace(input, i)
          if i == input.len:
            break

        if input[i] == '"':
          let
            start = i
            keyLen = parseString(input, i)
          key = unescapeString(input, start + 1, keyLen - 2)
          skipWhitespace(input, i)
          if i == input.len:
            error("Unexpected end of JSON input")
          if input[i] != ':':
            error("Expected : at " & $i)
          inc i
          skipWhitespace(input, i)
          if i == input.len:
            break
        else:
          error("Unexpected " & input[i] & " at " & $i)

      of ArrayValue:
        if input[i] == ']':
          inc i
          var popped = stack.pop()
          popped[1].len = i - popped[1].start
          if stack.len > 0:
            case stack[^1][1].kind
            of ObjectValue:
              stack[^1][1].o.add(move popped)
            of ArrayValue:
              stack[^1][1].a.add(move popped[1])
            else:
              error("Unexpected JsonValue kind, should not happen")
          else:
            root = some(move popped[1])
          continue

        if stack[^1][1].a.len > 0:
          if input[i] != ',':
            error("Expected , at " & $i)
          inc i
          skipWhitespace(input, i)
          if i == input.len:
            break

      else:
        error("Unexpected JsonValue kind, should not happen")

    let start = i
    var value: JsonValue
    case input[i]:
    of '[':
      value = JsonValue(kind: ArrayValue)
      inc i
    of '{':
      value = JsonValue(kind: ObjectValue)
      inc i
    of '"':
      value = JsonValue(kind: StringValue)
      value.len = parseString(input, i)
    of 't', 'f':
      value = JsonValue(kind: BooleanValue, b: parseBoolean(input, i))
      value.len = i - start
    of 'n':
      parseNull(input, i)
      value = JsonValue(kind: NullValue)
      value.len = i - start
    of '-', '0' .. '9':
      value = JsonValue(kind: NumberValue)
      value.len = parseNumber(input, i)
    else:
      error("Unexpected " & input[i] & " at " & $i)

    value.start = start

    if value.kind in {ArrayValue, ObjectValue}:
      stack.add((move key, move value))
    elif stack.len > 0:
      case stack[^1][1].kind:
      of ArrayValue:
        stack[^1][1].a.add(value)
      of ObjectValue:
        for j in 0 ..< stack[^1][1].o.len:
          if stack[^1][1].o[j][0] == key:
            error("Duplicate object key: " & key)
        stack[^1][1].o.add((move key, value))
      else:
        error("Unexpected JsonValue kind, should not happen")
    else:
      root = some(value)

  if stack.len > 0 or not root.isSome:
    error("Unexpected end of JSON input")

  when defined(js):
    return root.get
  else:
    return move root.get

proc fromJson*(v: var bool, value: JsonValue, input: string)
proc fromJson*(v: var SomeUnsignedInt, value: JsonValue, input: string)
proc fromJson*(v: var SomeSignedInt, value: JsonValue, input: string)
proc fromJson*(v: var SomeFloat, value: JsonValue, input: string)
proc fromJson*(v: var char, value: JsonValue, input: string)
proc fromJson*(v: var string, value: JsonValue, input: string)
proc fromJson*(v: var std.JsonNode, value: JsonValue, input: string)
proc fromJson*[T: array](v: var T, value: JsonValue, input: string)
proc fromJson*[T: enum](v: var T, value: JsonValue, input: string)
proc fromJson*[T: tuple](v: var T, value: JsonValue, input: string)
proc fromJson*[T: distinct](v: var T, value: JsonValue, input: string)
proc fromJson*[T](v: var Option[T], value: JsonValue, input: string)
proc fromJson*[T](v: var seq[T], value: JsonValue, input: string)
proc fromJson*[T](v: var (SomeSet[T] | set[T]), value: JsonValue, input: string)
proc fromJson*[T](v: var SomeTable[string, T], value: JsonValue, input: string)
proc fromJson*[T: ref](v: var T, value: JsonValue, input: string)
proc fromJson*[T: object](obj: var T, value: JsonValue, input: string)
proc fromJson*(v: var RawJson, value: JsonValue, input: string)

proc fromJson*(v: var bool, value: JsonValue, input: string) =
  if value.kind == BooleanValue:
    v = value.b
  elif value.kind == NullValue:
    discard
  else:
    error(
      "Expected " & $BooleanValue & ", got " & $value.kind &
      " at " & $value.start
    )

proc fromJson*(v: var SomeUnsignedInt, value: JsonValue, input: string) =
  if value.kind == NumberValue:
    # The first character is validated as {'-', '0' .. '9'}

    if input[value.start] == '-':
      error("Unexpected negative at " & $value.start)

    var ni = value.start
    while ni < value.start + value.len:
      if input[ni] notin {'0' .. '9'}:
        error("Invalid number at " & $value.start)
      let
        c = cast[type(v)](ord(input[ni]) - ord('0'))
        after = v * 10 + c
      if c == 0 or v < after:
        v = after
      else:
        error("Number out of valid range at " & $value.start)
      inc ni

  elif value.kind == NullValue:
    discard
  else:
    error(
      "Expected " & $NumberValue & ", got " & $value.kind &
      " at " & $value.start
    )

proc fromJson*(v: var SomeSignedInt, value: JsonValue, input: string) =
  if value.kind == NumberValue:
    # The first character is validated as {'-', '0' .. '9'}

    var
      sign = cast[type(v)](-1)
      ni = value.start

    if input[ni] == '-':
      sign = 1
      inc ni

    while ni < value.start + value.len:
      if input[ni] notin {'0' .. '9'}:
        error("Invalid number at " & $value.start)
      let c = cast[type(v)](ord(input[ni]) - ord('0'))
      if v >= (type(v).low + c) div 10:
        v = v * 10 - c
      else:
        error("Number out of valid range at " & $value.start)
      inc ni

    if sign == -1 and v == type(v).low:
      error("Number out of valid range at " & $value.start)
    else:
      v *= sign

  elif value.kind == NullValue:
    discard
  else:
    error(
      "Expected " & $NumberValue & ", got " & $value.kind &
      " at " & $value.start
    )

proc fromJson*(v: var SomeFloat, value: JsonValue, input: string) =
  if value.kind == NumberValue:
    let chars = parseFloat(input, v, value.start)
    if chars != value.len:
      error("Invalid float at " & $value.start)
  elif value.kind == NullValue:
    discard
  else:
    error(
      "Expected " & $NumberValue & ", got " & $value.kind &
      " at " & $value.start
    )

proc fromJson*(v: var char, value: JsonValue, input: string) =
  if value.kind == StringValue:
    if value.len == 3: # "c"
      v = input[value.start + 1]
    else:
      error("Too many bytes for char at " & $value.start)
  elif value.kind == NullValue:
    discard
  else:
    error(
      "Expected " & $StringValue & ", got " & $value.kind &
      " at " & $value.start
    )

proc fromJson*(v: var string, value: JsonValue, input: string) =
  if value.kind == StringValue:
    v = value.unescapeString(input)
  elif value.kind == NullValue:
    discard
  else:
    error(
      "Expected " & $StringValue & ", got " & $value.kind &
      " at " & $value.start
    )

proc fromJson*(v: var std.JsonNode, value: JsonValue, input: string) =

  proc fromJsonInternal(
    v: var std.JsonNode,
    value: JsonValue,
    input: string,
    depth: int
  ) =
    if depth == 100:
      error("Reached maximum nested depth at " & $value.start)
    case value.kind:
    of StringValue:
      v = std.newJString(value.unescapeString(input))
    of NumberValue:
      # Try integer first
      try:
        var tmp: int
        fromJson(tmp, value, input)
        v = std.newJInt(tmp)
        return
      except:
        discard
      # Fall back to float
      try:
        var tmp: float
        fromJson(tmp, value, input)
        v = std.newJFloat(tmp)
        return
      except:
        discard
      error("Invalid number at " & $value.start)
    of BooleanValue:
      v = std.newJBool(value.b)
    of NullValue:
      v = std.newJNull()
    of ObjectValue:
      v = std.newJObject()
      for i in 0 ..< value.o.len:
        var tmp: std.JsonNode
        fromJsonInternal(tmp, value.o[i][1], input, depth + 1)
        std.`[]=`(v, value.o[i][0], move tmp)
    of ArrayValue:
      v = std.newJArray()
      for i in 0 ..< value.a.len:
        var tmp: std.JsonNode
        fromJsonInternal(tmp, value.a[i], input, depth + 1)
        std.add(v, move tmp)

  fromJsonInternal(v, value, input, 0)

proc fromJson*[T: array](v: var T, value: JsonValue, input: string) =
  if value.kind == ArrayValue:
    if v.len == value.a.len:
      for i in 0 ..< value.a.len:
        fromJson(v[i], value.a[i], input)
    else:
      error(
        "Expected array of length " & $v.len &
        ", got " & $value.a.len & " at " & $value.start)

  elif value.kind == NullValue:
    discard
  else:
    error(
      "Expected " & $ArrayValue & ", got " & $value.kind &
      " at " & $value.start
    )

proc fromJson*[T: enum](v: var T, value: JsonValue, input: string) =
  if value.kind == NumberValue:
    var tmp: int
    fromJson(tmp, value, input)
    when T is HoleyEnum:
      for x in enumutils.items(T):
        if ord(x) == tmp:
          v = T(tmp)
          return
    else:
      if tmp >= ord(T.low) and tmp <= ord(T.high):
        v = T(tmp)
        return
    error("Invalid enum value at " & $value.start)
  elif value.kind == StringValue:
    let s = value.unescapeString(input)
    when T isnot HoleyEnum:
      for x in T:
        if s == $x:
          v = x
          return
    error("Invalid enum value at " & $value.start)
  elif value.kind == NullValue:
    discard
  else:
    error(
      "Expected " & $NumberValue & " or " & $StringValue &
      ", got " & $value.kind & " at " & $value.start
    )

proc fromJson*[T: tuple](v: var T, value: JsonValue, input: string) =
  if value.kind == NullValue:
    return

  if value.kind == ArrayValue:
    var i: int
    for k, v in v.fieldPairs:
      if i < value.a.len:
        fromJson(v, value.a[i], input)
      inc i
    return

  when T.isNamedTuple():
    if value.kind == ObjectValue:
      for k, v in v.fieldPairs:
        for i in 0 ..< value.o.len:
          if value.o[i][0] == k:
            fromJson(v, value.o[i][1], input)
            break
      return
    else:
      error(
        "Expected " & $ObjectValue & " or " & $ArrayValue &
        ", got " & $value.kind & " at " & $value.start
      )
  else:
    error(
      "Expected " & $ArrayValue & ", got " & $value.kind &
      " at " & $value.start
    )

proc fromJson*[T: distinct](v: var T, value: JsonValue, input: string) =
  var tmp: T.distinctBase
  fromJson(tmp, value, input)
  v = cast[T](tmp)

proc fromJson*[T](v: var Option[T], value: JsonValue, input: string) =
  if value.kind == NullValue:
    v = none(T)
  else:
    var tmp: T
    fromJson(tmp, value, input)
    v = some(move tmp)

proc fromJson*[T](v: var seq[T], value: JsonValue, input: string) =
  if value.kind == ArrayValue:
    for i in 0 ..< value.a.len:
      var tmp: T
      fromJson(tmp, value.a[i], input)
      v.add(move tmp)
  elif value.kind == NullValue:
    discard
  else:
    error(
      "Expected " & $ArrayValue & ", got " & $value.kind &
      " at " & $value.start
    )

proc fromJson*[T](v: var (SomeSet[T] | set[T]), value: JsonValue, input: string) =
  if value.kind == ArrayValue:
    for i in 0 ..< value.a.len:
      var tmp: T
      fromJson(tmp, value.a[i], input)
      v.incl(move tmp)
  elif value.kind == NullValue:
    discard
  else:
    error(
      "Expected " & $ArrayValue & ", got " & $value.kind &
      " at " & $value.start
    )

proc fromJson*[T](v: var SomeTable[string, T], value: JsonValue, input: string) =
  if value.kind == ObjectValue:
    when v is ref:
      new(v)
    for i in 0 ..< value.o.len:
      var tmp: T
      fromJson(tmp, value.o[i][1], input)
      v[value.o[i][0]] = move tmp
  elif value.kind == NullValue:
    discard
  else:
    error(
      "Expected " & $ObjectValue & ", got " & $value.kind &
      " at " & $value.start
    )

proc fromJson*[T: ref](v: var T, value: JsonValue, input: string) =
  if value.kind == NullValue:
    discard
  else:
    new(v)
    fromJson(v[], value, input)

proc discriminator(obj: NimNode): NimNode =
  var ti = obj.getTypeImpl()
  while ti.kind != nnkObjectTy:
    ti = ti[0].getTypeImpl()
  for c1 in ti.children:
    if c1.kind == nnkRecList:
      for c2 in c1.children:
        if c2.kind == nnkRecCase:
          for c3 in c2.children:
            if c3.kind == nnkIdentDefs:
              for c4 in c3.children:
                if c4.kind == nnkSym:
                  return c4

macro isObjectVariant(obj: typed): bool =
  if discriminator(obj) != nil:
    ident("true")
  else:
    ident("false")

macro discriminatorFieldName(obj: typed): untyped =
  newLit($discriminator(obj))

macro discriminatorField(obj: typed): untyped =
  # Not entirely sure why this is necessary but it seems to be
  let fieldName = discriminator(obj)
  return quote do:
    `obj`.`fieldName`

macro newObjectVariant(obj: typed, value: typed): untyped =
  let
    typ = obj.getTypeInst()
    fieldName = discriminator(obj)
  return quote do:
    `obj` = `typ`(`fieldName`: `value`)

template json*(v: string) {.pragma.}

proc validateTags(tags: static seq[string]) =
  when tags.len > 4:
    {.error: ("Too many JSON field tags").}
  when tags.len >= 2:
    when tags[1] notin ["", "omitempty", "required", "string"]:
      {.error: ("Unrecognized JSON field tag: " & tags[1]).}
  when tags.len >= 3:
    when tags[2] notin ["", "omitempty", "required", "string"]:
      {.error: ("Unrecognized JSON field tag: " & tags[2]).}
  when tags.len >= 4:
    when tags[3] notin ["", "omitempty", "required", "string"]:
      {.error: ("Unrecognized JSON field tag: " & tags[3]).}

proc fromJson*[T: object](obj: var T, value: JsonValue, input: string) =
  if value.kind == ObjectValue:
    when obj.isObjectVariant:
      # Do the object variant discriminator field first
      var foundDiscriminator = false
      for k, v in obj.fieldPairs:
        if k == obj.discriminatorFieldName:
          when v.hasCustomPragma(json):
            const
              customPragmaVal = v.getCustomPragmaVal(json)
              tags = customPragmaVal.split(',')
            validateTags(tags)
            when tags[0] == "-" and tags.len == 1: # "-" case
              {.error: $T & " variant discriminator field cannot be omitted".}
            else:
              const renamedField = if tags[0] != "": tags[0] else: k
              # TODO: stringFlag
              for i in 0 ..< value.o.len:
                if value.o[i][0] == renamedField:
                  var tmp: type(obj.discriminatorField)
                  fromJson(tmp, value.o[i][1], input)
                  foundDiscriminator = true
                  newObjectVariant(obj, tmp)
                  break
              if not foundDiscriminator:
                error("Missing required discriminator: " & renamedField)
          else:
            for i in 0 ..< value.o.len:
              if value.o[i][0] == k:
                var tmp: type(obj.discriminatorField)
                fromJson(tmp, value.o[i][1], input)
                foundDiscriminator = true
                newObjectVariant(obj, tmp)
                break
            if not foundDiscriminator:
              error("Missing required discriminator: " & k)

    template workAroundNimIssue19773(k, v) =
      when v.hasCustomPragma(json):
        const
          customPragmaVal = v.getCustomPragmaVal(json)
          tags = customPragmaVal.split(',')
        validateTags(tags)
        when tags[0] == "-" and tags.len == 1: # "-" case
          discard
        else:
          const
            requiredFlag = "required" in tags[1 .. ^1]
            stringFlag = "string" in tags[1 .. ^1]
            renamedField = if tags[0] != "": tags[0] else: k
          when requiredFlag:
            var found: bool
          for i in 0 ..< value.o.len:
            if value.o[i][0] == renamedField:
              when requiredFlag:
                found = value.o[i][1].kind != NullValue
              when stringFlag:
                when v is (SomeNumber | Option[SomeNumber]):
                  if value.o[i][1].kind == StringValue:
                    var tmp = JsonValue(kind: NumberValue)
                    tmp.start = value.o[i][1].start + 1
                    tmp.len = value.o[i][1].len - 2
                    parseNumber(input, tmp.start, tmp.len)
                    fromJson(v, tmp, input)
                  else:
                    fromJson(v, value.o[i][1], input)
                else:
                  {.error: "Using the string JSON option only applies to integer and floating-point fields".}
              else:
                fromJson(v, value.o[i][1], input)
              break
          when requiredFlag:
            if not found:
              error("Missing required field: " & renamedField)
      else:
        for i in 0 ..< value.o.len:
          if value.o[i][0] == k:
            fromJson(v, value.o[i][1], input)
            break

    for k, v in obj.fieldPairs:
      when obj.isObjectVariant:
        when k != obj.discriminatorFieldName:
          workAroundNimIssue19773(k, v)
      else:
        workAroundNimIssue19773(k, v)

  elif value.kind == NullValue:
    discard
  else:
    error(
      "Expected " & $ObjectValue & ", got " & $value.kind &
      " at " & $value.start
    )

proc fromJson*(v: var RawJson, value: JsonValue, input: string) =
  when defined(js):
    for i in 0 ..< value.len:
      v.string.add input[value.start + i]
  else:
    if value.len > 0:
      v.string.setLen(value.len)
      copyMem(v.string[0].addr, input[value.start].unsafeAddr, value.len)

proc fromJson*[T](x: typedesc[T], input: string): T =
  let root = parseJson(input)
  result.fromJson(root, input)

proc fromJson*[T](x: typedesc[T], input: RawJson): T =
  fromJson(x, input.string)

proc isEmpty(src: bool): bool
proc isEmpty(src: SomeUnsignedInt): bool
proc isEmpty(src: SomeSignedInt): bool
proc isEmpty(src: SomeFloat): bool
proc isEmpty(src: char): bool
proc isEmpty(src: string): bool
proc isEmpty(src: std.JsonNode): bool
proc isEmpty[T: array](src: T): bool
proc isEmpty[T: enum](src: T): bool
proc isEmpty[T: tuple](src: T): bool
proc isEmpty[T: distinct](src: T): bool
proc isEmpty[T](src: Option[T]): bool
proc isEmpty[T](src: seq[T]): bool
proc isEmpty[T](src: (SomeSet[T] | set[T])): bool
proc isEmpty[T](src: SomeTable[string, T]): bool
proc isEmpty[T: ref](src: T): bool
proc isEmpty[T: object](src: T): bool
proc isEmpty(src: RawJson): bool

proc isEmpty(src: bool): bool =
  not src

proc isEmpty(src: SomeUnsignedInt): bool =
  src == 0

proc isEmpty(src: SomeSignedInt): bool =
  src == 0

proc isEmpty(src: SomeFloat): bool =
  src == 0

proc isEmpty(src: char): bool =
  src == 0.char

proc isEmpty(src: string): bool =
  src == ""

proc isEmpty(src: std.JsonNode): bool =
  src == nil

proc isEmpty[T: array](src: T): bool =
  false

proc isEmpty[T: enum](src: T): bool =
  false

proc isEmpty[T: tuple](src: T): bool =
  when T.isNamedTuple():
    for _, v in src.fieldPairs:
      if not v.isEmpty():
        return false
  else:
    for v in src:
      if not v.isEmpty():
        return false
  true

proc isEmpty[T: distinct](src: T): bool =
  src.distinctBase.isEmpty()

proc isEmpty[T](src: Option[T]): bool =
  not src.isSome

proc isEmpty[T](src: seq[T]): bool =
  src.len == 0

proc isEmpty[T](src: (SomeSet[T] | set[T])): bool =
  src.len == 0

proc isEmpty[T](src: SomeTable[string, T]): bool =
  false

proc isEmpty[T: ref](src: T): bool =
  src == nil

proc isEmpty[T: object](src: T): bool =
  for _, v in src.fieldPairs:
    when v.hasCustomPragma(json):
      const
        customPragmaVal = v.getCustomPragmaVal(json)
        tags = customPragmaVal.split(',')
      when tags[0] == "-" and tags.len == 1: # "-" case
        discard # Skipped fields are empty
      else:
        if not v.isEmpty():
          return false
    else:
      if not v.isEmpty():
        return false
  true

proc isEmpty(src: RawJson): bool =
  src.string == ""

proc toJson*(src: bool, s: var string)
proc toJson*(src: SomeUnsignedInt, s: var string)
proc toJson*(src: SomeSignedInt, s: var string)
proc toJson*(src: SomeFloat, s: var string)
proc toJson*(src: char, s: var string)
proc toJson*(src: string, s: var string)
proc toJson*(src: std.JsonNode, s: var string)
proc toJson*[T: array](src: T, s: var string)
proc toJson*[T: enum](src: T, s: var string)
proc toJson*[T: tuple](src: T, s: var string)
proc toJson*[T: distinct](src: T, s: var string)
proc toJson*[T](src: Option[T], s: var string)
proc toJson*[T](src: seq[T], s: var string)
proc toJson*[T](src: (SomeSet[T] | set[T]), s: var string)
proc toJson*[T](src: SomeTable[string, T], s: var string)
proc toJson*[T: ref](src: T, s: var string)
proc toJson*[T: object](src: T, s: var string)
proc toJson*(src: RawJson, s: var string)

proc toJson*(src: bool, s: var string) =
  if src:
    s.add "true"
  else:
    s.add "false"

proc toJson*(src: SomeUnsignedInt, s: var string) =
  s.add $src

proc toJson*(src: SomeSignedInt, s: var string) =
  s.add $src

proc toJson*(src: SomeFloat, s: var string) =
  let cls = classify(src)
  case cls:
  of fcNan, fcInf, fcNegInf:
    error("Invalid float value (NaN or Inf)")
  of fcZero, fcNegZero:
    s.add '0'
  else: # fcNormal, fcSubnormal
    s.addFloat src # Same as std/json

proc toJson*(src: char, s: var string) =
  if src < 32.char or src == 127.char:
    error("Cannot JSON encode a control character in one byte")
  elif src >= 128.char:
    error ("Cannot JSON encode a non-ASCII character in one byte")
  else:
    s.add '"'
    s.add src
    s.add '"'

proc toJson*(src: string, s: var string) =
  s.add '"'

  var i, copyStart: int
  while i < src.len:
    let c = src[i]
    if cast[uint8](c) >= 128:
      let r = src.validRuneAt(i)
      if r.isSome:
        i += r.unsafeGet.unsafeSize()
        continue
      error("Invalid UTF-8 in string")
    elif cast[uint8](c) >= 32 and c != '"' and c != '\\' and c != '\127':
      inc i
    else:
      copy(s, src, copyStart, i - copyStart)
      case c:
      of '"': s.add """\""""
      of '\\': s.add """\\"""
      of '\b': s.add """\b"""
      of '\f': s.add """\f"""
      of '\n': s.add """\n"""
      of '\r': s.add """\r"""
      of '\t': s.add """\t"""
      else: # of '\0' .. '\7', '\11', '\14' .. '\31', '\127':
        const hex = "0123456789abcdef"
        s.add """\u00"""
        s.add hex[cast[uint8](c) shr 4]
        s.add hex[cast[uint8](c) and 0xf]
      inc i
      copyStart = i

  copy(s, src, copyStart, i - copyStart)

  s.add '"'

proc toJson*(src: std.JsonNode, s: var string) =
  if src == nil:
    s.add "null"
  else:
    case src.kind:
    of JNull:
      s.add "null"
    of JBool:
      std.getBool(src).toJson(s)
    of JInt:
      std.getInt(src).toJson(s)
    of JFloat:
      std.getFloat(src).toJson(s)
    of JString:
      std.getStr(src).toJson(s)
    of JArray:
      s.add '['
      var i = 0
      for e in std.items(src):
        if i != 0:
          s.add ','
        e.toJson(s)
        inc i
      s.add ']'
    of JObject:
      s.add '{'
      var i = 0
      for k, v in std.pairs(src):
        if i != 0:
          s.add ','
        k.toJson(s)
        s.add ':'
        v.toJson(s)
        inc i
      s.add '}'

proc toJson*[T: array](src: T, s: var string) =
  s.add '['
  for i, e in src:
    if i > 0:
      s.add ','
    e.toJson(s)
  s.add']'

proc toJson*[T: enum](src: T, s: var string) =
  ($src).toJson(s)

proc toJson*[T: tuple](src: T, s: var string) =
  when T.isNamedTuple():
    s.add '{'
    var i: int
    for k, v in v.fieldPairs:
      if i > 0:
        s.add ','
      k.toJson(s)
      s.add ':'
      v.toJson(s)
      inc i
    s.add '}'
  else:
    s.add '['
    for i, e in src:
      if i > 0:
        s.add ','
      e.toJson(s)
    s.add ']'

proc toJson*[T: distinct](src: T, s: var string) =
  cast[T.distinctBase](src).toJson(s)

proc toJson*[T](src: Option[T], s: var string) =
  if src.isSome:
    src.unsafeGet.toJson(s)
  else:
    s.add "null"

proc toJson*[T](src: seq[T], s: var string) =
  s.add '['
  for i, e in src:
    if i > 0:
      s.add ','
    e.toJson(s)
  s.add ']'

proc toJson*[T](src: (SomeSet[T] | set[T]), s: var string) =
  s.add '['
  for i, e in src:
    if i > 0:
      s.add ','
    e.toJson(s)
  s.add']'

proc toJson*[T](src: SomeTable[string, T], s: var string) =
  s.add '{'
  var i: int
  for k, v in src.pairs:
    if i > 0:
      s.add ','
    k.toJson(s)
    s.add ':'
    v.toJson(s)
    inc i
  s.add '}'

proc toJson*[T: ref](src: T, s: var string) =
  if src == nil:
    s.add "null"
  else:
    src[].toJson(s)

proc toJson*[T: object](src: T, s: var string) =
  s.add '{'

  var i: int
  for k, v in src.fieldPairs:
    when v.hasCustomPragma(json):
      const
        customPragmaVal = v.getCustomPragmaVal(json)
        tags = customPragmaVal.split(',')
      validateTags(tags)
      when tags[0] == "-" and tags.len == 1: # "-" case
        discard
      else:
        template body() =
          const renamedKey =
            if tags[0] != "":
              tags[0]
            else:
              k
          if i > 0:
            s.add ','
          const tmp = renamedKey.toJson() & ':'
          s.add tmp
          const stringFlag = "string" in tags[1 .. ^1]
          when stringFlag:
            when v is (SomeNumber | Option[SomeNumber]):
              s.add '"'
              v.toJson(s)
              s.add '"'
            else:
              {.error: "Using the string JSON option only applies to integer and floating-point fields".}
          else:
            v.toJson(s)
          inc i

        const omitempty = "omitempty" in tags[1 .. ^1]
        when omitempty:
          if not v.isEmpty():
            body()
        else:
          body()

    else:
      if i > 0:
        s.add ','
      const tmp = k.toJson() & ':'
      s.add tmp
      v.toJson(s)
      inc i

  s.add '}'

proc toJson*(src: RawJson, s: var string) =
  when defined(js):
    for c in src.string:
      s.add c
  else:
    if src.string.len > 0:
      let tmp = s.len
      s.setLen(tmp + src.string.len)
      copyMem(s[tmp].addr, src.string[0].unsafeAddr, src.string.len)

proc toJson*[T](src: T): string =
  src.toJson(result)

proc dump(node: JsonValue, input: string): string =
  ## For testing
  case node.kind
  of StringValue:
    result.add input[node.start ..< node.start + node.len]
  of NumberValue:
    result.add input[node.start ..< node.start + node.len]
  of BooleanValue:
    if node.b:
      result.add "true"
    else:
      result.add "false"
  of NullValue:
    result.add "null"
  of ObjectValue:
    result.add '{'
    for i in 0 ..< node.o.len:
      if i > 0:
        result.add ','
      let tmp = node.o[i][0].toJson()
      result.add tmp
      result.add ':'
      result.add dump(node.o[i][1], input)
    result.add '}'
  of ArrayValue:
    result.add '['
    for i in 0 ..< node.a.len:
      if i > 0:
        result.add ','
      result.add dump(node.a[i], input)
    result.add ']'

{.pop.}

when defined(release):
  {.pop.}
