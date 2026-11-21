# ParakeetAI vs Interview Copilot — gap analysis

Date: 2026-11-21 · Branch: `feat/copilot-15-accurate-turns` (COPILOT-15 implemented to P-11, H-1 not run) · Status: done (brainstorm 2026-11-21),
owner answers in section 4.

Purpose: understand how ParakeetAI (parakeet-ai.com, ParakeetAI d.o.o., Ljubljana) behaves in real interviews and what
Interview Copilot is missing for a real interview. ParakeetAI parity was already the goal of COPILOT-09; this document
re-checks it against what users and testers report in 2026 and turns the gaps into candidate tasks (COPILOT-16+).

## 1. Method and source quality

- **Official pages.** `parakeet-ai.com/`, `/pricing`, `/faq` were read (served in German). In November 2026 they mainly
  advertise a résumé builder and job finder; the live interview assistant gets one line ("answers in real time during the
  conversation") and a "Screenshot" button. No question-detection, latency, language or model details are on them.
  `/changelog` → 404. `blog.parakeet-ai.com` holds only SEO career articles (12 posts, 10–21 Nov 2026), no product updates.
- **Hands-on tests.** Almost all detailed tests are written by **competitors** (MeetAssist, InterviewFox, LockedIn AI,
  Final Round AI, OphyAI) or by a tool reviewer that sells its own tools (FavTutor). They contradict each other on
  latency, pricing and stealth. Treat every number below as "one tester, one setup".
- **First-hand users.** Trustpilot (359 reviews, 4.6; ~43 read) — mostly short praise; several reviewers note the
  vendor offers credits for reviews (FavTutor, unverified). The vendor's Featurebase board is private (sign-up wall).
- **Not readable.** Reddit (blocked for both the fetcher and the built-in browser — no Reddit thread was read; Reddit
  claims below are second-hand via LockedIn AI and marked so), G2 (HTTP 403), Featurebase posts (private).
  YouTube search was read in the browser: only promo shorts (e.g. "Don't prepare for your interview, just use Parakeet AI",
  "Job interviews with AI is crazy", 2.3 M views) and the vendor's own channel video "ParakeetAI - AI Interview
  Assistant" (604 K views, ~2 years old); no independent walkthrough with measurements was found.

Confidence marks: **[T]** measured by a tester (competitor), **[U]** first-hand user report, **[V]** vendor claim,
**[2]** second-hand (a reviewer quoting users), **[?]** sources conflict or unconfirmed.

## 2. How ParakeetAI behaves in a live interview

| Topic | What is reported | Sources |
|---|---|---|
| Question detection | "Auto Generate (Beta)": the app decides a question was asked and answers without a click; a manual **Answer** button exists. UI states "Checking…" → "Question detected". One how-to says a click is required [?]. Moving the overlay with Ctrl+Shift+Arrow can break detection [2]. Trustpilot's AI summary: "struggles with automatic question detection" [2] | MeetAssist [T], FavTutor, LockedIn, Final Round how-to, InterviewFox |
| Latency to first words | 2.9 s after the interviewer stops (transcript 0.5 s, "Question detected" 2.75 s, full answer 3.3–3.8 s) [T]; ~5.5 s to a readable answer, hand-timed [T]; "2–4 s" [V/2]; users: "slight lag at times" [U], fast "only if u got real fast speed" [U] | MeetAssist, InterviewFox, FavTutor, Trustpilot |
| Transcription | Cloud, **Speechmatics** (error string "Speechmatics connection became unresponsive") [T]. **50+ languages, one per session** [V]. Wrong language set → questions missed/misheard [T]. Keeps user and interviewer voices apart [T]. "Good transcription, even with accents" [2] | InterviewFox, MeetAssist, OphyAI, FavTutor |
| Answer format | One-line **"Question:" restatement**, then bullets [T]. Complaints: answers long and unfocused, sometimes miss the question [2]; "not to the point" even with a reference document [U]; users ask for more human-like answers and scrolling (Featurebase titles) | MeetAssist, InterviewFox, LockedIn, Trustpilot |
| Résumé / JD / documents | CV used in "interview" mode, not in "regular call"; job description in an instructions field; planted résumé detail recalled [T]. **Without matching documents it invented personal stories presented as the user's own in 3/3 cases** [T] | FavTutor, OphyAI, InterviewFox, MeetAssist |
| Follow-ups / context | Follow-ups kept in context 12/12 [T]; but "a quick follow-up question replaces the first answer" [2]; coding follow-up answered the original task again [T]; request for memory across sessions (Featurebase title) | MeetAssist, LockedIn, InterviewFox |
| Coding | "Coding"/"Non-Coding" modes, "Analyze Screen"/Screenshot sends the whole screen to the server; LeetCode Hard solved, code passed tests, one explanation wrong [T]; old answer stuck under "Generating…" ~2 s [T]; looping on an old error [2] | MeetAssist, InterviewFox, FavTutor |
| Models | Chosen per session: GPT-5, GPT-4.1, Claude Sonnet, Gemini added later [V] | FavTutor, OphyAI, Final Round |
| Overlay / stealth | Desktop app (Windows 10+, macOS 12+) or desktop Chrome; overlay transparent, zoomable, movable [T]. Hidden in a Meet share test [T]; **leaked on Zoom entire-screen share** [T]; process shown without name/icon (older builds: "pmodule") [T/?] | MeetAssist, InterviewFox, Final Round |
| Platforms | Zoom, Meet, Teams, Webex, Chime, Lark, HackerRank/CoderPad/LeetCode, phone calls via Google Voice [V] | LockedIn, FavTutor |
| Reliability | Featurebase classification by InterviewFox (689 posts): mid-interview failures 188, answer quality 166, audio/connection 128, detection/privacy 81, slow responses 59 [2]; freezing right before answering [2]; Teams audio stops [2] | InterviewFox, FavTutor |
| Extras | AI mock interviewer (first free, little feedback), call notes/summary, résumé builder, headshots, question bank "coming soon", 10 free 10-minute sessions [V] | FavTutor, OphyAI, LockedIn |
| Pricing | 1 credit = 60 min (0.5 per 30-minute block, auto-extends); $38/credit or ~$150/month unlimited; prices differ by source [?]; refunds only for unused purchases | OphyAI, MeetAssist, InterviewFox |
| Praise | Quick help in "nervous moments", easy setup, clean UI, résumé personalization, transcript for later review [U] | Trustpilot, InterviewFox |

## 3. Gap table

Our status: **have** / **partial** / **missing** / **better** (ours is better). Importance for a real interview:
H (high), M (medium), L (low), — (out of scope).

| # | ParakeetAI capability | Ours | Evidence on our side | Imp. |
|---|---|---|---|---|
| 1 | Automatic question detection + manual Answer button | have | `TurnDetector` (pause 1000/600 ms, owner speech, echo), hotkey `answerNow`; `evals/turn` premature 0 / missed 0 (COPILOT-15 P-08) | H |
| 2 | Visible detection state ("Checking…", "Question detected") | partial | provisional transcript lines (COPILOT-15 R-04); no explicit "question detected / waiting for pause" state in the overlay (not verified in UI) | M |
| 3 | First words ≈ 3 s after the question | better (unverified live) | baseline median ≈ 2.2 s `speech_end → first_token`; COPILOT-15 budget median ≤ 3.0 s / p90 ≤ 5.0 s, not measured live yet (H-1) | H |
| 4 | Accurate transcription of dense speech | better on synthetic, unverified on owner | whole-question re-decode WER 4.5% vs 28.2% chunks (`stt-dense`, synthetic voices); local, no network drop like "Speechmatics unresponsive" | H |
| 5 | 50+ languages | partial | uk / ru / en only (Parakeet v3 + language gate); one-language-per-session is not needed by us (mixed uk/ru/en allowed) | — (owner: Ukrainian only) |
| 6 | Speaker separation (candidate vs interviewer) | have | separate app-audio and mic channels, CAM++ voiceprint, rehearsal `SpeakerRouter` | H |
| 7 | "Question:" restatement before the answer | have | ❓ understood-question line (COPILOT-15 R-10) | M |
| 8 | Résumé, job description, extra documents | better | profiles, materials with bge-m3 retrieval, job import, **question bank with prepared answers** (card in ~0 s) | H |
| 9 | No invented personal stories | better on paper, unverified | `PromptBuilder` forbids inventing projects/employers/numbers; `--smoke-memory` checks; no live measurement like MeetAssist's 3-case test | H |
| 10 | Follow-ups in context; a follow-up must not erase the first answer | better | `InterviewMemory`, answer history with versions ←/→ (COPILOT-09), "you mentioned" rules (COPILOT-07) | H |
| 11 | Coding: screenshot / analyze screen → solution | have | screenshot → strong model, `ScreenshotTask` keeps the task 30 s for follow-ups; no "coding mode" toggle; no measured pass-rate on a LeetCode-style set | H (owner does live-coding) |
| 12 | Model choice (GPT-5 / Claude / Gemini) per session | partial | chain Groq → Cerebras → Gemini → DeepSeek → Claude → custom; model in the wizard; **free Groq tier ≈ 1 hint per minute per key** (ARCHITECTURE §10) — a dense round moves the chain to fallback models | H |
| 13 | Overlay hidden from screen share, no Dock icon | have | `panel.sharingType = .none` (setting), visibility check, `LSUIElement`; behaviour under Zoom/Meet entire-screen share on macOS 15 not re-tested since COPILOT-11 | M |
| 14 | Works in Zoom, Meet, Teams, Webex, etc. | have / partial | preflight knows Zoom, Teams, Telegram, Discord, Slack, Meet in browsers; Webex/Chime/Lark not listed | L |
| 15 | Phone interviews (Google Voice) | missing | no phone-call source (iPhone calls via Continuity / FaceTime app audio not supported) | — (owner: Google Meet only) |
| 16 | Second device (phone/tablet shows hints) | missing | single overlay on the Mac | L |
| 17 | AI mock interview | better | local AI voice interviewer, test call with WER measurement | M |
| 18 | Post-call notes / summary | better | review after End: comments, summary, "Ask AI" (COPILOT-09) | M |
| 19 | Memory across sessions (next round with the same company) | missing | memory is per session; profile/bank carry over, previous rounds' Q&A do not feed the prompt | M |
| 20 | Overlay ergonomics (transparency, zoom, scroll, move) | have | resizable panel, collapse, next screen, font size (COPILOT-09/11) | M |
| 21 | Reliability: no mid-interview freeze | partial | local STT, provider chain with hedge and last resort; but no long-session soak test on M1 8 GB with both transcribers + embeddings + Whisper history pass | H |
| 22 | Résumé builder, headshots, job search | missing | out of scope (not live-interview help) | — |
| 23 | Cloud dependency, per-minute billing | better | local STT, free tiers, `UsageMeter`; no audio leaves the Mac except LLM text | M |

### What ParakeetAI users suffer from that we already avoid
- Freezes and "connection unresponsive" from cloud transcription — our STT is local.
- A follow-up wiping the previous answer — we keep versions.
- Invented personal stories when documents do not match — our prompt forbids it (needs a live measurement, see gap 9).
- Paying per 30-minute block — not applicable.

### Our real gaps (short)
1. **Not proven on the owner's real voice and real calls** (H-1 not run): latency, WER and the ❓ line are synthetic numbers.
2. **LLM throughput on free tiers** in a dense round (gap 12).
3. **Long-session reliability** on an 8 GB M1 (gap 21).
4. Smaller items: detection state in the overlay (2), cross-session memory (19), coding eval (11). Languages, phone and
   second device (5, 15, 16) are not needed for the owner's situation (section 4).

## 4. Brainstorm with the owner (2026-11-21)

### The owner's situation (no personal data)
| Question | Answer |
|---|---|
| Interview language | Ukrainian only |
| Interview types | HR / behavioural, oral technical, live-coding |
| Platform | Google Meet (browser) |
| Live-coding setup | the interviewer shares the screen with the task; wanted help: ready code **and** the approach + what to say aloud |
| Top priority if only one | **understand the question reliably** (1–2 s later is acceptable) |
| Paid LLM key | yes, a few dollars a month is fine |
| Profile in the app | almost empty |

### Failures the owner saw on real calls (all **before** the COPILOT-15 build)
1. Words mashed into "porridge" — consistent with per-chunk Parakeet text (28.2% WER on dense speech) and the per-phrase
   Whisper revision backlog (up to 107 s) that COPILOT-15 removed. Expected to be largely fixed; H-1 must confirm.
2. **The interviewer's speech in Meet shown as a gray "filtered" line, and no hint.** On the call channel the only gray-line
   source is `LanguageGate` (`ListeningController.filterReason`, label "язык …"); the voiceprint gray line ("чужой голос")
   applies to microphone mode. Hypothesis (not confirmed — no metric lines were retained in the system log for the last
   14 days): `LanguageGate.check` drops a phrase on the call channel when its text is Latin-dominant and not English
   (≥ 3 words) — exactly what a garbled Ukrainian phrase transliterated into Polish-like Latin looks like. The check runs on
   the **provisional per-phrase text**, before the COPILOT-15 whole-question re-decode, and filtered phrases are removed
   from the question audio range, so the re-decode cannot rescue them. There is also no way to say "answer this anyway"
   from a gray line.
3. The question was misunderstood → the hint answered a different question.
4. Late hint / no hint.
5. Answers generic, not the owner's experience, sometimes with invented facts — largely explained by the almost empty
   profile: the model has nothing true to say about the owner. ParakeetAI shows the same failure without documents
   (MeetAssist: invented stories 3/3).

### Conclusions
- Languages (50+), phone calls and a second device do not matter for this owner; the ParakeetAI feature surface is not
  the gap. The gap is **reliability of the Ukrainian question on Meet** and **having true content to answer with**.
- Several reported failures predate COPILOT-15; H-1 (live check) must come first, otherwise COPILOT-16 would fix
  problems that may be gone and miss the ones that remain.
- A paid key removes the free-tier throughput limit; with "understand reliably" as the priority, the latency budget can
  spend ~1 s more on accuracy (e.g. fallback B, Whisper turbo on the whole question) if H-1 shows Parakeet drift.

## 5. Candidate tasks (ranked)

Sizes: S ≈ 1 day, M ≈ 2–4 days, L ≈ a week or more (agent time, including evals and handoff).

| Rank | Task | Why (one line) | Size |
|---|---|---|---|
| 0 | **Finish COPILOT-15: H-1 live check, P-12, P-13** (not a new task) | All COPILOT-15 gains are synthetic; the owner's failures predate it; decide fallback B on the real voice | S |
| 1 | **COPILOT-16 Filter after re-decode + "answer anyway"** — on the call channel decide `LanguageGate` on the whole-question re-decoded text (keep filtered phrases' audio in the range until then), never drop Latin non-English phrases when the session language is Ukrainian unless the re-decode confirms it, log the label of every drop, and add a click / hotkey on a gray line that forces a turn from it | Directly targets the owner's "gray filtered line, no hint" failure and the top priority "understand reliably" | M |
| 2 | **COPILOT-17 Profile builder + no-facts mode** — guided filling from the résumé PDF and the job posting (the app asks the owner short questions for facts, numbers and 5–7 STAR stories; drafts bank answers with the existing `QuestionPreparation`), and a prompt rule: when the profile has no fact for the question, answer with a structure and `[your example]` placeholders instead of a story | "Generic / invented" answers come from an almost empty profile; better retrieval cannot fix missing content | M |
| 3 | **COPILOT-18 Ukrainian question accuracy on the owner's voice** — use H-1 numbers: term dictionary seeded from the profile and job posting, a uk→ru / uk→pl drift metric per turn, switch on fallback B (Whisper turbo on the whole question, +~2 s) if drift is real, and a test-call script with the owner's typical technical questions | Second half of "understand reliably"; scope depends on H-1, so it follows it | M |
| 4 | **COPILOT-19 Live-coding mode** — one hotkey: screenshot of the shared Meet screen → strong model returns ready code **plus** approach, complexity and 3–4 sentences to say aloud; follow-ups stay bound to the task (existing `ScreenshotTask`); a small synthetic eval of coding screenshots with pass/fail | The owner does live-coding and wants both code and talk track; ParakeetAI's coding path is its strongest tested feature | M |
| 5 | **COPILOT-20 Paid primary provider + prompt diet** — a paid fast key as the first link of the chain, shorter hint prompt (~6 000 tokens today), measured `first_token` and tokens per hint | Removes the free-tier throttle in a dense round; owner agreed to a small cost | S |
| 6 | **COPILOT-21 Overlay status line** — "listening / waiting for pause / question caught / generating / filtered (why)" | ParakeetAI's "Checking… → Question detected" builds trust; a visible state also exposes silent drops like failure 2 | S |
| 7 | **COPILOT-22 One-hour soak run** — replay a synthetic 60-minute Ukrainian call on the M1 8 GB: CPU, memory, latency drift, no freezes | ParakeetAI's top complaint is mid-interview failure; we never ran a long session | S–M |
| 8 | Cross-round memory (next round with the same company sees the previous rounds' questions and answers) | Useful for multi-round processes; lower value than the items above | M |

Not recommended now: more languages, phone calls, second device, résumé builder / headshots / job search (outside the
owner's situation or outside live help). Stealth work beyond the existing capture exclusion is out of scope.

Suggested order: 0 → 1 → 2 (2 can run in parallel with 1: different files) → 3 (after H-1 data) → 4 → 5 → 6 → 7.
## Sources

- ParakeetAI official: https://www.parakeet-ai.com/ , https://www.parakeet-ai.com/pricing , https://www.parakeet-ai.com/faq ,
  https://blog.parakeet-ai.com/ (read 2026-11-21); https://www.parakeet-ai.com/changelog (404)
- MeetAssist (competitor), hands-on test 15–16 Oct 2026, app 3.9.116: https://meetassist.io/reviews/parakeet-ai
- InterviewFox (competitor), 5 Nov 2026: https://interviewfox.ai/reviews/parakeet-ai-review/
- LockedIn AI (competitor), checked 27 Oct 2026: https://www.lockedinai.com/blog/what-is-parakeet-ai
- Final Round AI (competitor): https://www.finalroundai.com/blog/can-parakeet-ai-be-detected ,
  https://www.finalroundai.com/blog/how-to-use-parakeet-ai
- OphyAI (competitor), 29 Sep / 19 Oct 2026: https://ophyai.com/blog/career-advice/parakeet-ai-review ,
  https://ophyai.com/blog/career-advice/parakeet-ai-pricing
- FavTutor, updated 18 Sep 2026: https://favtutor.com/parakeet-ai-review/
- Trustpilot (users), read 2026-11-21: https://www.trustpilot.com/review/parakeet-ai.com
- Product Hunt (ParakeetAI 2.0 launch 7 Oct 2026): https://www.producthunt.com/products/parakeetai
- YouTube search (read in a browser 2026-11-21): https://www.youtube.com/results?search_query=parakeet+ai+interview
- Not readable: Reddit (blocked), G2 https://www.g2.com/products/parakeet-ai/reviews (403), Featurebase
  https://parakeetai.featurebase.app/ (private)
