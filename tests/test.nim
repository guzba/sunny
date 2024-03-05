import unicody, sunny {.all.}, std/strutils, std/options, std/sets, std/tables

from std/json as std import nil

doAssertRaises CatchableError:
  discard parseJson("")

doAssertRaises CatchableError:
  discard parseJson("-")

doAssertRaises CatchableError:
  discard parseJson("+1")

doAssertRaises CatchableError:
  discard parseJson("01")

doAssertRaises CatchableError:
  discard parseJson("0_1")

doAssertRaises CatchableError:
  discard parseJson("0.")

doAssertRaises CatchableError:
  discard parseJson("0.2.3")

doAssertRaises CatchableError:
  discard parseJson("0.e")

doAssertRaises CatchableError:
  discard parseJson("3e+")

doAssertRaises CatchableError:
  discard parseJson("3e+0.2")

doAssertRaises CatchableError:
  discard parseJson("3e1e2")

doAssertRaises CatchableError:
  discard parseJson("True")

doAssertRaises CatchableError:
  discard parseJson("False")

doAssertRaises CatchableError:
  discard parseJson("Null")

doAssertRaises CatchableError:
  discard parseJson("[")

doAssertRaises CatchableError:
  discard parseJson("[[]")

doAssertRaises CatchableError:
  discard parseJson("[][]")

doAssertRaises CatchableError:
  discard parseJson("{")

doAssertRaises CatchableError:
  discard parseJson("{{}")

doAssertRaises CatchableError:
  discard parseJson("{}{}")

