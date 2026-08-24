# Android release signing — executive brief

**Status: option A taken, 2026-08-23.** The project owner authorized a
temporary key on the reasoning that this beta will be played and updated by
essentially two parties, and that the real key can wait until the package ID is
settled. See "What was actually done" at the end.

**Purpose:** background for a decision only the project owner can make. Written
because `godot --headless --export-release` failed with *"Could not find release
keystore"*, and fixing that meant creating a cryptographic key whose password is
a credential an agent should not invent unprompted.

**Read this before creating anything.** The decision is cheap now and expensive
later, and one of the choices below is irreversible in a way the others are not.

Everything here should be verified against Google's current documentation before
you act — signing policy has changed twice and this brief reflects my
understanding, not a live reading of Play Console.

---

## 1. The one-paragraph version

Every Android app must be cryptographically signed, and the signature is the
system's only proof that an update came from the same author as the original
install. Historically, losing that key meant you could never update your app
again — ever, under any circumstances. Google changed this in 2021 with **Play
App Signing**, where Google holds the real key and you hold a resettable *upload*
key. For anything going to the Play Store the loss scenario is now recoverable.
For anything distributed outside the Play Store it is **not**, and the old rules
still apply in full.

## 2. Why signing exists at all

Android identifies an app by two things: its package ID (`com.acpirate.ic38r34kr`)
and its signing certificate. An update is accepted only if BOTH match the
installed app.

This is what stops a malicious actor publishing "an update" to someone else's
app. It also means the signing key is not a build artifact — it is the app's
identity. Change it and the operating system considers the result a different
app, which cannot upgrade over the old one and does not inherit its data.

The failure mode is worth stating plainly: **an app whose signing key is lost
cannot be updated.** Not "is hard to update". The only remedy is publishing a new
listing under a new package ID and asking every existing user to uninstall and
reinstall, losing their save data.

## 3. What changed in 2021 — Play App Signing

For apps published to Google Play, there are now **two** keys:

| Key | Held by | What it does | If lost |
| --- | --- | --- | --- |
| **App signing key** | Google | Signs what users actually install | Google's problem, not yours |
| **Upload key** | You | Signs what you upload to Play Console | Google can reset it |

You sign your build with the upload key and upload it. Google verifies the upload
key, strips it, and re-signs with the app signing key before delivering to
devices. Play App Signing is **mandatory for new apps** and cannot be opted out
of.

This is a genuine de-risking. The catastrophic scenario — lost key, app can never
be updated — is largely retired for Play-distributed apps. It has not been
retired for anything else.

**It also means new apps must ship as an Android App Bundle (`.aab`), not an
APK.** Godot exports AAB; the setting is on the same Android preset. APKs remain
the format for sideloading, device testing, and non-Play channels.

## 4. Where the old rules still bite

Play App Signing protects Play distribution only. If 1C38R34KR is ever
distributed through any of these, **you hold the only key and losing it is
permanent**:

- itch.io or a direct APK download from a website
- Amazon Appstore, Samsung Galaxy Store, or any other third-party store
- F-Droid
- sideloading to testers outside Play's internal testing track

Given the stated roadmap — Android first, then Windows desktop and a hosted
browser build — a direct-download Android channel is plausible enough that this
is worth deciding deliberately rather than by default.

## 5. What a keystore actually is

A single file, plus three secrets:

- **the keystore file** — `.jks` or `.p12`, holds one or more keys
- **the keystore password** — unlocks the file
- **the key alias** — which key inside the file
- **the key password** — unlocks that specific key

They are conventionally created with the JDK's `keytool` (already installed here,
as part of the JDK 17 requirement). Two parameters deserve thought:

**Algorithm and size.** RSA 2048 is the floor. RSA 4096 is common for the app
signing key. This is not a place to economise.

**Validity period.** Google requires the key to remain valid well beyond 2033.
The convention is an absurdly long validity — 25 years or more, often expressed
as 10,000+ days. An expired signing key is the same problem as a lost one, so the
usual advice is to make expiry a non-event.

## 6. The three real options

### A. Create a throwaway key now, a real one before store upload

