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

## Phase 2 — Content pipeline

### P-006 · `load.ts` split into modules

**Forced by:** nothing — this is a judgement call, recorded because authorization
§16 asks for module-boundary deviations.

The alpha's `load.ts` is 2,441 lines holding diagnostics, vocabularies, the
table reader, per-dataset row models, validation, resolution, and the
fingerprint. Ported as `issues.gd`, `vocab.gd`, `table.gd`, `effects.gd`,
`passives.gd`, `fingerprint.gd`, and `load.gd`.

**Impact:** boundaries only. No logic is reordered or merged, and the module map
in the handoff still resolves — `load.gd` remains the entry point.

### P-007 · CSV parser ported rather than substituted

**Forced by:** `FileAccess.get_csv_line()` handles quoting but not the
behaviours the pipeline depends on — 1-based line tracking that every
validation diagnostic reports, skipping wholly empty rows rather than yielding
`[""]`, BOM stripping, and reporting an unterminated quote as a structural
error.

**Note:** this reverses the handoff's own §12 guidance ("do not hand-roll a
splitter"), which was written before those dependencies were traced. Diverging
on any of them would change validation output or change what gets fingerprinted.

### P-008 · Godot's JSON parser yields every number as a float

**Forced by:** `JSON.parse_string` produces floats for all JSON numbers, and
GDScript array equality is type-strict, so `[0, 0] != [0.0, 0.0]`.

**Resolution:** fixture-side values are coerced to `int` at the comparison,
rather than loosening the comparison itself.

**Impact:** every test that compares JSON fixture data against integer game
data — and, in Phase 4, the differential comparator. Worth remembering there.

### P-009 · djb2 must iterate UTF-16 code units, not codepoints

**Forced by:** JavaScript strings are UTF-16 and `charCodeAt` yields code units,
so a character outside the BMP contributes **two**. GDScript strings are UTF-32.
A codepoint-based loop diverges on any non-BMP character — and reports a
different length, which is itself the base36 suffix of the fingerprint.

**Resolution:** `Fingerprint.utf16_units()` computes surrogate pairs directly
from codepoints. Pinned by a vector for `"🎮"`, whose UTF-16 length is 2.

**Why it matters despite ASCII content:** it would go unnoticed until the day
someone pastes an emoji into a notes column, and would then present as an
unexplained save-invalidating fingerprint change.

### P-010 · Godot's `JSON.stringify` cannot produce the canonical string

**Forced by:** the fingerprint requires byte-equality with JavaScript's
`JSON.stringify` — insertion-ordered keys, integral floats rendered without a
decimal point, raw non-ASCII rather than `\u` escapes, and JS's exact escape
set.

**Resolution:** `Fingerprint.stringify()` is a hand-written serializer. Pinned
against JS output for every value shape the canonical string contains.

**Related, resolved favourably:** A5 asked whether any fingerprinted value is
non-integer. **Zero are**, so JS float formatting never has to be reproduced.
`_float_to_js` raises rather than guessing if that ever stops being true.

### P-011 · GDScript strings cannot contain U+0000

**Forced by:** GDScript strings are NUL-terminated internally, so an embedded
NUL cannot round-trip through a fixture.

**Resolution:** the control-character hash vector uses `U+0001`, `U+001F`, and
`U+007F` instead. Authored content contains no control characters at all, so
this is a test-coverage limitation rather than a behavioural gap — recorded so
the omission is not mistaken for an oversight.

### P-012 · JavaScript omits undefined properties when serializing

**Forced by:** the fingerprint includes the whole axis-target object. In
JavaScript an unset optional property is *absent* from the JSON, not `null`, so
a whole-Packet target serializes as `{"token":"NEU","kind":"NEU"}` — with no
`color` or `shape` keys at all.

**Resolution:** `_axis_target` adds those keys only when they are set. The same
reasoning applies to a PASSIVE's `ALL` scope, which the alpha models as
`true`-or-absent and never as `false`.

**Impact:** either mistake shifts the fingerprint, and the resulting mismatch
gives no clue which of ~11,000 characters is wrong. Both are the kind of detail
that only surfaces because the fingerprint is compared byte-for-byte.

---

## Phase 2 result

The content fingerprint reproduces the alpha's `49c229cd-8ma` exactly.

That one value validates the whole pipeline simultaneously: CSV parsing and
leading-apostrophe normalization, all ten dataset readers, payload grammar and
composite expansion, Effect parameter contracts, typed tuple resolution, the
Transform axis grammar, plan assembly with per-row resolved targeting,
area-pattern cell *order*, the hand-written canonical serializer, and djb2's
UTF-16 semantics. Any one of them being subtly wrong produces a different hash.

**What it does not prove:** the validation guard rails. Those fire only on
invalid content, and the authored content is valid — a rule missing from the
port would look identical to one that passes. They are covered separately by
`test_validation.gd`, which constructs the minimal invalid state for each rule
and asserts it is rejected.

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
