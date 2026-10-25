# COPILOT-04 handoff

ID: COPILOT-04-handoff · Updated: 2026-10-23 · Branch: `feat/copilot-04-instant-answers` (from `feat/copilot-03-ai-interviewer` @ `b32fdec`)
Links: [intent.md](intent.md), [spec.md](spec.md)

## Done (2026-10-23)
- R-01 speculative request, R-02 350 ms pause after "?", R-03 gist on the first line, R-04 metrics, R-05 improvisation.
- Audio settings: "Pause after a question ending in "?"" and "Start answering early". Version 0.1.7 (build 8).

## Offline measurement (turn eval, 36 cases, Parakeet final 500 ms after the end of speech)
| Configuration | Turn after the end of speech, mean | The model gets the question | Extra requests |
|---|---:|---:|---:|
| Before (T = 700 ms) | 700 ms | 700 ms (at the turn) | 0 |
| 350 ms pause for "?" | 596 ms | — | 0 |
| + speculative request | 596 ms | **500 ms** in 23 of 26 turns: 12 — directly by the turn ("?"), 11 — by the speculative request | 3 |
| + question words (`questionStarters`) | 596 ms | 500 ms | 3 — no gain, the flag is off |

The model gets the question ~200 ms earlier (no change on cut-off phrases: there we wait for a continuation).
The speculative request did not start at the same moment as the turn (the final arrived after the pause) — fixed from the live log of 2026-10-23.

## Live log 2026-10-23 18:10 (v0.1.8, Microphone source, 1 question)
- The Groq key is saved and checked (`model_ids provider=groq present=true`).
- The owner's recognition is **Whisper medium** (`recognitionBackend = whisper`), the phrase final after 1.8 s (`stt_ms=1334`):
  the turn 2.0 s after the end of speech, Groq's first words 0.74 s after the turn — **2.7 s** from the end of the question.
- Conclusion: the ≤ 1 s goal needs Parakeet (final ~0.5 s); the model is fully installed (23 files).
Further it is bounded by the VAD pause (350 ms) and the Parakeet final (~150 ms) — candidates for the next task.

## Live log 2026-10-23 18:22 (v0.1.10, Parakeet)
- Switched to Parakeet (on the owner's command; only `recognitionBackend` was changed, a copy of the settings — outside Git):
  the phrase final after **507 ms** (`stt_ms=131`) instead of 1.8 s; Whisper turbo refines Ukrainian text (~2.2 s, does not delay the hint).
- The speculative request started 135 ms before the turn but was still being assembled (reading keys from the Keychain) and was cancelled.
  Fixed in 0.1.11: the turn adopts a request that is still being prepared too; if that one decides a bank card is needed — the answer goes the normal way.

## R-06 custom API (2026-10-23)
The `custom` provider, a block in Keys, a model field in Models, the menu line without an unconfigured custom API.
`swift test` 201 tests PASS (two runs in a row; in the first run, before the expectations were fixed, the timing test
`slowButStartedStreamIsNotTimedOut` failed once, PASS on reruns). NOT RUN: a live request through the owner's key.
Version 0.1.10 (build 11).

## Checks
`swift build` PASS; `swift test` 195 tests PASS (+6); turn eval 0% / 0%, mean 596 ms; bank eval 94.9% / 0%;
secret scan 0 findings; `scripts/build-app.sh` + `codesign --verify --strict` — in the session's final message.

## NOT RUN
- AC-01, AC-03 — a live measurement with a Groq key (the executor has no keys).

## H-1 — live measurement (owner, ≈ 15 min)
1. Settings → Keys: a Groq key (console.groq.com, free). Profile → "No profile" (or a profile).
2. Menu → "AI interview…", 10 questions in Russian and 10 in English, answer briefly.
3. In Terminal: `scripts/metrics.py --last 30m` — the lines "C4-AC-01 speech_end → first_token" and "Speculative requests".
4. For comparison — Settings → Audio, turn off "Start answering early", repeat 5 questions.
