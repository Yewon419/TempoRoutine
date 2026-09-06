# [FULL NAME] (한글 이름)

B.S. Data Science · Ewha Womans University, Seoul, Korea
[email] · [phone] · [github.com/Yewon419](https://github.com/Yewon419) · [LinkedIn / portfolio URL]

<!-- 연락처는 이 저장소가 public이라 플레이스홀더로 둡니다. 제출본은 로컬 사본에 채워 씁니다. -->

**Applying to:** Claude Campus — Builder Club Lead (undergraduate track)

---

## Summary

Undergraduate data science student. I led a six-person university ML project through two
direction changes that each meant deleting finished work, and I write the standards and
tooling that let a team move together. Separately, across 27 repositories, I build in a
paired agentic workflow with Claude Code — not just *using* Claude, but building the
verification loop around it, open-sourcing the tooling that loop needed, and writing MCP
servers that extend it. I completed Cohort 6 of Prometheus, an inter-university AI and data
engineering society, and stay connected to its alumni across several Seoul campuses — so a
Builder Club at Ewha would open with a cohort, not a signup sheet. What I want to teach
there is the second thing above: not prompting, but how to know whether what the model gave
you is actually correct.

---

## Education

**Ewha Womans University** — B.S., Department of Data Science
Seoul, Korea · Third year · Expected graduation Spring 2028
Relevant coursework: Data Engineering (the team project below), [ML / statistics / DB — add 2–3]
[GPA — include only if strong]

---

## Leadership

### Violence Temporal Localization — led a 6-person university data engineering project
`Python · PyTorch · ResNet50 · Transformer · OpenCV · Flask · Streamlit`
[github.com/Yewon419/violence-temporal-localization](https://github.com/Yewon419/violence-temporal-localization)

Finding person-to-person physical violence *intervals* in films, as an aid to film ratings
review. I drove the project's technical direction, wrote the standards the team labeled
against, and built the tooling they worked in.

**I redefined the problem, which meant throwing away finished work — twice.**

- The team started on per-frame **object detection** (cigarettes, alcohol, weapons). We had a
  ~20,000-image dataset built and hosted on Hugging Face. I argued it could not answer the
  ratings question: a glass on screen barely affects a rating, and the categories that
  actually matter — violence, horror — **do not fit in a single frame; they exist only on the
  time axis.** I moved the project to temporal localization and archived the abandoned track
  in full rather than hiding it.
- We were auto-labeling with Grounding DINO to cut annotation cost. Samples looked fine, so I
  ran an **exhaustive review instead of a spot check: 98.3% false positive on action and
  event labels** (117 of 119 deleted — `car_accident` firing on parked cars, `explosion` on
  neon signs, `blood` on lipstick), while object labels held up (74% clear-keep, stratified).
  I published the four audit reports as the evidence base, and killed automatic labeling for
  the violence classes on that basis. **The decision was made by measurement, not by
  seniority** — which is why the team accepted it.

**Then I built what the team needed to execute the new direction.**

- **The labeling standard.** `docs/annotation_guide.md` — I wrote it because label quality is
  the hard ceiling on model performance, so the disagreements have to be settled *before*
  anyone starts: which acts count, where an interval starts (at the wind-up, not the impact —
  otherwise the model loses the signal's onset), and when two bursts merge (gaps ≤5s / 10
  frames). Consistency across annotators mattered more than tight boundaries, and saying so
  explicitly is what made six people's labels comparable.
- **The annotation tool.** Existing options were all blocked — CVAT's video export has no
  interval tags, VIA's host blocks hotlinking, Label Studio needs six installs. I built a
  single-file Flask + OpenCV interval annotator: **4,470 frames from a 37-minute film in
  17.7s** (`grab()` + `retrieve()` to skip full decodes), keyboard tagging, **automatic
  negative-class backfill** so annotators only mark two of three classes, color-block
  timeline, click-to-delete, undo. The backfill design is what actually moved team
  throughput. I annotated 10 films with it myself.
- **The team review workflow.** CVAT setup and the shared inspection process, documented so
  review was a repeatable procedure rather than six private judgment calls.
- **A running decision log** (`decisions.md`) recording why each choice was made, in order —
  so the team never re-litigated a settled question.

**The technical result, reported honestly.**

- Pipeline: 2fps frames → ResNet50 2048-d embeddings → sliding clips (len 4 / stride 2) →
  per-video standardization → Transformer encoder (d_model 2048, 8 heads, 2 layers) →
  Gaussian smoothing (σ=1.0) + **hysteresis merge** (enter at 0.45, hold until 0.30 — the
  dual-threshold idea from Canny edge detection) so a brief lull mid-fight doesn't split an
  interval. Benchmarked LSTM / TCN / BiLSTM / Transformer; plain Transformer won at
  **Test Acc 0.72**, violence recall ~0.6. I reported the ceiling as-is and diagnosed it as
  features, not architecture: ResNet frame embeddings carry no motion.
- **I then invalidated our own headline metric.** Predicted violence ratio came out ~35% for
  every film — easy to read as a model problem. I ran a normalization experiment instead and
  isolated **two independent causes**: per-video standardization erases cross-film intensity,
  *and* the ground truth was itself balance-sampled to 40.0% violence for every film
  (std 0.0%p) by a `neg_ratio=1.5` in clip generation — the signal was never in the data.
  I documented that **film-level violence ratio is not a valid output of this pipeline** and
  shipped a cross-video comparison warning into the demo UI, rather than leaving a number
  that looks meaningful and isn't.
- Streamlit CPU demo with a custom HTML5 player (Streamlit's `st.video` can't style a
  progress bar) painting detected intervals red and snapping playback to them.
  `mypy --strict` + `ruff`, zero errors.

### Prometheus — inter-university AI & data engineering society · Cohort 6 (completed), alumni

An inter-university (not single-campus) society for AI and data engineering. I completed
Cohort 6 and remain in its alumni network, which spans several Seoul universities. This is
why a Claude Builder Club at Ewha wouldn't start from zero: it gives me both a recruiting
channel into Ewha and co-hosts for events a single-campus club can't run alone.

**GYM-ZALABIM** — real-time home-training posture correction, 4-person team
`MediaPipe · OpenCV · FastAPI · React` · [repo/demo link — fill in]

Scores a user's form against reference data from their webcam in real time. Webcam →
FastAPI backend (session state, per-mode flow control, scoring) → MediaPipe engine
(33 pose landmarks → joint metrics → comparison against reference → score) → React frontend.

- **Easy mode (squat)** runs a 5-state machine — Stand → Descend → Hold → Ascend → Rest —
  and scores four checkpoints: trunk, hip, and knee angles plus knee-valgus distance.
  The reference wasn't guessed: we derived it from AI Hub fitness posture imagery by
  filtering to frames where all four conditions hold, selecting a representative peak frame,
  and min-max normalizing — yielding reference means of trunk 32.59°, hip 110.11°,
  knee 108.35°, knee-valgus 49.13px.
- **Hard mode (choreography)** can't use a static reference, because the same move performed
  slower is still correct. So scoring runs **DTW frame matching** against a preprocessed
  reference sequence before comparing left/right elbow and knee angles — aligning on time
  first, then measuring form.
- [Your specific role — which of these you owned. The reference-derivation pipeline and the
  DTW scoring are the two parts worth claiming if they were yours.]

[Additional leadership — TA/tutoring, organizing, presentations, other competitions.]

---

## Building with Claude

Four escalating levels of using Claude — I use it, I build a verification loop around it,
I open-source the tooling that loop needed, and I extend Claude itself.

### Sustained production work — TempoRoutine (iOS + Android, closed TestFlight beta)
`Swift · SwiftUI · SwiftData · CloudKit · Kotlin · Jetpack Compose`
[github.com/Yewon419/TempoRoutine](https://github.com/Yewon419/TempoRoutine)

An on-device, account-free routine planner. Sole engineer, designer, and release manager —
built entirely in a paired agentic workflow, on Windows, with **no local Apple toolchain at
all.** That constraint is the point: I could not compile Swift locally, so correctness had to
move somewhere I could actually check it.

- ~29,000 lines of Swift across 114 files; 18 SwiftData models, 9 home/lock-screen widget
  surfaces plus a Live Activity, CloudKit `CKSyncEngine` sync, StoreKit 2 purchases.
- Prediction logic isolated into **TempoCore**, a dependency-free Swift package with
  **161 unit tests**, specifically so domain logic is verifiable on a Linux CI container.
- Ported the engine to **Kotlin 1:1** (~8,650 lines, 164 mirrored tests), verifying
  equivalence with **golden JSON fixtures compared as parse trees, not bytes** (Swift emits
  sorted keys and integer `0`; Kotlin emits declaration order and `0.0`).
- 4 languages (ko/en/ja/zh-Hans, 944 keys) behind one lookup path, audited by a Python tool
  I wrote after finding 341 hard-coded strings silently bypassing the catalog.

### End-to-end data product — JejuNow (2026 Korea Tourism Data competition entry)
`Next.js 16 · FastAPI · LightGBM · Supabase/Postgres · Capacitor iOS`
[github.com/Yewon419/JejuNow](https://github.com/Yewon419/JejuNow)

Predicts crowding at Jeju tourist spots and redirects demand to quieter same-category
alternatives.

- **Pipeline:** 8 years / 36,360 rows of Korea Tourism Data Lab popularity share, TourAPI 4.0
  (801 spots, operating hours), KMA ASOS weather over 101 months — each behind its own
  scheduled collector with quota handling.
- **Model:** LightGBM on spot×month popularity share. Time-split validation (hold-out from
  2025-07): **MAE 0.423, MAPE 14.1%, 87.2% top-30% ranking agreement.** Hourly values are a
  documented *composition* — monthly prediction × an explicit heuristic intraday profile —
  not a model output, and the README says so.
- **Built to run unattended through a two-month judging window:** free-tier Render + a
  5-minute ping to a `/keepalive` endpoint that runs a *real DB query*, because Supabase's
  free tier suspends after 7 days and counts only DB activity; frontend auto-fallback to
  precomputed rows on cold start; weekly GitHub Actions recompute inside the 750h/mo budget.
- Unmapped spots fall back to category means, are flagged `is_imputed` in the database, and
  render as "estimated" in the UI. `mypy`/`ruff` and `tsc --noEmit`/lint all clean.

### Tooling the loop needed — chalkak (open source)
`Shell · GitHub Actions · xcodebuild · simctl`
*"Screenshot your iOS app on every push, from CI, without a Mac and without UI tests."*

The missing half of the no-Mac workflow: logic was testable, but nothing verified *rendering*.
Boots a simulator in CI and ad-hoc-signs the build — unsigned archives have no entitlements
section and die on CloudKit init — then publishes screenshots as an artifact, so layout,
color, font, and dark-mode regressions surface per push instead of per release. Extracted
from my own repo and released standalone because the constraint isn't unique to me.

### Extending Claude itself — MCP_supporter · claudebar · custom skills
`Python · Model Context Protocol · Windows system tray`

**MCP_supporter** is an MCP server whose job is installing and configuring *other* MCP servers
from chat — it removes the hand-edited JSON config that stops most beginners from ever getting
a first server running. **claudebar** puts live Claude usage in the Windows tray. I also
maintain a private Claude Skills repository and **Mypersona**, a portable context layer that
survives moving between models. These are small, I use them daily, and they are exactly the
scale of a good first Builder Club project.

**Also:** AutoStock (AI-driven Korean equities platform — FastAPI + Vue 3 + Celery + KIS Open
API, strategy generation, backtesting, live execution), HangsungDrone (B2B SaaS backend),
ddackdae, jarimae, rollingpaper, cafe-finder.

---

## The methodology I want to teach

I don't treat Claude as autocomplete. I treat it as a colleague working under a written
contract, and I keep the contract in the repository.

- **A failure ledger, not a style guide.** `TempoRoutine/CLAUDE.md` holds **55 rules distilled
  from 24 dated production incidents** — each naming the symptom, the date it cost me, and the
  root cause. Example: *"lock-screen widgets rendering as blank white blocks is privacy
  redaction, not a render failure"* — written after I misdiagnosed it as a `Date.now` bug,
  shipped the wrong fix, and had to reverse myself. The ledger exists so the same mistake
  costs one CI cycle instead of three.
- **Design the verification loop around your actual constraint.** No Mac meant pure logic went
  into a testable package, rendering went into CI screenshots, and only genuine runtime
  behavior was deferred to real-device TestFlight. "CI is green" is explicitly *not* "done"
  in my repository's rules.
- **Know what the model cannot know.** Standing rule against trusting model recall for library
  APIs — after a `glassEffect(isEnabled:)` parameter that appeared in three third-party
  references but not in the SDK cost me a full CI round trip. New-OS API surface is verified
  by compilation, never by consensus.
- **The same discipline applied to my own results.** The normalization audit that invalidated
  our violence-ratio metric and JejuNow's published limitations are the same instinct as the
  ledger: assume the number is wrong until you've tried to break it. Agentic tools make
  output cheap, which makes this the only scarce skill left.

Most students I know are stuck at *"the AI wrote something and I can't tell if it's right."*
The answer isn't better prompting. It's designing a verification loop you can afford to run,
and writing down what breaks. That's a one-workshop idea, and I have a year of scar tissue
to teach it from.

---

## What I would do on campus

**A founding cohort on day one.** The club doesn't start cold: the Data Science department is
my own, and Prometheus gives me an existing network of AI-focused students across several
Seoul campuses to recruit from and co-host with. Most single-campus clubs can't offer that
second channel.

- **Ship Night (weekly, 2h).** Not a lecture — everyone leaves with a deployed thing. Ladder:
  a claudebar-sized tool → a first MCP server (via MCP_supporter) → an agentic CI loop.
- **"Verify It" workshop.** Building a test/CI harness for AI-generated code you can't read
  line-by-line. Concrete, straight from the TempoRoutine ledger.
- **Research track for non-CS majors.** Ewha's strength is that most students here aren't
  engineers. Claude Projects for thesis literature review, artifacts for data-heavy
  coursework, MCP for wiring research tools together — starting with the departments
  adjacent to Data Science [name 2–3].
- **Competition cohort.** JejuNow was a competition entry I took from idea to
  submitted-and-deployed. Korea runs public-data and tourism-data competitions on a fixed
  annual calendar; I'd run a group that ships into one, using Claude for the pipeline work
  that usually kills student entries before submission.
- **Cross-campus hackathon.** A joint build weekend with Prometheus — the kind of event that
  makes an Ewha club visible beyond Ewha.

---

## Technical Skills

**Languages** Python · Swift · Kotlin · TypeScript · SQL
**ML / Data** PyTorch, LightGBM, scikit-learn, pandas, OpenCV, Hugging Face Hub;
time-split validation, sampling-bias analysis, annotation standards and tooling
**Mobile** SwiftUI, SwiftData, CloudKit, WidgetKit, Live Activities, App Intents, StoreKit 2;
Jetpack Compose, Room
**Backend / Web** FastAPI, Celery, Next.js, Supabase/PostgreSQL, Prisma, Streamlit, Flask
**AI tooling** Claude Code, Model Context Protocol (server authoring), Claude Skills, Anthropic API
**Infra / Quality** GitHub Actions (multi-job macOS/Linux), App Store Connect API, Vercel, Render,
XcodeGen, Gradle; `mypy --strict` + `ruff` clean as a standing gate

---

## Languages

Korean (native) · English (TOEIC 810)
