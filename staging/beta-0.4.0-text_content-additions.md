# Beta 0.4.0 — text_content rows to import

Ten rows to append to the `text_content` sheet, then re-export. The header line
in the CSV is for reference; only the ten data rows are new.

No leading whitespace anywhere (AN-011). One row contains an em dash, matching
the sheet's existing usage.

| Category | REF_ID | EN | Why |
| --- | --- | --- | --- |
| `BOSS_NAME` | `BOS_02` | RAHNDAHL | §11 |
| `BOSS_NAME` | `BOS_03` | NEHBOCYET | §11 |
| `BOSS_NAME` | `BOS_04` | ECHOFALL | §11 |
| `FUNCTION_NAME` | `FNC_021` | LOGICBOMBEXPLODE | §11 |
| `FUNCTION_NAME` | `FNC_022` | BRAINSCRAMBLE | §11 |
| `UI_BUTTON_TEXT` | `GAME_UI_TITLE_BOSS_ATTACK` | Boss Attack | title entry, §10.1 |
| `UI_SCREEN_PROMPT` | `GAME_UI_BOSS_ATTACK_PROMPT` | No Run and no UPGRADEs — pick a Boss and fight it. | §11 forbids reusing the Run prompt |
| `UI_SCREEN_PROMPT` | `GAME_UI_RESULT_BOSS_WIN` | {opponent} breached. | `GAME_UI_RESULT_QUICK_WIN` says "System ICE breached", which misidentifies a Boss (§10.6) |
| `UI_STATUS_TEXT` | `GAME_UI_CONTEXT_BOSS_ATTACK` | Boss Attack | pause/status line, §10.6 |
| `UI_STATUS_TEXT` | `GAME_UI_CONTEXT_QUICK_MATCH` | Quick Match | migrates the hardcoded literal at `main.gd:812`/`802` into the framework |

## Deliberately reused, not duplicated

- `GAME_UI_BOSS_SELECT_HEADING` — "SELECT BOSS" is genuinely generic (§11).
- `GAME_UI_RESULT_NEW_BATTLE`, `GAME_UI_RESULT_REPLAY_SEED`,
  `GAME_UI_RESULT_BACK_TO_TITLE` — wording is mode-neutral.
- `GAME_UI_RESULT_LOSS` — "Hacker LINK severed" is true in any mode.

## Not needed

CAPACITOR and LOGIC BOMB get no rows. Special types have never carried
player-facing text — OVERRIDE, BOMB, SHIELD and BUFF are all purely visual, and
the only `FUNCTION_NAME,FNC_001,BOMB`-style rows name Functions, not overlays.
