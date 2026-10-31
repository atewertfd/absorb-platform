---
name: perf-measure
description: Measure Absorb Plus RAM and CPU on Windows with fixed scenarios, before and after a change, and record the results. Use for any performance claim ("faster", "less RAM") or perf regression check.
---

# Measure performance

Never claim a speed or memory improvement without numbers from this procedure.

1. Build the version to measure (use the `build-verify` skill) and note its version.
2. Start `build\windows\x64\runner\Release\absorb.exe`. Sign in to the **throwaway test server** (`.\tool\dev.ps1 server up`, then `server seed`; credentials in `tool/test-server/.env`), never the owner's real server. Wait 30 seconds after launch.
3. Run each scenario for 60 seconds and record its output:
   ```powershell
   .\tool\measure-windows-usage.ps1 -Seconds 60 -Label "idle on Home"
   .\tool\measure-windows-usage.ps1 -Seconds 60 -Label "playing a book"
   .\tool\measure-windows-usage.ps1 -Seconds 60 -Label "scrolling the library"
   .\tool\measure-windows-usage.ps1 -Seconds 60 -Label "downloading a book"
   ```
   The script only reads process counters. It never changes the app.
4. Do the same on the comparison build, on the same machine and close in time, with the same steps.
5. Write the results to `docs/perf/<version>.md`. Use a table of scenario × average/peak working set, private MB and CPU % of one core, and add notes such as uptime, the library size and what was playing.
6. Report the differences, and call out noise. On this machine, differences under about 5% CPU or 15 MB are within noise.

If a scenario can't be driven by hand, for example because no one is at the keyboard, say so instead of making up numbers.
