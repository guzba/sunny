# Sunny

`nimble install sunny`

[API reference](https://guzba.github.io/sunny/)

Sunny is fast JSON library for Nim that supports field tags like those found in Go. Field tags help make working with real-world JSON comfortable and easy.

## The basics

To parse JSON into an instance, use `fromJson`:

```nim
import sunny

type MyType = object
  a: int
  b: string

let instance = MyType.fromJson("""{"a":3,"b":"foo"}""")
assert instance.a == 3
assert instance.b == "foo"
```

To encode an instance to JSON, use `toJson`:
```nim
import sunny

type MyType = object
  a: int
  b: string

let instance = MyType(a: 42, b: "boo")
echo instance.toJson() # """{"a":42,"b":"boo"}"""
```

## Using field tags

Sunny supports field tags exactly like those found in Go. Field tags are a comma-separated list and the first tag is always used for optionally renaming a field.

The supported tags are currently `rename/skip`, `omitempty`, `required` and `string`.

### Renaming fields

Often the JSON you need to consume (or produce) will not use the style convention you wish it did. This makes being able to rename fields easily very helpful. The new name for a field is **always** the first tag.

This new name will be used by both `fromJson` and `toJson`.

```nim
type Example = object
  myField {.json: "my_field".}: int

let instance = Example.fromJson("""{"my_field":9000}""")
assert instance.myField == 9000

echo Example(myField: -1).toJson() # """{"my_field":-1}"""
```

### Skipping fields

Another common situation is having some fields on an object that you never want to be included in the JSON output. A special tag of "-" indicates the field should be skipped.

This skips the field in both `fromJson` and `toJson`.

```nim
type Example = object
  myField {.json: "-".}: int

echo Example(myField: 42).toJson() # """{}"""
```

### Omitting empty fields

In situations such as providing a JSON API for public consumption, you may want to omit including keys when they contain a default or empty value. This can avoid confusion around if there is difference between `"key":null` and `"key"` not being present.

Using the `omitempty` tag will result in `toJson` not including the field when encoding JSON if the field is empty, meaning the value is 0, an empty string, an empty seq, or an empty object.

(Be mindful of the the leading `,` which leaves first tag empty indicating the field should not be renamed.)

```nim
type Example = object
  foo {.json: ",omitempty".}: string

echo Example(foo: "").toJson() # """{}"""
echo Example(foo: "bar").toJson() # """{"foo":"bar"}"""
```

### Required fields

While this tag does not exist in Go, Sunny supports the `required` tag.

Using this tag indicates that the field must be both present in the JSON and must not be `null`. If the field is missing or `null`, an exception is raised.

```nim
type Example = object
  x {.json: ",required".}: string

# Both of these raise an exception since `x` is tagged as a required field.
let instance = Example.fromJson("""{}""")
let instance = Example.fromJson("""{"x":null}""")

# This works since `x` is present and non-`null`.
let instance = Example.fromJson("""{"x":9000}""")
assert instance.x == 9000
```

### The string field tag

It is quite common to find JSON APIs that encode numbers as strings. This is usually motivated by Javascript which has an interesting approach to numbers.

In Nim, you may want to parse a field as a number (integer or floating-point) even if it may be encoded as a string JSON. Using the `string` field tag makes this easy.

This field tag applies to both `fromJson` and `toJson`.

```nim
type Example = object
  x {.json: ",string".}: int

let instance = Example.fromJson("""{"x":"42"}""")
assert instance.x == 42

echo Example(x: 42).toJson() # """{"x":"42"}"""
```

### Using multiple field tags

Using multiple field tags is supported and easy to do since they are just a comma-separated list:

```nim
type Example = object
  myField {.json: "my_field,omitempty,string".}: int
```

## Custom `fromJson` and `toJson`

While using field tags solves many of the most common problems when working with JSON, sometimes more control is needed.

Taking inspiration from [jsony](https://github.com/treeform/jsony), Sunny supports calling custom `fromJson` and `toJson` hooks for types where you need more control than field tags provide.

For the example below lets imagine that `Example.data` holds binary data. Binary data does not mix with JSON since JSON which must be UTF-8 encoded. By implementing custom `fromJson` and `toJson` procs, the binary data can be transparently base64 encoded/decoded making it perfectly save for JSON.

```nim
import sunny, std/base64

type Example = object
  data: string

proc fromJson*(v: var Example, value: JsonValue, input: string) =
  # Call the default `fromJson` in `sunny` to do the initial parsing.
  sunny.fromJson(v, value, input)
  # Now overwrite `data` with the base64 decoded raw bytes.
  v.data = base64.decode(v.data)

proc toJson*(src: Example, s: var string) =
  # Here we make a new temporary instance and assign `data` to be the
  # base64 encoded string instead of the raw bytes.
  var tmp: Example
  tmp.data = base64.encode(src.data)
  # Call the default `toJson` in `sunny` now that `data` is safely base64 encoded.
  sunny.toJson(tmp, s)
```

To implement behavior similar to [jsony](https://github.com/treeform/jsony)'s `newHook` and `postHook`, try something like this:

```nim
proc fromJson*(v: var Example, value: JsonValue, input: string) =
  # Any code before `sunny.fromJson` is the equivalent of a `newHook`.

  sunny.fromJson(v, value, input)

  # Anything after `sunny.fromJson` is the equivalent of a `postHook`.
```

Note that you do not need to re-implement parsing just to have a custom hook, simply calling `sunny.fromJson` will take care of all the default behaviors including field tags.

## Raw JSON

Some JSON APIs use a form of variant object, where a `type` field will indicate what is stored in another field like `object`. By using `RawJson` you can indicate that a field should be treated as unparsed JSON which can then be parsed into a specific object type at a later time:

```nim
type Container = object
  `type`: string
  `object`: RawJson

let a = Container.fromJson("""{"type":"event","object":{}}""")

type Event = object
  # ...

let b = Event.fromJson(a.`object`.string)
```

## Default behaviors

Sunny's default behavior when parsing fields is loose / not strict.

* Fields are not required (use `required` field tag to become stricter)
* A missing field and `field: null` are treated as the same thing

This means you can easily parse the parts of a JSON blob you care about without a headache.

While Sunny is loose about the presence / absence of fields, Sunny is strict about certain things to protect against unexpected bugs. These include:

* Detecting duplicate keys when parsing JSON (raises an exception instead of last-key-wins or something odd like that).
* Invalid UTF-8 will be detected and raise an exception (JSON must be valid UTF-8).
* All JSON values are validated as part of parsing, avoiding frustrating "parses-on-my-machine" situations cased by things like "10_000" working in Nim's `parseInt` while not being valid JSON.

In addition to those protective measures, Sunny is also an iterative parser. This is very important when parsing untrusted inputs. A recursive parser attempting to parse an adversarial JSON blob can result in a stack overflow, terminating your process with zero information about what happened or why. This is not a great situation to find one-self in.

## Performance

Sunny is a performance-aware library that includes some SIMD-optimized fast-paths. I'll include some benchmarks here later but you can expect significantly faster parsing and encoding than std/json. The performance is ~ the same as that of [jsony](https://github.com/treeform/jsony).

## Testing

To prevent Sunny from causing a crash or otherwise misbehaving on bad JSON, a fuzzer has been run against it. You can run the fuzzer any time by running `nim c -r tests/fuzz.nim`
