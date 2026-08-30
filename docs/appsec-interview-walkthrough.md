# AppSec / DevSecOps Interview Walkthrough

A complete, spoken-word guide to explaining the security process you built around a
CI/CD pipeline and a deliberately-vulnerable web app (**crAPI**). Read it top to
bottom. The goal isn't to memorize commands — it's to be able to **tell the story**
of how you think about application security, and back it with a live demo if asked.

---

## 0. The 30-second pitch (your opener)

> "I built a DevSecOps lab to practice application security end to end. It's a
> CI/CD pipeline in GitHub Actions that deploys a deliberately-vulnerable API —
> OWASP crAPI — and runs layered security scans against it. The pipeline
> shifts security left with static analysis on every push, then deploys the app
> and runs dynamic scans against the running target. I use that as a range: I
> attack the app by hand with Burp and sqlmap, confirm real vulnerabilities,
> then codify each finding as an automated test so the pipeline catches it
> forever. It taught me both sides — how vulnerabilities look in code *and* how
> they behave at runtime, and where automated tooling has blind spots."

That paragraph alone signals: you know the vocabulary (shift-left, SAST/DAST),
you understand *defense in depth*, and you have a real, reproducible artifact.

---

## 1. The mental model — the loop I run

Everything below is one repeating cycle. Name it early; interviewers love a framework.

```
   ┌─────────────────────────────────────────────────────────┐
   │   1. THREAT MODEL   → what could go wrong, what to protect │
   │   2. SHIFT LEFT     → catch issues in code, pre-deploy      │
   │   3. DEPLOY         → stand up the running target           │
   │   4. DAST           → scan the running app (automated)      │
   │   5. MANUAL TEST    → verify + find what scanners miss      │
   │   6. FIX & REGRESS  → remediate, then automate the check    │
   └────────────────────────── repeat ─────────────────────────┘
```

The one-liner to say: **"Security isn't a gate at the end — it's a control at
every stage of the SDLC, and every finding becomes a regression test."**

---

## 2. The architecture (draw this on the whiteboard)

```
  developer
     │  git push
     ▼
  ┌──────────────────────────────────────────────┐
  │  GitHub Actions — CLOUD runners               │   "shift-left" static gates
  │  ┌──────────┐ ┌──────────┐ ┌──────┐ ┌───────┐ │   run on every push, no infra cost
  │  │ secrets  │ │ SCA/CVE  │ │ IaC  │ │ SAST  │ │
  │  │ gitleaks │ │ trivy    │ │ trivy│ │semgrep│ │
  │  └──────────┘ └──────────┘ └──────┘ └───────┘ │
  └───────────────────────┬──────────────────────┘
                          │  manual trigger (Run workflow)
                          ▼
  ┌──────────────────────────────────────────────┐
  │  SELF-HOSTED runner (my box)                  │   the CD + DAST half
  │  deploy crAPI (Docker) → nuclei → OWASP ZAP    │   runs where the app is reachable
  │  → upload scan reports as build artifacts      │
  └───────────────────────┬──────────────────────┘
                          ▼
        manual attack: Burp Suite / sqlmap / ffuf
```

**Why the split matters (a strong talking point):** static analysis needs only the
source, so it runs on free cloud runners. Dynamic analysis needs the *running*
app, which lives on my host — a cloud runner can't reach `localhost` — so that
job runs on a **self-hosted runner**. Being able to explain *why* each job runs
where it does shows you understand the tooling, not just copied a template.

---

## 3. Step-by-step walkthrough (the core of your explanation)

For each stage: **what it is → why → the tool → what to say.**

### Stage 1 — Threat modeling (start here; most candidates skip it)

- **What:** Before scanning, ask *what are we protecting and from whom?* For an API:
  authn/authz, the data (PII, payment), the trust boundaries between services.
- **Why:** Tools find what they're told to. Threat modeling decides what matters.
- **Say:** "I map the attack surface first — endpoints, auth flows, trust
  boundaries — using something like the STRIDE categories or the OWASP API
  Security Top 10. crAPI is built around those: broken object-level
  authorization, broken authentication, mass assignment."
- **Name-drop correctly:** **OWASP API Security Top 10** (BOLA/API1, Broken Auth/API2,
  Mass Assignment/API6). BOLA = "Broken Object Level Authorization" = IDOR for APIs.

### Stage 2 — Shift-left: static gates on every push

These run in the cloud, on every `git push`, before anything deploys. Four categories —
know the difference cold, because interviewers test it:

| Category | Question it answers | Tool here | Needs the app running? |
|----------|--------------------|-----------|------------------------|
| **Secret scanning** | Did we commit a credential? | gitleaks | No |
| **SCA** (Software Composition Analysis) | Are our dependencies / base images vulnerable (known CVEs)? | trivy (image scan) | No |
| **IaC scanning** | Is our infra config misconfigured? | trivy (config scan) | No |
| **SAST** (Static Application Security Testing) | Are there vuln patterns in *our* source? | semgrep | No |

