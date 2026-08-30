# DevSecOps lab: CI/CD pipeline around crAPI

A hands-on lab for building **app-sec + DevSecOps skill**. A GitHub Actions
pipeline deploys the deliberately-vulnerable **crAPI** target, gates it with
automated security scans, and leaves it running so you attack it by hand — then
you fix, re-run, and watch the gates react.

```
 commit ──► GitHub Actions (cloud) ──► static gates: secrets, image CVEs, config, SAST
                                        │
                                        ▼  (manually triggered)
              self-hosted runner (this Kali box) ──► deploy crAPI + nuclei DAST
                                        │
                                        ▼
                 you attack :8888 with Burp / sqlmap / ffuf / nuclei
```

## Why it's split into two workflows

- **`static-gates.yml`** runs on **GitHub-hosted runners** — free, and it uses
  *none* of your box's ~4 GB RAM. Secret scan, image CVE scan (crAPI's
  `postgres:14` / `mongo:4.4` images have real CVEs — read them), config scan,
  and a SAST job wired for `./services` (your own future code).
- **`deploy-dast.yml`** runs on a **self-hosted runner on this box**, because a
  cloud runner can't reach crAPI on your `localhost`. It deploys crAPI, runs
  nuclei, uploads the report, and (by default) leaves crAPI up for manual attack.

## One-time setup

1. **Create the GitHub repo and push.** In the Claude Code prompt you can run
   shell directly with a leading `!`:
   ```
   ! gh auth login              # if gh isn't set up yet (install: sudo apt install gh)
   ! gh repo create devsecops-crapi --private --source=. --remote=origin --push
   ```
   (Or make an empty repo on github.com and `git remote add origin … && git push -u origin main`.)
   Pushing immediately triggers **static-gates** on the cloud — check the Actions tab.

2. **Register the self-hosted runner** (needed only for the DAST workflow).
   On github.com: *repo → Settings → Actions → Runners → New self-hosted runner*,
   pick Linux, and run the shown `./config.sh …` + `./run.sh` on this box. When it
   asks for labels, add **`kali`** (the workflow targets `[self-hosted, kali]`).

## Daily loop

```bash
make up            # deploy crAPI locally
make dast          # run the pipeline's nuclei scan by hand
make attack-info   # print target URLs + tool starting points
# ... attack http://127.0.0.1:8888 with Burp / sqlmap / ffuf ...
make down          # free RAM when done  (this box is tight — do this!)
```

Or trigger the full pipeline from GitHub: *Actions → deploy-and-dast → Run workflow*.

## The learning loop that actually builds skill

1. **Attack** crAPI by hand, confirm a real bug (start with BOLA/IDOR, JWT, mass
   assignment — crAPI's classic vuln classes).
2. **Codify it**: write a nuclei template for it in `security/nuclei-templates/`
   (copy the starter template there). Now the pipeline regression-tests it.
3. **Compare** what your automated DAST caught vs. what you found manually — the
   *gap* is the real lesson about scanner blind spots.
4. **Extend**: add your own small microservice under `./services/` and watch the
   SAST (semgrep) gate light up on real source.

## Resource note

This box has ~4 GB RAM and crAPI is ~10 containers. Run **one** thing at a time
and `make down` when you're finished. If it's too heavy, comment out
`crapi-chatbot` / `chromadb` in `target/docker-compose.yml` (the AI features you
won't attack) to reclaim memory.

## Layout

```
.github/workflows/static-gates.yml   cloud gates: secrets, CVE, config, SAST
.github/workflows/deploy-dast.yml    self-hosted: deploy crAPI + nuclei DAST
target/docker-compose.yml            vendored crAPI stack (infra-as-code)
security/nuclei-templates/           your custom DAST checks (add as you learn)
services/                            your own code goes here (exercises SAST)
Makefile                             up / down / dast / attack-info helpers
```
