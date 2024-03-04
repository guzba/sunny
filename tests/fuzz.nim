import std/random, sunny, data/twitter, std/strformat

randomize()

const iterations = 10000

for i in 0 ..< iterations:
  var
    json = twitterJson
    pos = rand(json.high)
    value = rand(255).char

  json[pos] = value
  echo &"{i} {pos} {value.uint8}"

  try:
    discard Twitter.fromJson(json)
  except CatchableError:
    discard

  var json2 = json[0 ..< pos]
  try:
    discard Twitter.fromJson(json2)
  except CatchableError:
    discard