- **Say:** "Shift-left means catching problems while they're cheapest to fix —
  in code review, not in production. These four gates are analyzing the source
  and the supply chain without ever executing the app."
- **Real result to cite:** "My image scan flagged a **CRITICAL CVE** in the
  `postgres:14` base image — that's the SCA lesson: most risk rides in
  dependencies you didn't write."
- **Honest nuance (this impresses):** "My secret scanner came back clean even
  though the app has hardcoded demo passwords — because they're low-entropy
  strings like `JWT_SECRET=crapi`, and gitleaks' default rules target
  high-entropy values and known token formats. That taught me scanners only
  catch what they have a rule for — you have to tune them."

### Stage 3 — Deploy the target

- **What:** The pipeline brings the app up in Docker on the self-hosted runner.
- **Why:** Dynamic testing needs a live, running instance.
- **Say:** "This is the CD half. The same compose definition is version-controlled
  in the repo — infrastructure as code — so the environment is reproducible."

### Stage 4 — DAST: scan the running app

**DAST = Dynamic Application Security Testing** — black-box testing against the
*running* app, the way an attacker sees it. I run **two** scanners on purpose:

- **nuclei** — fast, template-driven. Checks for specific known issues
  (exposed files, misconfigurations, default logins).
- **OWASP ZAP (baseline)** — spiders the app, then runs passive checks
  (security headers, cookie flags, information disclosure).

- **Say:** "I run two because they have different coverage — and the *gap*
  between them is the lesson."
- **Real result to cite:**

  | Scanner | Found |
  |---------|-------|
  | nuclei | `/.env` exposed — leaking DB credentials (High) |
  | ZAP | Missing security headers: no CSP, no `X-Content-Type-Options`, server version leak |

  "Neither alone gives the full picture. That's why defense in depth applies to
  *tooling* too, not just controls."

### Stage 5 — Manual verification (where real skill shows)

- **What:** Confirm scanner findings by hand and hunt for what scanners can't
  find — business-logic and authorization flaws.
- **Why:** Automated DAST is great at known patterns and terrible at logic. No
  scanner *understands* that user A shouldn't read user B's vehicle record.
- **Tools:** **Burp Suite** (intercepting proxy — the core tool), **sqlmap**
  (SQL injection), **ffuf** (content/endpoint discovery).
- **Say:** "I verify every automated finding — false positives waste everyone's
  time — then I go after the logic flaws: **BOLA/IDOR** by swapping object IDs,
  **broken JWT** by tampering with the token, **mass assignment** by adding
  fields the API trusts blindly. Those are the API1/API2/API6 issues no scanner
  reliably catches."

### Stage 6 — Fix and regress

- **What:** Remediate the finding, then write an automated check so it can't
  silently come back.
- **Why:** A fix without a regression test rots. This closes the loop.
- **Say:** "Every confirmed vuln becomes a nuclei template checked into the repo.
  Next push, the pipeline re-tests it. That's how a finding turns into a durable
  control — remediation plus prevention of regression."

---

## 4. The tools, and the category each proves you know

Interviewers probe whether you know *why* a tool, not just its name.

| Tool | Category | One-line "why" |
|------|----------|----------------|
| gitleaks | Secret scanning | Credentials in git history are a top breach cause |
| trivy | SCA + IaC | Finds CVEs in images/deps and misconfigs in infra |
| semgrep | SAST | Pattern-matches vulnerable code at the source |
| nuclei | DAST | Fast, templated runtime checks; easy to extend |
| OWASP ZAP | DAST | Spider + passive analysis; broad web coverage |
| Burp Suite | Manual DAST / proxy | The workhorse for hands-on testing & logic flaws |
| sqlmap | Exploitation | Confirms & weaponizes SQL injection |
| ffuf | Discovery | Fuzzes for hidden endpoints/params |

Say the categories out loud: **"secrets, SCA, IaC, SAST are static; nuclei, ZAP,
Burp are dynamic."** That mapping is the thing many candidates fumble.

---

## 5. Concepts to state precisely (rapid-fire prep)

- **Shift-left:** move security earlier in the SDLC (design/code) where fixes are cheap.
- **SAST vs DAST vs IAST:** static (reads code, no execution) / dynamic (tests the
  running app, no source needed) / interactive (instrumentation inside a running app,
  combines both).
- **SCA:** analyzing third-party dependencies & base images for known CVEs.
- **Defense in depth:** layered controls so one failure isn't fatal — here, multiple
  scanners plus manual testing.
- **Gating vs report-only:** a gate *fails the build*; report-only *informs*. I run
  most gates report-only in a lab so I can study findings, and I'd tighten to
  hard-fail on CRITICAL in a real org. Knowing *when* to block is judgment, not
  just config.
- **False positive / false negative:** why human verification and tuning matter.
- **OWASP Top 10 vs OWASP API Security Top 10:** know both exist; crAPI targets the API one.

---

