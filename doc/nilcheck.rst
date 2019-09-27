Not nil annotation
------------------

Ref types are ``not nil`` by default.
They can be annotated to include ``nil`` with the ``nil`` annotation or ``?`` : still bikeshedding 

.. code-block:: nim

  type
    Object = ref object
      a: int
    NilableObject = nil Object

    Proc = (proc (x, y: int))


  proc p(x: Object) =
    echo x.a # ensured to dereference without an error

  # compiler catches this:
  p(nil)

  # and also this:
  var x: Object
  p(x)

Syntax:

- ``nil A`` more nim-ish maybe
- ``?A`` popular from c# and typescript, but here its prefix, shorter, maybe more clear
- ``can nil A`` request from the #nim channel: two keywords, but maybe similar to not nil
- ``maybe nil A`` request from the #nim channel: in some ways more obvious than ``nil`` (``nil A`` sounds a bit like ``nil and A``), but maybe it sounds like Option
- ``A or nil`` request from the #nim channel, maybe Araq?: however, clashing with type classes, maybe an exception

 
If a type can include ``nil`` as a valid value, dereferencing values of the type
is checked for by the compiler: if a value which might be nil is derefences, this produces a warning by default, an error if
`--strickNilChecks` is enabled.

You can still turn off nil checking on function level by using the `{.nilCheck: off}.` pragma.

If a type is nilable, you should dereference its values only after a `isNil` check, e.g.:

.. code-block:: nim

  proc p(x: NilableObject) =
    if not x.isNil:
      echo x.a

    # equivalent
    if x != nil:
      echo x.a

  p(x)

Safe dereferencing can be done only on certain locations: 

- ``var`` local variables
- ``let`` variables
- arguments

Dereferencing operations: look at [Reference and pointer types], for procedures: calling

It's enough to ensure that a value is not nil in a certain branch, to dereference it safely there: the language recognizes such checks
in ``if``, ``while``, ``case``, ``and``, ``or``

e.g.

.. code-block:: nim

  not nilable.isNil and nilable.a > 0

is fine.

``case`` can be used as well

.. code-block:: nim

  case a.isNil:
  of true:
    echo a.a # error
  of false:
    echo 0

However, certain constructs invalidate the value ``not-nil``-ness. 

- calls to functions where the location we check is passed by var
- reassignments of the checked location

.. code-block:: nim

  if not nilable.isNil:
    nilable.a = 5 # OK
    var other = 7 # OK
    echo nilable.a # OK
    call() # maybe sets nilable to `nil`?
    echo nilable.a # warning/error: `nilable` might be nil

Additional check is that the return value is also ``not nil``, if that's expected by the return type

.. code-block::nim

  proc p(a: Nilable): Nilable not nil =
    if not a.isNil:
      result = a # OK
    result = a # warning/error


When two branches "join", a location is still safe to dererence, if it was not-nilable in the end of both branches, e.g.

.. code-block::nim

  if a.isNil:
    a = Object()
  else:
    echo a.a
  # here a is safe to dereference

newSeq(length, unsafeDefault(T))
..

Initialization of non nilable pointers
---------------------------------------


The compiler ensures that every code path initializes variables which contain
non nilable pointers. The details of this analysis are still to be specified
here.

TODO

- no implicit initialization for object types depending on such fields
- proving each path in a proc sets result if return type
- forbidding direct construction without initialization of those fields for them
- maybe using unsafeDefault as escape hatch


Not nil refs in sequences
-------------------------

``seq[T]`` where ``T`` is ``ref`` and ``not nil`` are an interesing edge case: they are supported with some limitations.

They can be created with only some overloads of ``newSeq``:  

``newSeq(length)``: ``default`` for ``ref T not nil`` returns ``nil``, so the programmer is responsible to fill correctly the sequence.

However this should be used only in edge cases.

There is special treatment of ``setLen`` related functions as well: one can use ``shrink`` in all cases.
However one can use ``grow`` similarly to ``newSeq`` :

``grow(length)``: calls ``default``: expects that the programmer fills the new elements with non nil values manually.

