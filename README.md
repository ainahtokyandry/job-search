# job-search

A job search that runs itself.

Twice a week — or on whatever schedule you pick — a background agent sweeps job
boards for openings that match your profile, keeps only the ones posted in the
last few days, checks that you are actually eligible for them, and writes a dated
Markdown report into `reports/`. A small menu bar indicator shows when the next
run is due and opens the latest report in one click.

It runs entirely on your own Mac. Nothing is uploaded, no account is created, and
your profile, your CV and your results never leave the machine.

```
◷ Sun 08:00
├── Next run:  Sun 3 Aug, 08:00  (2d 14h)
├── Last run:  Wed 30 Jul, 15:00  (18h ago)
├── Open latest report  (2026-07-30)
├── Open project folder
├── Run search now…
└── Quit
```

## Why

Job boards reward whoever shows up first, and the good listings on the
remote-friendly ones are gone within days. Checking six or seven boards by hand,
twice a week, is dull enough that you stop doing it. This does the sweep on a
schedule and hands you a short, deduplicated, date-verified list instead.

What you get per listing: title and company, stack keywords, remote policy and an
eligibility note, posting date, rate or salary when it is published, the language
of the posting, and a direct link. Listings whose date or eligibility cannot be
confirmed are flagged rather than silently dropped, and a closing section records
any board that was unreachable.

## Requirements

- macOS (the scheduler uses `launchd`)
- [Claude Code](https://claude.com/claude-code) installed and signed in — the CLI
  does the searching, so an active subscription or API access is needed
- Xcode Command Line Tools, only for the optional menu bar app
  (`xcode-select --install`)

## Install

```sh
git clone https://github.com/ainahtokyandry/job-search.git
cd job-search
./setup.sh
```

`setup.sh` asks four things, and every one of them has a sensible default you can
accept with Return:

1. **When to run.** The default is Sunday 08:00 and Wednesday 15:00. Choose your
   own days and times instead — any number of slots, for example
   `Mon 09:00, Thu 18:30`.
2. **What to search for.** Keep the default profile, answer a handful of
   questions about the role, stack and place you want, **build the profile from
   your CV**, or open the file and write it yourself.
   The default in [`profile.default.md`](profile.default.md) looks for
   JavaScript/TypeScript developer roles — fullstack, frontend, backend or mobile,
   any seniority — for a candidate based in Madagascar: remote-worldwide boards,
   the French-speaking market, and Malagasy job boards, in French or English.
   Unless that happens to describe you, pick one of the other three.
3. **Whether to install the background agent** that runs the searches.
4. **Whether to install the menu bar indicator.**

Re-run `./setup.sh` whenever you want to change any of it; it offers your current
settings as the new defaults.

## Everyday use

```sh
./run-search.sh --force   # run one now, outside the schedule
./uninstall.sh            # remove the agents and the menu bar app
```

Reports land in `reports/job-search-YYYY-MM-DD.md`. Logs, including everything the
agent did during a run, land in `logs/search-YYYY-MM-DD.log`.

## Configuration

`setup.sh` writes two files. Both are yours, both are gitignored, and both can be
edited by hand.

**`config.env`** — the mechanics:

| Key | Meaning |
| --- | --- |
| `SCHEDULE` | Comma-separated `<Day> <HH:MM>` slots, local time |
| `HEARTBEAT_SECONDS` | How often to check whether a slot is due |
| `MAX_ATTEMPTS` | Retries before a failed slot is abandoned |
| `MAX_AGE_DAYS` | Ignore anything posted longer ago than this |
| `REPORTS_DIR`, `REPORT_PREFIX` | Where reports go and how they are named |
| `CLAUDE_BIN` | Path to the CLI; empty means autodetect |
| `NOTIFY` | `0` silences macOS notifications |

Changing `HEARTBEAT_SECONDS` means reinstalling the agent, so re-run `./setup.sh`
after editing it. The other keys take effect on the next run.

**`profile.md`** — what to look for. It is prose, pasted straight into the
agent's prompt, so you can write anything a human would understand: the roles you
want, the stacks, where you live, which languages you work in, what makes you
eligible for a listing, which boards to sweep and which to never touch. Start
from [`profile.default.md`](profile.default.md) and edit freely; the more
specific the eligibility rules, the less noise comes back.

## How the scheduling works

`launchd` wakes `run-search.sh` every `HEARTBEAT_SECONDS`. The script works out
the most recent slot that has come due, compares it against the last one it
completed (`.last-run`), and exits in milliseconds when there is nothing to do.

The heartbeat is deliberate: `StartCalendarInterval` silently never fires on some
machines, and a calendar trigger has no memory, so a slot that falls while the
Mac is asleep or shut down is lost. This design catches up instead — a missed
slot runs at the first heartbeat after the machine wakes. A failed run is retried
up to `MAX_ATTEMPTS` times, then abandoned so a hard failure cannot loop.

A `.run.lock` directory guarantees one search at a time. `.last-run`, `.attempts`
and `.run.lock` are the whole of the runtime state, and none of them are
committed.

## Layout

```
setup.sh              interactive installer and reconfigurator
run-search.sh         the scheduled runner; the gate, retries and locking
prompt-template.md    the instructions sent to the agent, minus your profile
profile.default.md    the shipped default profile, copied to profile.md
config.example.env    every setting, documented
lib/config.zsh        config loading and schedule maths, shared by the scripts
menubar/              the menu bar app and its build script
uninstall.sh          removes the agents and the app
```

## Privacy

Your `config.env`, `profile.md`, CV, reports and logs stay on your machine and are
excluded from version control. Searching sends your profile to the Claude API as
part of the prompt, the same way it would if you asked in the app; nothing else is
transmitted anywhere.
