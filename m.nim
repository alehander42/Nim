import jsffi, jsconsole

type
  B = object

  C = object
    a0: int
    a1: bool


proc e(a: JsObj[tuple[a0: int, a1: bool]]) =
  echo a.a0

e(C())
      
var t = js{a0: 2, a1: false} # JSTuple[tuple[a0: int, a1: false]]

e(t)

proc eJs(a: js) =
  console.log a

console.log t.a0
eJs(t)

