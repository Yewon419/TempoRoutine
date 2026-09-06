# [FULL NAME] (한글 이름)

B.S. Data Science · Ewha Womans University, Seoul, Korea
[email] · [github.com/Yewon419](https://github.com/Yewon419) · [LinkedIn / portfolio URL]

**Applying to:** Claude Campus — Builder Club Lead (undergraduate track)

---

## Summary

Undergraduate data science student who ships production software solo and audits her own
work hard enough to throw it away. Across 27 repositories I have released a two-platform
mobile app to TestFlight beta, built an ML temporal-localization pipeline for a university
research project, and deployed a competition entry designed to survive a two-month judging
window unattended. The consistent thread is not the stack — it is that I measure whether
the thing I built actually works, publish the number when it doesn't, and delete the branch
when the answer is no. I do all of it in a paired agentic workflow with Claude Code, on a
Windows machine with no local Apple toolchain, which forced me to write down a verification
methodology. That methodology is what I want to teach.

---

## Education

**Ewha Womans University** — B.S., Data Science
Seoul, Korea · Expected graduation [YYYY.MM]
Relevant coursework: Data Engineering (team project below), [ML / statistics / DB — fill in]
[GPA — include only if strong]

---

## Selected Projects

### Violence Temporal Localization — ML pipeline, university data engineering team project
`Python · PyTorch · ResNet50 · Transformer · OpenCV · Flask · Streamlit`
[github.com/Yewon419/violence-temporal-localization](https://github.com/Yewon419/violence-temporal-localization)

Finds person-to-person physical violence *intervals* in films, as an aid to film ratings
review. Team of 6 split by category; this repository documents my scope. The project is
best described by the two times I deleted work that was already finished.

- **Killed the object-detection track.** I had built a ~20,000-image dataset for
  cigarette/alcohol/weapon detection and hosted it on Hugging Face. Then I concluded it
  could not answer the ratings question: a glass on screen barely affects a rating, and the
  categories that actually matter — violence, horror — **do not fit in a single frame; they
  are only definable on the time axis.** Redefined the problem as temporal localization and
  archived the abandoned track rather than hiding it.
- **Proved auto-labeling unusable with an exhaustive audit.** Grounding DINO bounding boxes
  looked plausible on samples, so I reviewed them 100%: **98.3% false positive on action and
  event labels** (117 of 119 deleted — `car_accident` firing on parked cars, `explosion` on
  neon signs, `blood` on lipstick), while object labels held up (74% clear-keep on a
  stratified sample). Conclusion: violence labels cannot be generated automatically.
- **So I built the annotator.** CVAT's video export doesn't support interval tags, VIA's host
  blocks hotlinking, Label Studio needs six installs. Wrote a single-file Flask + OpenCV
  interval annotator: 2fps extraction at **4,470 frames from a 37-minute film in 17.7s**
  (`grab()` + `retrieve()` to skip full decodes), keyboard interval tagging, automatic
  negative-class backfill, color-block timeline, click-to-delete, undo. Annotated 10 films
  with it.
- **Pipeline:** 2fps frames → ResNet50 2048-d embeddings → sliding clips (len 4 / stride 2) →
  per-video standardization → Transformer encoder (d_model 2048, 8 heads, 2 layers) →
  Gaussian smoothing (σ=1.0) + **hysteresis merge** (enter at 0.45, hold until 0.30 — the
  dual-threshold idea from Canny edge detection) so a brief dip mid-fight doesn't split an
  interval. Benchmarked LSTM / TCN / BiLSTM / Transformer; plain Transformer won at
  **Test Acc 0.72**, violence recall ~0.6. Reported as-is, and diagnosed the ceiling as
  features, not architecture: ResNet frame embeddings carry no motion.
- **Then invalidated my own headline metric.** Predicted violence ratio came out ~35% for
  every film. Easy to read as a model problem; I ran a normalization experiment instead and
  found **two independent causes**: per-video standardization erases cross-film intensity,
  *and* the ground truth itself was balance-sampled to 40.0% violence for every film
  (std 0.0%p) by a `neg_ratio=1.5` in clip generation — meaning the signal was never in the
  data. Documented that **film-level violence ratio is not a valid output of this pipeline**,
  and shipped a cross-video comparison warning into the demo UI rather than quietly leaving
  a number that looks meaningful.
- Streamlit CPU demo with a custom HTML5 player (Streamlit's `st.video` can't style a
  progress bar) that paints detected intervals red and snaps playback to them.
  `mypy --strict` + `ruff`, zero errors.

### TempoRoutine — production iOS + Android app (closed TestFlight beta)
`Swift · SwiftUI · SwiftData · CloudKit · Kotlin · Jetpack Compose`
[github.com/Yewon419/TempoRoutine](https://github.com/Yewon419/TempoRoutine)

An on-device, account-free cycle-aware routine planner. Sole engineer, designer, and release
manager.

- ~29,000 lines of Swift across 114 files; 18 SwiftData models, 9 home/lock-screen widget
  surfaces plus a Live Activity, CloudKit `CKSyncEngine` device sync, StoreKit 2 purchases.
- Prediction engine isolated into **TempoCore**, a dependency-free Swift package with
  **161 unit tests**, specifically so domain logic is verifiable on a Linux CI container
  without a Mac.
- Localized to **4 languages** (ko/en/ja/zh-Hans, 944 keys) behind a single lookup path,
  audited by a Python tool I wrote after finding 341 hard-coded strings silently bypassing
  the catalog.
- Ported the engine to **Kotlin 1:1** (~8,650 lines, 164 mirrored tests) and verified
  cross-platform equivalence with **golden JSON fixtures compared as parse trees, not bytes**
  (Swift emits sorted keys and integer `0`; Kotlin emits declaration order and `0.0`).

### JejuNow — congestion forecasting service, 2026 Korea Tourism Data competition entry
`Next.js 16 · FastAPI · LightGBM · Supabase/Postgres · Capacitor iOS`
[github.com/Yewon419/JejuNow](https://github.com/Yewon419/JejuNow)

Predicts crowding at Jeju tourist spots and redirects demand to quieter same-category
alternatives, to relieve top-spot concentration.

- **Data pipeline:** 8 years / 36,360 rows of Korea Tourism Data Lab popularity share,
  TourAPI 4.0 (801 Jeju spots, operating hours), KMA ASOS weather across 101 months — each
  behind its own scheduled collector with API quota handling.
- **Model:** LightGBM regression on spot×month popularity share. Time-split validation
  (hold-out from 2025-07): **MAE 0.423, MAPE 14.1%, 87.2% top-30% ranking agreement.**
  Hourly values are a documented *composition* — monthly prediction × an explicit heuristic
  intraday profile (per-category Gaussian peak × weekday weights × TourAPI opening hours) —
  not a model output.
- **Honesty is a section of the README, not an afterthought.** The target is a demand proxy,
  not measured congestion; unmapped spots fall back to category means, are flagged
  `is_imputed` in the database, and render as "estimated" in the UI; one planned macro
  feature was dropped and the reason published (the public dataset refreshes annually, so it
  cannot serve as a monthly live feature).
- **Engineered for an unattended two-month judging window:** free-tier Render + a 5-minute
  UptimeRobot ping to a `/keepalive` endpoint that runs a *real DB query* — because Supabase's
  free tier suspends after 7 days and counts only DB activity — plus frontend auto-fallback to
  precomputed rows when the API cold-starts, and weekly GitHub Actions recompute inside the
  750h/month budget. Gates: `mypy`/`ruff` and `tsc --noEmit`/lint all clean.

### chalkak — open-source CI screenshot tool
`Shell · GitHub Actions · xcodebuild · simctl`
*"Screenshot your iOS app on every push, from CI, without a Mac and without UI tests."*

Extracted from my own constraint. Boots a simulator in CI and ad-hoc-signs the build —
unsigned archives have no entitlements section and die on CloudKit init — then publishes
screenshots as a workflow artifact, so layout, color, font, and dark-mode regressions are
caught per push instead of per TestFlight release.

### MCP_supporter · claudebar — Claude-ecosystem developer tools
`Python · Model Context Protocol · Windows system tray`

`MCP_supporter` is an MCP server whose job is installing and configuring *other* MCP servers
from chat — it removes the JSON-config step that stops most beginners from ever getting a
first server running. `claudebar` surfaces live Claude usage in the Windows tray. Both are
small, both are things I use daily, and both are exactly the scale of a good first club
project.

**Also:** AutoStock (AI-driven Korean equities platform — FastAPI + Vue 3 + Celery + KIS Open
API, strategy generation, backtesting, live execution), HangsungDrone (B2B drone-show SaaS
backend), ddackdae, jarimae, rollingpaper, cafe-finder, Mypersona (portable cross-LLM
persona layer).

---

## How I work with Claude — the part I want to teach

I do not treat Claude as autocomplete. I treat it as a colleague working under a written
contract, and I keep the contract in the repository.

- **A failure ledger, not a style guide.** `TempoRoutine/CLAUDE.md` holds **55 rules distilled
  from 24 dated production incidents** — each naming the symptom, the date it cost me, and the
  root cause. Example: *"lock-screen widgets rendering as blank white blocks is privacy
  redaction, not a render failure"* — written after I misdiagnosed it as a `Date.now` bug,
  shipped the wrong fix, and had to reverse myself in public. The ledger exists so the same
  mistake costs one CI cycle instead of three.
- **Closing the verification loop under a hard constraint.** No Mac, no local Swift compiler.
  So correctness had to move somewhere I could afford to check: pure logic into a testable
  package, rendering into CI screenshots, and only genuine runtime behavior deferred to
  real-device TestFlight. "CI is green" is explicitly *not* "done" in my repository's rules.
- **Knowing what the model cannot know.** I keep a standing rule against trusting model recall
  for library APIs — after a `glassEffect(isEnabled:)` parameter that appeared in three
  third-party references but not in the SDK cost me a full CI round trip. New-OS API surface
  gets verified by compilation, never by consensus.
- **The same discipline, applied to my own results.** The violence project's normalization
  audit and JejuNow's limitations section are the same instinct as the ledger: assume the
  number is wrong until you have tried to break it. AI-assisted development makes output
  cheap, which makes this the only scarce skill left.

Most students I know are stuck at *"the AI wrote something and I can't tell if it's right."*
The answer isn't better prompting. It's designing a verification loop you can afford to run,
and writing down what breaks. That is a teachable, one-workshop idea, and I have a year of
scar tissue to teach it from.

---

## What I would do on campus

- **Ship Night (weekly, 2h).** Not a lecture — everyone leaves with a deployed thing. Ladder:
  a claudebar-sized tool → a first MCP server (via MCP_supporter) → an agentic CI loop.
- **"Verify It" workshop.** Building a test/CI harness for AI-generated code you can't read
  line-by-line. Concrete, straight from the TempoRoutine ledger.
- **Research track for non-CS majors.** Ewha's strength is that most students here aren't
  engineers. Claude Projects for thesis literature review, artifacts for data-heavy
  coursework, MCP for wiring research tools together — [name specific departments/clubs].
- **Competition/hackathon team.** JejuNow was a competition entry; I would run a cohort that
  takes one from idea to submitted and deployed. [Existing Ewha club/hackathon to partner
  with — fill in.]

---

## Technical Skills

**Languages** Python · Swift · Kotlin · TypeScript · SQL
**ML / Data** PyTorch, LightGBM, scikit-learn, pandas, OpenCV, Hugging Face Hub;
time-split validation, sampling-bias analysis, annotation tooling
**Mobile** SwiftUI, SwiftData, CloudKit, WidgetKit, Live Activities, App Intents, StoreKit 2;
Jetpack Compose, Room
**Backend / Web** FastAPI, Celery, Next.js, Supabase/PostgreSQL, Prisma, Streamlit, Flask
**AI tooling** Claude Code, Model Context Protocol (server authoring), Claude Skills, Anthropic API
**Infra / Quality** GitHub Actions (multi-job macOS/Linux), App Store Connect API, Vercel, Render,
XcodeGen, Gradle; `mypy --strict` + `ruff` clean as a standing gate

---

## Leadership & Activities

[Fill in — clubs, TA/tutoring, organizing, competitions, presentations. Anthropic's stated
bar is "well-connected on campus," so this section carries real weight; anything where you
convened people belongs here even if it isn't technical. The 6-person data engineering team
counts if you led any part of the coordination.]

---

## Languages

Korean (native) · English ([level — e.g. professional working proficiency, TOEFL/OPIc score])