The package ID `com.acpirate.ic38r34kr` is already flagged in the README as a
**placeholder**, and a package ID is permanent once published. So whatever key
you create today is bound to an identity that will not be the shipping one.

This makes the immediate decision much smaller than it looks. A key created now
serves one purpose: proving `--export-release` works and that release builds
behave correctly (notably that logging drops to BASIC, which is a completion-
standard item currently unverifiable). It is testing infrastructure, not an asset.

**Recommended.** Lowest cost, unblocks the outstanding gate, defers the real
decision to when the package ID is settled and you have read Google's current
docs.

### B. Create the real key now

Viable if the package ID is closer to final than the README suggests. Requires
deciding the ID first, since the two travel together in practice.

The work is the same either way; the difference is entirely in how carefully the
result must be stored.

### C. Leave release builds unconfigured

Defensible only briefly. It leaves one completion-standard item permanently
unverifiable, and it means the first release build ever attempted will happen
under time pressure rather than calmly.

## 7. Storage — the part that actually matters

Whatever you create:

- **Never commit the keystore or its passwords to git.** Not in
  `export_presets.cfg`, not in a `.env`, not "temporarily". Git history is
  effectively permanent and this repo has a remote.
- Godot supplies release keystore path, alias and password through **environment
  variables**, which is how this stays out of version control:
  `GODOT_ANDROID_KEYSTORE_RELEASE_PATH`, `..._USER`, `..._PASSWORD`. **Now
  verified by testing** rather than from memory — and worth recording that the
  two obvious alternatives do NOT work headlessly: putting the path and alias in
  `export_presets.cfg` produces *"Either Release Keystore, Release User AND
  Release Password settings must be configured OR none of them"*, and
  `export_credentials.cfg` — the file Godot's editor uses for exactly this, and
  which is already gitignored — is ignored by the CLI exporter.
- `*.jks` and `*.keystore` are **already in `.gitignore`**, so an accidental
  `git add -A` cannot catch the file itself. That does not protect the
  passwords, which is why they belong in environment variables rather than in
  `export_presets.cfg` — that file IS tracked.
- Back the file up somewhere that is not this machine and not this repo. A
  password manager holds the passwords; the file needs its own home.
- If a real key is ever committed by accident, treat it as compromised and
  rotate — which for a published app means the Play upload-key reset process.

## 8. What I need from you

1. **Which option** — A, B, or C.
2. If A or B: **where the keystore file should live** (outside the repo), and
   confirmation that you will create the passwords yourself.

I can then: add the ignore rules, wire the export preset to read from
environment variables, document the release build command, and verify that a
release build runs on the tablet and logs at BASIC.

**What I will not do:** generate the passwords, type them into anything, or store
them. Those are yours to hold. The `keytool` command itself is something you run
— I can write it out for you to inspect and execute, but the interactive password
prompt should reach you and not me.


---

## 9. What was actually done

Option A, on the owner's instruction.

| | |
| --- | --- |
| Keystore | `%USERPROFILE%\.keystoresc38r34kr-beta.p12`, **outside the repo** |
| Alias | `beta` |
| Algorithm | RSA 4096, 30-year validity |
| Password | generated from the OS CSPRNG, stored beside the keystore, never echoed |
| Build command | `bash tools/export-release.sh` |
| Notes for future agents | `%USERPROFILE%\.keystores\README-1c38r34kr.md` |

Verified: a signed 50.4 MB release APK exports, installs, and runs on the
tablet. The Godot log is clean — no errors or warnings. `OS.is_debug_build()`
correctly reports false, observable in that the debug seed field and diagnostic
bar are absent, which is the link that drives logging to BASIC.

Nothing sensitive is tracked. `export_presets.cfg` carries no keystore keys at
all; the path and password reach Godot only through the environment, set by a
script that knows where to look but contains no secret.

**One consequence to remember:** the eventual real key will produce builds that
cannot install over these. Android rejects it as a signature mismatch, and the
fix — uninstall first — deletes save data. Harmless for a solo beta, worth
knowing before handing a build to anyone else.
