# [FULL NAME] (한글 이름)

B.S. Data Science · Ewha Womans University, Seoul, Korea
[email] · GitHub [github.com/Yewon419](https://github.com/Yewon419) · [LinkedIn / portfolio URL]

**Applying to:** Claude Campus — Builder Club Lead (undergraduate track)

---

## Summary

Undergraduate data science student who ships production software solo. Over the past
year I have designed, built, localized, and released a two-platform mobile product to
TestFlight beta, plus an open-source CI tool and two Claude-ecosystem developer tools —
27 public and private repositories in total. Every one of them was built in a paired
agentic workflow with Claude Code, on a Windows machine with no local Apple toolchain,
which forced me to develop a rigorous, written methodology for verifying AI-generated
code. That methodology — not the app — is what I want to teach other students.

---

## Education

**Ewha Womans University** — B.S., Data Science
Seoul, Korea · Expected graduation [YYYY.MM]
Relevant coursework: [machine learning / statistics / databases / algorithms — fill in]
[GPA — include only if strong]

---

## Selected Projects

### TempoRoutine — production iOS + Android app (closed TestFlight beta)
`Swift · SwiftUI · SwiftData · CloudKit · Kotlin · Jetpack Compose`
[github.com/Yewon419/TempoRoutine](https://github.com/Yewon419/TempoRoutine)

An on-device, account-free cycle-aware routine planner. Sole engineer, designer, and
release manager.

- ~29,000 lines of Swift across 114 files; 18 SwiftData models, 9 widget surfaces
  (home + lock screen) and a Live Activity, CloudKit `CKSyncEngine` device sync.
- Prediction engine isolated in **TempoCore**, a dependency-free Swift package covered by
  **161 unit tests** so the domain logic can be verified on a Linux CI container without
  a Mac.
- Localized into **4 languages** (ko / en / ja / zh-Hans, 944 string keys) behind a single
  lookup path, audited by a Python tool I wrote after discovering 341 hard-coded strings
  silently bypassing the catalog.
- Ported the entire engine to **Kotlin 1:1** (~8,650 lines, 164 mirrored tests) and proved
  cross-platform equivalence with **golden JSON fixtures** compared as parse trees rather
  than bytes.
- Shipped in-app purchases, a private TestFlight beta, and a feedback-triage pipeline that
  pulls App Store Connect beta feedback via the ASC API.

### chalkak — open-source CI screenshot tool
`Shell · GitHub Actions · xcodebuild · simctl`
*"Screenshot your iOS app on every push, from CI, without a Mac and without UI tests."*

Extracted from my own constraint: I develop on Windows and cannot run a simulator. Boots a
simulator in CI, ad-hoc-signs the build (unsigned archives have no entitlements section and
die on CloudKit init), and publishes screenshots as a workflow artifact — so layout, color,
font, and dark-mode regressions are caught per push instead of per TestFlight release.

### MCP_supporter — meta MCP server
`Python · Model Context Protocol`

An MCP server whose job is installing and configuring other MCP servers from chat. Removes
the JSON-config step that stops most beginners from ever getting a first MCP server running
— the exact friction I would target in a Builder Club onboarding workshop.

### claudebar — Claude usage tray app
`Python · Windows system tray`

Surfaces live Claude usage in the Windows system tray. Small, but it is the tool I use every
day and the kind of 60-minute build that makes a good first club project.

### AutoStock — AI-driven Korean equities trading platform
`FastAPI · Vue 3 · Celery · KIS Open API`

Strategy generation, backtesting, and automated execution against the Korea Investment &
Securities API. Taught me the discipline I now apply everywhere: validate every external
feed before use, assume it can be null or stale, log every signal and execution, and never
swallow an exception.

### Violence temporal localization — ML research pipeline
`Python · PyTorch · ResNet50 · Transformer`

Locates person-to-person physical violence intervals in films. Built my own annotation tool,
then an embedding + temporal model pipeline on top of it.

**Also:** JejuNow (tourism congestion forecasting, Next.js + ML + Capacitor iOS),
HangsungDrone (B2B drone-show SaaS backend, FastAPI + Supabase), ddackdae (admissions
matching platform), jarimae, rollingpaper, cafe-finder, Mypersona (portable cross-LLM
persona layer).

---

## How I work with Claude — the part I want to teach

I do not treat Claude as an autocomplete. I treat it as a colleague working under a written
contract, and I keep the contract in the repo.

- **A failure ledger, not a style guide.** `TempoRoutine/CLAUDE.md` holds **55 rules distilled
  from 24 dated production incidents** — each rule names the symptom, the date it burned me,
  and the root cause. Example: *"lock-screen widgets rendering as blank white blocks is
  privacy redaction, not a render failure"* — written after I misdiagnosed it as a
  `Date.now` bug, shipped the wrong fix, and had to reverse myself. The ledger exists so the
  same mistake costs one CI cycle instead of three.
- **Closing the verification loop under a hard constraint.** No Mac, no local Swift compiler.
  So correctness had to move somewhere I could actually check it: pure logic into a testable
  package, rendering into CI screenshots, and only runtime behavior (SwiftData schema,
  permissions, gestures) deferred to real-device TestFlight. "CI is green" is explicitly
  *not* "done" in my repo's rules.
- **Knowing what the model cannot know.** I have a standing rule against trusting model recall
  for library APIs — after a `glassEffect(isEnabled:)` parameter that appeared in three
  third-party references but not in the SDK cost me a full CI round trip. New-OS API surface
  gets verified by compilation, never by consensus.
- **Custom skills and a persona layer.** I maintain a private Claude skills repo and
  `Mypersona`, a portable context layer that survives moving between models.

Most students I know are stuck at "the AI wrote something and I can't tell if it's right."
The answer is not better prompting. It is designing a verification loop you can afford to run,
and writing down what breaks. That is a teachable, one-workshop idea, and I have a year of
scar tissue to teach it from.

---

## What I would do on campus

- **Ship Night (weekly, 2h).** Not a lecture — everyone leaves with a deployed thing. Ladder:
  claudebar-sized tool → first MCP server (via MCP_supporter) → an agentic CI loop.
- **"Verify It" workshop.** How to build a test/CI harness for AI-generated code you can't
  read line-by-line. Concrete, from the TempoRoutine ledger.
- **Non-CS reach.** Ewha's strength is that most students here are not engineers. Claude
  Projects for thesis literature review, artifacts for data-heavy coursework, MCP for
  connecting research tools — [name specific departments/clubs you can reach].
- **Hackathon.** [Existing Ewha club / hackathon you can partner with — fill in.]

---

## Technical Skills

**Languages** Python · Swift · Kotlin · TypeScript · SQL
**Mobile** SwiftUI, SwiftData, CloudKit, WidgetKit, Live Activities, App Intents, StoreKit 2;
Jetpack Compose, Room
**Backend / Data** FastAPI, Celery, Supabase, PostgreSQL, Prisma, pandas, PyTorch
**AI tooling** Claude Code, Model Context Protocol (server authoring), Claude Skills, Anthropic API
**Infra** GitHub Actions (multi-job macOS/Linux matrices), App Store Connect API, XcodeGen, Gradle

---

## Leadership & Activities

[Fill in — clubs, TA/tutoring, organizing, competitions, presentations. Anthropic's stated
bar is "well-connected on campus," so this section carries real weight; anything where you
convened people belongs here even if it is not technical.]

---

## Languages

Korean (native) · English ([level — e.g. professional working proficiency, TOEFL/OPIc score])
