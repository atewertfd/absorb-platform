---
name: status
description: Quick health report for the Absorb Plus repo — branch, uncommitted work, upstream lag, recent CI, fork footprint, latest releases. Use at the start of a work session or when the owner asks where things stand.
---

# Status

Run these, then summarize in a few plain sentences:

```bash
git status --short --branch
git fetch origin --quiet && git fetch fork --quiet
git rev-list --left-right --count HEAD...fork/$(git rev-parse --abbrev-ref HEAD)   # unpushed / behind
git rev-list --count HEAD..origin/main                                            # upstream commits not merged
git log --oneline HEAD..origin/main | head -15
gh run list --repo atewertfd/absorb-platform --limit 6
gh release list --repo atewertfd/absorb-platform --limit 5
```

```powershell
.\tool\dev.ps1 footprint
```

Report:
- what's uncommitted or unpushed;
- how far behind upstream the branch is, and whether those upstream commits touch files the fork changed (`git diff --name-only HEAD...origin/main` against `git diff --name-only origin/main...HEAD`);
- failing CI;
- the latest release and whether it's Latest or a pre-release;
- the footprint trend.

Suggest the next action: merge upstream, release, or fix CI.
