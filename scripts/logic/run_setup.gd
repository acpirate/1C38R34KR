class_name RunSetup
extends RefCounted

## A Run that has been committed but has not finished choosing its identity.
##
## This is deliberately its OWN shape rather than a `Run` with half its fields
## nulled. A Run in setup has no encounter, no inventory, no build, and no
## resolved LINK maximum, and every consumer of a committed Run would otherwise
## have to defend against reading one. The alpha reached the same conclusion for
## the same reason (`RunSetupInfo`).
##
## Committing a Boss is the DESTRUCTIVE New-Run boundary (authorization §4.1):
## it replaces any prior Run save, creates this state, and parks setup on Hacker
## Selection. There is no `SETUP_BOSS` phase, because Boss commitment is what
## brings the Run into existence — before it there is nothing to resume to.

## Fixed from the moment of commitment. Ordinary Back navigation can never
## change it; only deliberately starting a new Run picks a different one.
var boss_id := ""

## Which setup screen this resumes to.
var step: Types.SetupStep = Types.SetupStep.HACKER

## COMMITTED selections only. A highlighted-but-unconfirmed UI row is never Run
## state, so this stays empty until the Hacker screen is confirmed.
var hacker_id := ""

## The settings snapshot, taken at BOSS commitment because that is the New-Run
## boundary, and authoritative for the whole Run. Editing title Settings later
## must never alter a Run already under way.
var settings := {}

## The Run's isolated route stream, seeded at commitment so the initial path
## offers cannot vary with how long identity selection took. Never the battle's
## gameplay stream — see `Run.route_rng`.
var route_rng_state := 0


## §4.1 — commit the Boss and create the Run.
##
## Rejects an unknown ID rather than substituting a default Boss: `Content.boss`
## reports the miss, and a Run committed to a Boss that does not exist is not a
## playable state.
##
## The caller supplies the route seed so the whole Run's route randomness comes
## from one persisted, gameplay-isolated stream.
static func commit_boss(boss_id_in: String, settings_in: Dictionary, route_seed: int) -> RunSetup:
	var boss := Content.boss(boss_id_in)
	if boss.is_empty():
		return null
	var s := RunSetup.new()
	s.boss_id = boss["id"]
	s.step = Types.SetupStep.HACKER
	s.hacker_id = ""
	s.settings = settings_in.duplicate(true)
	s.route_rng_state = Rng.new(route_seed).get_state()
	return s


## Committing the Hacker advances the persisted setup phase. The Boss is
## untouched — it is already fixed for this Run.
func commit_hacker(hacker_id_in: String) -> RunSetup:
	# Reject an unknown ID here rather than at battle time, where the failure
	# would be far less diagnosable.
	if Content.hacker(hacker_id_in).is_empty():
		return null
	var s := RunSetup.new()
	s.boss_id = boss_id
	s.step = Types.SetupStep.DECK
	s.hacker_id = hacker_id_in
	s.settings = settings.duplicate(true)
	s.route_rng_state = route_rng_state
	return s


## The session phase this setup state resumes to.
func phase() -> Types.SessionPhase:
	return (
		Types.SessionPhase.SETUP_HACKER
		if step == Types.SetupStep.HACKER
		else Types.SessionPhase.SETUP_DECK
	)


## The isolated route stream. Committing the Deck consumes this to generate the
## initial path offers (beta 0.2 Phase B).
func route_rng() -> Rng:
	return Rng.new(route_rng_state)
