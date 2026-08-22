# Port Notes

Running record of places where the GDScript could **not** be a literal
translation of the alpha, and why. Authorization §16 requires these in the
final report; recording them as they happen beats reconstructing them later.

Anything here is a deviation forced by the language or engine. Deliberate design
decisions live in `decisions.md` instead.

---

## Phase 1 — Foundation

### P-001 · `Color` and `Shape` enums renamed

**Forced by:** Godot has a builtin `Color` type, and GDScript rejects an enum
that shadows a builtin name — *"The member "Color" cannot have the same name as
a builtin type."*

**Resolution:** renamed to `PacketColor` and `PacketShape`. Renamed as a pair so
the two stay symmetric; `Shape` alone would not have collided.

**Impact:** naming only. The enum **values** are unchanged and remain frozen at
`0..5` per D-014, which is what weak-set derivation actually depends on.

### P-002 · Enum type annotations must be fully qualified

**Forced by:** GDScript treats the bare `Side` written inside `types.gd` and the
`Types.Side` seen by an external caller as *different named types*:

```
Parse Error: Invalid argument for "opponent_of()" function:
argument 1 should be "Side" but is "Types.Side".
```

**Resolution:** house convention — enum annotations always use the qualified
form (`Types.Side`), **including inside the file that declares them**.

**Impact:** affects every logic module that passes an enum across a boundary,
which is most of them. Established in Phase 1 deliberately, because discovering
it in Phase 3 would mean editing every signature already written.

### P-003 · Constants are not readable by name from a `class_name`

**Forced by:** a `class_name` identifier is a *type*, not an object, so both
`Constants.get(name)` and `Constants.get_script_constant_map()` are parse
errors. `preload` does not help — the parser resolves it back to the same named
type.

**Resolution:** a runtime `load(path)` into a `Script`-typed variable yields an
object whose instance methods are callable.

**Impact:** test tooling only. No gameplay code reads constants reflectively.

### P-004 · `Math.imul` has no direct GDScript equivalent

**Forced by:** two masked uint32 operands can produce a product up to ~1.8e19,
which exceeds int64's ~9.2e18 maximum.

**Resolution:** `Rng._imul` splits operands into 16-bit halves so no
intermediate can overflow.

**Measured:** GDScript's integer multiply *does* wrap cleanly mod 2^64, so the
naive `(a * b) & 0xFFFFFFFF` produces identical results — asserted by
`test_rng.gd` across ten cases including `0xFFFFFFFF * 0xFFFFFFFF`. The
defensive form is kept anyway: correctness here should not rest on overflow
semantics. Revisit only if Phase 4 profiling shows the harness is RNG-bound.

---

## Tooling defects found and fixed

### P-005 · A parse error in a test suite hung the runner

**Symptom:** `godot --headless -s res://tools/run_tests.gd` spun forever at 100%
CPU instead of failing.

**Cause:** a script with a parse error still `load()`s as an object but cannot
be instantiated. Calling `new()` on it raises a runtime error that aborts
`_initialize()`, so `quit()` was never reached and the SceneTree main loop ran
indefinitely.

**Fix:** guard with `script.can_instantiate()` before `new()`, plus a `_process`
fallback that aborts if the main loop is ever reached.

**Why it is recorded:** a test runner that hangs instead of failing is worse
than the bug it was reporting — it converts a clear failure into a stalled
build. Both exit paths are now verified: 0 on pass, 1 on failure.
