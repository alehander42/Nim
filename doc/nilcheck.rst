Not nil annotation
------------------

All types for which ``nil`` is a valid value can be annotated to
exclude ``nil`` as a valid value with the ``not nil`` annotation:

.. code-block:: nim
  type
    NilableObject = ref object
      a: int
    Object = NilableObject not nil
    Proc = (proc (x, y: int)) not nil

  proc p(x: Object) =
    echo x.a # ensured to dereference without an error

  # compiler catches this:
  p(nil)

  # and also this:
  var x: Object
  p(x)

If they can include ``nil`` as a valid value, dereferencing values of the type
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

Dereferencing operations: look at [Reference and pointer types]

It's enough to ensure that a value is not nil in a certain branch, to dereference it safely there: the language recognizes such checks
in ``if``, ``while``, ``case``, ``and``, ``or``

e.g.

.. code-block:: nim
  not nilable.isNil and nilable.a > 0

is fine.

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

..code-block::nim
  proc p(a: Nilable): Nilable not nil =
    if not a.isNil:
      result = a # OK
    result = a # warning/error

When two branches "join", a location is still safe to dererence, if it was not-nilable in the end of both branches, e.g.

..code-block::nim
  if a.isNil:
    a = Object()
  else:
    echo a.a
  # here a is safe to dereference

The compiler ensures that every code path initializes variables which contain
non nilable pointers. The details of this analysis are still to be specified
here.


Not nil refs in sequences
-------------------------

``seq[T]`` where ``T`` is ``ref`` and ``not nil`` are an interesing edge case: they are supported with some limitations.

They can be created with only some overloads of ``newSeq``:  

``newSeq(length, unsafeDefault(T))``: ``default`` isn't defined for ``ref T not nil``, ``unsafeDefault`` is equivalent to ``nil``.
However this should be used only in edge cases.

.. code-block:: nim
  newSeqWithInit(length):
    Object(a: it)

where we pass a block, which fills each value of the result with a valid not nil value in a loop iterating length times where ``it`` is the index

There is special treatment of ``setLen`` related functions as well: one can use ``shrink`` in all cases.
However one can use ``grow`` similarly to ``newSeq`` :

``grow(length, unsafeDefault(T))``: ensuring that you fill the new elements with non nil values manually

.. code-block:: nim
  growWithInit(length):
    Object(a: it)

similar to ``newSeqWithInit``

Many generic algorithms can be done with the the safe ``shrink``, ``newSeqWithInit`` and ``growWithInit``, but ``unsafeDefault`` can be used as an escape hatch.