## 6. The "war stories" (senior-level signal — use 1 or 2)

Real debugging beats a clean demo. It shows you operate, not just follow tutorials.

- **Resource-aware engineering:** "The app stack wouldn't start on a 4 GB box —
  MongoDB's health checks timed out because the host was thrashing and swap was
  full. I diagnosed it from the container health logs, capped Mongo's WiredTiger
  cache, raised the memory limit, and lengthened the health-check timeout so a
  slow-but-alive service wasn't killed. Root cause was host RAM, so I also
  right-sized the VM." → *shows systematic debugging + reading the actual signals.*

- **Understanding the failure, not just the fix:** "Trimming the app to save RAM
  broke the web tier — its nginx resolves every upstream at startup, so a removed
  service made it hard-fail with `host not found in upstream`. I added a tiny
  stub so DNS resolves, gated behind a compose profile." → *shows you understand
  systems, not just security.*

- **Tuning a scanner:** "My first nuclei run loaded only one template because a
  single `-t` flag overrode the built-in template store. Fixed the flags; loads
  jumped from 1 to ~1,800. Lesson: verify your tooling is actually doing what you
  think — an empty result can mean 'misconfigured', not 'secure'." → *the single
  most valuable appsec instinct: distrust a clean scan until you've proven it ran.*

- **Supply-chain / pinning:** "I pinned a GitHub Action to a bad version tag and
  the job failed to resolve it; I re-pinned to the release's immutable commit SHA.
  Pinning actions to a SHA is also a supply-chain control — a moved tag can't
  swap code under you." → *ties a bug to a real security principle.*

---

## 7. Live demo script (if you can share your screen)

Keep it under ~5 minutes. Narrate every command with *what it proves*.

```bash
# 1. Show the pipeline as code
cat .github/workflows/static-gates.yml     # "security defined as code, versioned"

# 2. Bring the target up
make up                                     # "reproducible env from one compose file"

# 3. Run the dynamic scan the pipeline runs
make dast                                   # "DAST against the live app — finds /.env"

# 4. Prove the finding is real (verify, don't trust)
curl http://127.0.0.1:8888/.env             # "HTTP 200, real leaked DB creds"

# 5. Show the automated report from CI
gh run view <run-id>                         # "the same gate, green, in CI"

# 6. Free resources
make down
```

If you can't run it live, walk the same steps from screenshots or the repo.

---

## 8. Questions they'll ask — and strong answers

**Q: SAST vs DAST — when do you use each?**
A: SAST early, in code review, on every commit — it reads source, needs no running
app, and pinpoints the vulnerable line, but produces more false positives. DAST later,
against a deployed build — it tests real runtime behavior including config and auth,
finds no source-line, but confirms exploitability. They're complementary; I run both.

**Q: How do you handle false positives?**
A: Triage every finding — verify manually before it goes to a developer. In CI I
start report-only to learn the baseline, tune rules/allowlists, then promote to
hard-gate the categories I trust (e.g., fail on CRITICAL CVEs or any secret).

**Q: Would you block the pipeline on findings?**
A: Depends on severity and confidence. Secrets and CRITICAL CVEs — hard fail.
Noisy or low-severity DAST warnings — report-only with a tracked ticket, so I
don't train developers to ignore a red build. Blocking on everything is how teams
learn to bypass security.

**Q: Your scanners find nothing — are you secure?**
A: No — a clean scan can mean the scanner didn't run right, lacks a rule for the
issue, or the bug is business logic no tool understands. I verify the scan actually
executed (template counts, request counts) and always pair automation with manual
testing. (I hit exactly this — a "clean" run that had loaded one template.)

**Q: How does this scale to a real org?**
A: Same shape, more rigor: SAST/SCA as required PR checks with severity gates,
DAST against ephemeral staging per PR, secrets scanning as a pre-commit hook *and*
a server-side gate, results centralized (e.g., DefectDojo/SARIF to the Security
tab), SLAs on remediation, and periodic manual pentests for logic flaws. Pin and
verify your CI supply chain. The lab is the same philosophy at small scale.

**Q: Why crAPI and not a scanner-friendly app like Juice Shop?**
A: crAPI targets the **API** Security Top 10 — BOLA, broken auth, mass assignment —
which are the authorization and logic flaws that dominate real API breaches and
that automated scanners struggle with. It forces manual skill, not just tooling.

---

## 9. What I'd build next (shows growth mindset)

- Add my *own* microservice under `services/` so the SAST gate runs on code I wrote.
- Promote select gates from report-only to hard-fail on CRITICAL.
- Centralize findings (SARIF → GitHub code scanning / DefectDojo) instead of raw logs.
- Add container runtime hardening and a signed-image / SBOM step.
- Wire DAST against an ephemeral per-PR environment instead of a static host.

---

## 10. The single sentence to leave them with

> "The point of the lab isn't the tools — it's the discipline: threat model,
> shift left, verify everything a scanner tells you, and turn every finding into
> a test. Tools change; that process doesn't."
