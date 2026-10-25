# Live test-call script (H-4)

For AC-01…AC-03, AC-05, AC-09, AC-10. The data is synthetic: questions to the fictional candidate from `profile.example/`.
Metrics are computed by `scripts/metrics.py` from the app logs (numbers only, no utterance text).
The questions are deliberately in Russian, Ukrainian and English — the languages under test.

## Preparation (≈ 3 min)
1. On the Mac: Google Chrome → meet.google.com → "New meeting" → "Start an instant meeting". Copy the link.
2. On a phone: open the link (Meet app or browser) and join. **Mute your own microphone in Meet on the Mac** so the phone
   does not hear echo, and wear headphones if you have them (it works without them too).
3. In the app: a session with the source "Chrome" (or Auto), mode "Bank + hint", language "Auto (UK/RU/EN)".
4. The executor starts the memory measurement in Terminal: `scripts/footprint-monitor.sh 10` (AC-05).

## Questions (read from the phone; after each one pause 5–10 s until the answer appears)
| # | Language | Question | Expected |
|---|---|---|---|
| 1 | ru | Пару слов о вашем опыте? | Card `about-me` |
| 2 | ru | Почему решили сменить работу? | Card `why-leaving` |
| 3 | ru | Как вы справляетесь, когда сроки горят? | Card `deadline` |
| 4 | ru | Как вы относитесь к работе по выходным? | Not in the bank → generated hint |
| 5 | ru | Расскажите о проекте, который… *(2 s pause)* …вы считаете своим лучшим. | One question, not cut; `hardest-project` or a hint |
| 6 | uk | Розкажіть коротко про себе. | Card `about-me` |
| 7 | uk | Яка ваша найбільша слабкість? | Card `weaknesses` |
| 8 | uk | Чи доводилося вам навчати молодших розробників? | Card `mentoring` |
| 9 | uk | Що ви знаєте про SwiftData? | Not in the bank → hint in Ukrainian |
| 10 | uk | Як ви ставитеся до віддаленої роботи? | Card `remote-relocation` |
| 11 | en | Could you introduce yourself briefly? | Card `about-me` |
| 12 | en | Tell me about a conflict with a teammate. | Card `conflict` (S/T/A/R chips) |
| 13 | en | What are your salary expectations? | Card `salary` |
| 14 | en | How would you speed up a slow table view? | Not in the bank → hint in English |
| 15 | en | Do you have any questions for us? | Card `questions-for-us` |

## Checks during the call (AC-09)
- After question 3: click into the Chrome window (focus on Chrome) and press **⌃⌥H** twice — the overlay hides and
  reappears, focus stays in Chrome (the cursor in the address bar does not disappear).
- After question 9: without waiting for the answer, press **⌃⌥↩** — the answer comes immediately for the last line.
- After question 14: open any page with a coding task in Chrome and press **⌃⌥S** — the solution appears in the overlay.
- While question 12 is being asked, start speaking into the Mac microphone yourself — auto-answer must not interrupt (S-07); then ⌃⌥↩.

## Owner assessment (AC-10, AC-11)
- For each language: how many of 5 phrases were transcribed understandably (visible in the overlay transcript) and whether
  the language was detected correctly.
- Menu: does it resemble `docs/design/menu-v2.webp` with the deviations from spec R-15.
