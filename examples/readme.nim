import sunny, std/base64

block:
  type MyType = object
    a: int
    b: string

  let instance = MyType.fromJson("""{"a":3,"b":"foo"}""")
  assert instance.a == 3
  assert instance.b == "foo"

block:
  type MyType = object
    a: int
    b: string

  let instance = MyType(a: 42, b: "boo")
  echo instance.toJson() # """{"a":42,"b":"boo"}"""

block:
  type Example = object
    myField {.json: "my_field".}: int

  let instance = Example.fromJson("""{"my_field":9000}""")
  assert instance.myField == 9000

  echo Example(myField: -1).toJson() # """{"my_field":-1}"""

block:
  type Example = object
    myField {.json: "-".}: int

  echo Example(myField: 42).toJson() # """{}"""

block:
  type Example = object
    foo {.json: ",omitempty".}: string

  echo Example(foo: "").toJson() # """{}"""
  echo Example(foo: "bar").toJson() # """{"foo":"bar"}"""

block:
  type Example = object
    x {.json: ",required".}: int

  # Both of these raise an exception since `x` is tagged as a required field.
  doAssertRaises CatchableError:
    discard Example.fromJson("""{}""")
  doAssertRaises CatchableError:
    discard Example.fromJson("""{"x":null}""")

  # This works since `x` is present and non-`null`.
  let instance = Example.fromJson("""{"x":9000}""")
  assert instance.x == 9000

block:
  type Example = object
    x {.json: ",string".}: int

  let instance = Example.fromJson("""{"x":"42"}""")
  assert instance.x == 42

  echo Example(x: 42).toJson() # """{"x":"42"}"""

block:
  type Example = object
    myField {.json: "my_field,omitempty,string".}: int

block:
  type Example = object
    data: string

  proc fromJson(v: var Example, value: JsonValue, input: string) =
    # Call the default `fromJson` in `sunny` to do the initial parsing.
    sunny.fromJson(v, value, input)
    # Now overwrite `data` with the base64 decoded raw bytes.
    v.data = base64.decode(v.data)

  proc toJson(src: Example, s: var string) =
    # Here we make a new temporary instance and assign `data` to be the
    # base64 encoded string instead of the raw bytes.
    var tmp: Example
    tmp.data = base64.encode(src.data)
    # Call the default `toJson` in `sunny` now that `data` is safely base64 encoded.
    sunny.toJson(tmp, s)

block:
  type Container = object
    `type`: string
    `object`: RawJson

  let a = Container.fromJson("""{"type":"event","object":{}}""")

  type Event = object
    # ...

  let b = Event.fromJson(a.`object`)