doAssertRaises CatchableError:
  discard parseJson("""{"a":"a","b":"b"""")

doAssertRaises CatchableError:
  discard parseJson("""{"\u":"abc"}""")

doAssertRaises CatchableError:
  discard parseJson("""{"a":"a","a":"b"}""")

block:
  let testCases = [
    "\"\"",
    "\"abc\"",
    """"\"\\\b\f\n\r\t""""
  ]
  for s in testCases:
    # echo string.fromJson(s).toJson()
    doAssert string.fromJson(s).toJson() == s

block:
  doAssert int32.fromJson("2147483647") == 0x7FFFFFFF

  doAssert int16.fromJson("-32768") == 0b1000000000000000'i16

  doAssertRaises CatchableError:
    discard int16.fromJson("65535")

  doAssertRaises CatchableError:
    discard int16.fromJson("-32769")

  doAssert uint32.fromJson("4294967295") == 0xFFFFFFFF'u32
  doAssert uint32.fromJson("0") == 0'u32
  doAssert uint32.fromJson("1") == 1'u32
  doAssert uint32.fromJson("99") == 99'u32
  doAssert uint32.fromJson("5404810") == 5404810'u32

  doAssertRaises CatchableError:
    discard uint32.fromJson("-1")

  doAssertRaises CatchableError:
    discard uint16.fromJson("4294967295")

block:
  doAssert char.fromJson(""""a"""") == 'a'

  doAssertRaises CatchableError:
    discard char.fromJson("")

  doAssertRaises CatchableError:
    discard char.fromJson("ab")

  doAssertRaises CatchableError:
    discard char.fromJson("🔒")

block:
  for i in 0 .. 7:
    var s = newString(1)
    s[0] = i.char
    doAssert s.toJson() == """"\u000""" & $i & """""""
  doAssert "\11".toJson() == """"\u000b""""
  for i in 14 .. 31:
    var s = newString(1)
    s[0] = i.char
    doAssert s.toJson() == """"\u00""" & toHex(i, 2).toLowerAscii() & """""""
  doAssert "\127".toJson() == """"\u007f""""

block:
  let testCases = [
    "0",
    "true",
    "false",
    "null",
    "\"\"",
    "[]",
    "[100,200,300]",
    "{}",
    "{\"\":\"\"}",
    "{\"a\":\"b\"}",
    "{\"x\":true}",
    "{\"y\":null}",
    "{\"a\":[{\"b\":[\"c\",\"d\",\"efg\"]}]}",
    """{"bbq\"\\\b\f\n\r\tae":"asdf"}"""
    # """{"\u0000":"aeiou"}"""
  ]

  for s in testCases:
    doAssert dump(parseJson(s), s) == s

  for s in testCases:
    doAssert RawJson.fromJson(s).string == s

# block:
#   let input = " [  [  [ [ ] ] ]     ]  "
#   doAssert dump(input, parseJson(input)) == "[[[[]]]]"

block:
  for i in highSurrogateMin .. highSurrogateMax:
    doAssertRaises CatchableError:
      discard string.fromJson("\"\\u" & toHex(i, 4) & '\"')

  for i in lowSurrogateMin .. lowSurrogateMax:
    doAssertRaises CatchableError:
      discard string.fromJson("\"\\u" & toHex(i, 4) & '\"')

  for i in highSurrogateMin .. highSurrogateMin: # highSurrogateMax
    for j in lowSurrogateMin .. lowSurrogateMax:
      discard string.fromJson(
        '"' &
        "\\u" & toHex(i, 4) &
        "\\u" & toHex(j, 4) &
        '"'
      )

  for i in 0 ..< highSurrogateMin:
    discard string.fromJson('"' & "\\u" & toHex(i, 4) & '"')
  for i in lowSurrogateMax + 1 ..< 0xffff:
    discard string.fromJson('"' & "\\u" & toHex(i, 4) & '"')

block:
  doAssert (int, int, int).fromJson("[3, 2, 1]") == (3, 2, 1)
  doAssert (string, char).fromJson("""["zz", "e"]""") == ("zz", 'e')

  type Named = tuple[a: string, b: int]

  doAssert Named.fromJson("""["eee", 3]""") == (a: "eee", b: 3)
  doAssert Named.fromJson("""["eee"]""") == (a: "eee", b: 0)

  doAssertRaises CatchableError:
    discard Named.fromJson("""[3]""")

  doAssert Named.fromJson("""{"b":3,"a":"ok"}""") == (a: "ok", b: 3)

  doAssertRaises CatchableError:
    discard (int, string).fromJson("""{"b":3,"a":"ok"}""")

  doAssertRaises CatchableError:
    discard Named.fromJson(""""asdf""")

block:
  doAssert array[1, int].fromJson("[1]") == [1]

block:
  type
    MaterialKinds = enum
      InvalidMaterial, WoodMaterial, SteelMaterial

    Thing = object
      material: MaterialKinds

  doAssert Thing.fromJson("""{"material":0}""") ==
      Thing(material: InvalidMaterial)

  doAssert Thing.fromJson("""{"material":2}""") ==
      Thing(material: SteelMaterial)

  doAssertRaises CatchableError:
    discard Thing.fromJson("""{"material":3}""")

block:
  type
    MaterialKinds = enum
      InvalidMaterial, WoodMaterial = 100, SteelMaterial = 113

    Thing = object
      material: MaterialKinds

  doAssert Thing.fromJson("""{"material":0}""") ==
      Thing(material: InvalidMaterial)

  doAssert Thing.fromJson("""{"material":113}""") ==
      Thing(material: SteelMaterial)

  doAssertRaises CatchableError:
    discard Thing.fromJson("""{"material":50}""")

block:
  type
    MaterialKinds = enum
      InvalidMaterial, WoodMaterial = "wood", SteelMaterial = "steel"

    Thing = object
      material: MaterialKinds

  doAssert Thing.fromJson("""{}""") == Thing(material: InvalidMaterial)

  doAssert Thing.fromJson("""{"material":0}""") ==
      Thing(material: InvalidMaterial)

  doAssert Thing.fromJson("""{"material":1}""") ==
      Thing(material: WoodMaterial)

  doAssertRaises CatchableError:
    discard Thing.fromJson("""{"material":3}""")

block:
  type
    MaterialKinds = enum
      InvalidMaterial, WoodMaterial = "wood", SteelMaterial = "steel"

    Thing = object
      material: MaterialKinds

  doAssert Thing.fromJson("""{"material":"wood"}""") ==
      Thing(material: WoodMaterial)

  doAssert Thing.fromJson("""{"material":"steel"}""") ==
      Thing(material: SteelMaterial)

  doAssertRaises CatchableError:
    discard Thing.fromJson("""{"material":""}""")

  doAssertRaises CatchableError:
    discard Thing.fromJson("""{"material":"brick"}""")

block:
  type Deadline = distinct float64

  proc `==`(a, b: Deadline): bool =
    a.float64 == b.float64

  doAssert Deadline.fromJson("1.3") == 1.3.Deadline

block:
  type Reffy = ref object
    a: int
    b: string

  doAssert Reffy.fromJson("null") == nil

  let reffy = Reffy.fromJson("""{"a":3,"b":"cd"}""")
  doAssert reffy.a == 3
  doAssert reffy.b == "cd"

  let r1 = (ref int).fromJson("42")
  doAssert r1[] == 42

  let r2 = (ref seq[float]).fromJson("[4,5,6]")
  doAssert r2[] == @[4d,5,6]

when not defined(js):
  import data/twitter

  block:
    type Twitter = object
      statuses: RawJson
    doAssert Twitter.fromJson(twitterJson).statuses.string == twitterJson[16 ..< ^391]

  block:
    let
      a = std.parseJson(twitterJson)
      b = std.JsonNode.fromJson(twitterJson)
    doAssert std.`==`(a, b)

block:
  doAssertRaises CatchableError:
    discard std.JsonNode.fromJson("[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[[]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]]")

block:
  type Something = object
    kind {.json: "type,omitempty".}: string
    ignore {.json: "-".}: int

  const json = """{"type":"foo","ignore":1}"""

  let something = Something.fromJson(json)

  doAssert something.kind == "foo"
  doAssert something.ignore == 0

  doAssert something.toJson() == """{"type":"foo"}"""
  doAssert Something().toJson() == """{}"""

block:
  type SpecialCase = object
    `-` {.json: "-,".}: int

  const json = """{"-":6}"""

  doAssert SpecialCase.fromJson(json).`-` == 6

block:
  type
    OptionalTest = object
      a: Option[string]
      b: Option[int]
      c: Option[seq[int]]
      foo: Option[Foo]

    Foo = object
      x {.json: "-"}: int

  block:
    let
      test = """{"a":null,"b":null,"c":null,"foo":null}"""
      expected = OptionalTest()
    doAssert OptionalTest.fromJson(test) == expected
    doAssert expected.toJson() == test

  block:
    let test = """{}"""
    doAssert OptionalTest.fromJson(test) == OptionalTest()

  block:
    let
      test = """{"a":null,"b":2,"c":null,"foo":null}"""
      expected = OptionalTest(b: some(2))
    doAssert OptionalTest.fromJson(test) == expected
    doAssert expected.toJson() == test

  block:
    let
      test = """{"a":"","b":null,"c":[],"foo":null}"""
      expected = OptionalTest(a: some(""), c: some(seq[int](@[])))
    doAssert OptionalTest.fromJson(test) == expected
    doAssert expected.toJson() == test

  block:
    let
      test = """{"a":null,"b":null,"c":null,"foo":{"x":4}}"""
      expected = OptionalTest(foo: some(Foo()))
    doAssert OptionalTest.fromJson(test) == expected
    doAssert expected.toJson() == """{"a":null,"b":null,"c":null,"foo":{}}"""

block:
  type
    SkippedField = object
      i {.json: "-".}: int

    OptionalOmitEmptyTest = object
      v {.json: ",omitempty".}: Option[int]
      w {.json: ",omitempty".}: SkippedField

  doAssert OptionalOmitEmptyTest().toJson() == """{}"""
  doAssert OptionalOmitEmptyTest(
    v: some(0),
    w: SkippedField(i: 333)
  ).toJson() == """{"v":0}"""

block:
  type RequiredTest = object
    valid {.json: ",required".}: bool

  doAssertRaises CatchableError:
    discard RequiredTest.fromJson("""{}""")

  doAssertRaises CatchableError:
    discard RequiredTest.fromJson("""{"x":"y"}""")

block:
  type Node = object
    kids: seq[Node]

  var bad: string
  for i in 0 ..< 10_000:
    bad.add "{\"kids\":["

  doAssertRaises CatchableError:
    discard parseJson(bad)

block:
  let s = HashSet[string].fromJson("""["a","b","c","c","c"]""")
  doAssert s.len == 3
  doAssert "a" in s
  doAssert "b" in s
  doAssert "c" in s

block:
  let
    order = ["c", "b", "a"]
    s = OrderedSet[string].fromJson(order.toJson())
  for i, entry in s:
    doAssert order[i] == entry

block:
  let s = set[uint16].fromJson("[3, 4, 5, 5]")
  doAssert 3 in s
  doAssert 4 in s
  doAssert 5 in s

block:
  type MaterialKinds = enum
    InvalidMaterial, WoodMaterial = "wood", SteelMaterial = "steel"

  let s = set[MaterialKinds].fromJson("""["wood","steel"]""")
  doAssert InvalidMaterial notin s
  doAssert WoodMaterial in s
  doAssert SteelMaterial in s

block:
  let t = Table[string, string].fromJson("""{"a":"at","b":"bat","c":"cat"}""")
  doAssert t.len == 3
  doAssert t["a"] == "at"
  doAssert t["b"] == "bat"
  doAssert t["c"] == "cat"

block:
  let t = TableRef[string, string].fromJson("""{"a":"at","b":"bat","c":"cat"}""")
  doAssert t.len == 3
  doAssert t["a"] == "at"
  doAssert t["b"] == "bat"
  doAssert t["c"] == "cat"

block:
  type
    BoxKind = enum
      IntBox, FloatBox, StringBox

    Box1 = ref object
      case kind: BoxKind
      of IntBox:
        i: int
      of FloatBox:
        f: float
      of StringBox:
        s: string

    Box2 = ref object
      case kind {.json:"type".}: BoxKind
      of IntBox:
        i: int
      of FloatBox:
        f: float
      of StringBox:
        s: string

  doAssertRaises CatchableError:
    discard Box1.fromJson("""{}""")

  doAssertRaises CatchableError:
    discard Box2.fromJson("""{"kind":2}""")

  doAssert Box1.fromJson("""{"kind":1,"f":3.14}""").f == 3.14

  doAssert Box2.fromJson("""{"type":1,"f":3.14}""").f == 3.14

block:
  type Holder = object
    b {.json: ",string".}: uint
    c {.json: ",string".}: int
    d {.json: ",string".}: float
    e {.json: ",string".}: Option[float]
    f {.json: ",string".}: Option[int]

  const encoded = """{"b":"3","c":"-1","d":"2.0","e":"3.0","f":"44"}"""

  let holder = Holder(b: 3, c: -1, d: 2.0, e: some(3.0), f: some(44))

  doAssert holder.toJson() == encoded

  doAssert Holder.fromJson(encoded) == holder

# block:
#   type Duplicate = object
#     a: int
#     b {.json: "a".}: string

#   doAssertRaises CatchableError:
#     discard Duplicate().toJson()












# block:
type Something = object
  a: int
  b: bool
  c: string

proc fromJson(v: var Something, value: JsonValue, input: string) =
  echo "from stage1 ", v

  v.c = "cat"

  # defaultFromJson(v, value, input)
  sunny.fromJson(v, value, input)

  echo "from stage2 ", v

  v.a = 8

let something = Something.fromJson("""{"a":9,"b":true,"c":null}""")
echo something

proc toJson(src: Something, s: var string) =
  echo "to stage1"

  # var tmp: string
  # src.defaultToJson(tmp)

  # "base64 encode"
  # "json in json"
  # "hipmunk case deduped objects to lut"

  s.add "wowza"

  echo "to stage2"

echo something.toJson()

# block:
#   type DefaultValues = object
#     x: int = 2
#     f: bool = true

#   echo DefaultValues()

#   echo default(DefaultValues)

#   var a: DefaultValues
#   echo a # (x: 0, f: false)

#   # Does `move` set default values when it resets the var?
#   var b = DefaultValues()
#   discard move b
#   echo b # (x: 0, f: false)

#   proc f(): DefaultValues = # proc `result` behavior
#     discard
#   echo f() # (x: 0, f: false)

#   # array / seq behavior matches `: DefaultValues`, not `= DefaultValues()`
#   var c: array[1, DefaultValues]
#   echo c # [(x: 0, f: false)]

#   const json1 = """{}"""
#   echo DefaultValues.fromJson(json1)

#   const json2 = """[{}]"""
#   echo seq[DefaultValues].fromJson(json2)

#   const json3 = """[{"x":4}]"""
#   echo seq[DefaultValues].fromJson(json3)

# Test toJson scenarios
