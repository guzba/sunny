import sunny, benchy, data/twitter

from std/json as std import nil

from jsony import nil

# import packedjson, packedjson/deserialiser
# import eminim, std/streams, json_serialization

# block: # Does everyone agree?
#   let
#     fromExperiments = Twitter.fromJson(twitterJson)
#     fromJsony = fromJson(twitterJson, Twitter)
#     fromEminim = newStringStream(twitterJson).jsonTo(Twitter)
#     fromJsonSerlization = Json.decode(twitterJson, Twitter, allowUnknownFields = true)
#     fromPackedjson = deserialiser.to(packedjson.parseJson(twitterJson), Twitter)

#   doAssert fromExperiments == fromJsony
#   doAssert fromExperiments == fromEminim
#   doAssert fromExperiments == fromJsonSerlization
#   doAssert fromExperiments == fromPackedjson

# timeIt "experiments/json":
#   discard parseJson(twitterJson)

# timeIt "experiments/json":
#   discard parseJson(twitterJsonNoWhitespace)

# timeIt "jsony":
#   type Empty = object
#   discard fromJson(twitterJson, Empty)

timeIt "sunny fromJson":
  discard Twitter.fromJson(twitterJson)

# timeIt "jsony from json":
#   discard jsony.fromJson(twitterJson, Twitter)

# timeIt "planetis-m/eminim from json":
#   discard newStringStream(twitterJson).jsonTo(Twitter)

# timeIt "experiments/json to std":
#   discard std.JsonNode.fromJson(twitterJson)

# timeIt "jsony to std":
#   discard jsony.fromJson(twitterJson, std.JsonNode)

# timeIt "std/json from json":
#   discard std.parseJson(twitterJson)

# timeIt "packedjson from json":
#   discard deserialiser.to(packedjson.parseJson(twitterJson), Twitter)

# timeIt "json_serialization from json":
#   discard Json.decode(twitterJson, Twitter, allowUnknownFields = true)



# let tmp = Twitter.fromJson(twitterJson)

# echo tmp.toJson().len
# echo jsony.toJson(tmp).len

# timeIt "experiments/json to json":
#   discard tmp.toJson()

# timeIt "jsony to json":
#   discard jsony.toJson(tmp)



# type Something = object
#   a {.json: "b".}: string
#   b {.json: "c".}: string
#   c {.json: "d".}: string
#   d {.json: "e".}: string
#   e {.json: "f".}: string
#   f {.json: "g".}: string
#   g {.json: "h".}: string
#   h {.json: "i".}: string
#   i {.json: "j".}: string
#   j {.json: "k".}: string
#   k {.json: "l".}: string
#   l {.json: "m".}: string
#   m {.json: "n".}: string
#   n {.json: "o".}: string
#   o {.json: "p".}: string
#   p {.json: "q".}: string
#   q {.json: "r".}: string
#   r {.json: "s".}: string
#   s {.json: "t".}: string
#   t {.json: "u".}: string
#   u {.json: "v".}: string
#   v {.json: "w".}: string
#   w {.json: "x".}: string
#   x {.json: "y".}: string
#   y {.json: "z".}: string

# const asdf = """{"b":"a","c":"b","d":"c","e":"d","f":"e","g":"f","h":"g","i":"h","j":"i","k":"j","l":"k","m":"l","n":"m","o":"n","p":"o","q":"p","r":"q","s":"r","t":"s","u":"t","v":"u","w":"v","x":"w","y":"x","z":"y"}"""

# timeIt "asdf":
#   discard Something.fromJson(asdf)

# block:
#   type Node = object
#     kids: seq[Node]

#   var bad: string
#   for i in 0 ..< 10_000:
#     bad.add "{\"kids\":["

  # doAssertRaises CatchableError:
  # discard parseJson(bad)

  # doAssertRaises CatchableError:
  # discard fromJson(bad, JsonNode)
  # discard fromJson(bad, RawJson)
  # discard fromJson(bad, Node)

  # discard std.parseJson(bad)
  # discard packedjson.parseJson(bad)

  # discard newStringStream(bad).jsonTo(Node)

  # discard Json.decode(bad, Node)
