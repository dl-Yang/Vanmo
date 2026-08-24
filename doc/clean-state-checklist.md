# Clean State Checklist

Complete each applicable item before ending a substantive work session. Record why an item does not apply instead of silently skipping it.

## Repository and Verification

- [ ] `git status --short` was reviewed, and no unrelated user changes were overwritten or deleted.
- [ ] `./init.sh` completed dependency resolution, VanmoCore tests, and cross-platform static checks successfully.
- [ ] Platform verification matching the change was run: `./run_device.sh` or `--simulator` for iOS, and `--macos` for macOS.
- [ ] If `project.yml` changed, `xcodegen generate` was run and `project.pbxproj` was not edited manually.
- [ ] Any unexecuted device or UI flow is explicitly marked unverified; unit tests are not presented as manual verification.

## State and Evidence

- [ ] `doc/agent-progress.md` records the actual commands, results, risks, and next step.
- [ ] `doc/feature_list.json` has at most one `in_progress` feature, and every `passing` feature has verification evidence.
- [ ] `doc/session-handoff.md` was updated for long-running or unfinished work.
- [ ] Changes to architecture boundaries, data flows, or build configuration were reflected in `ARCHITECTURE.md`.
- [ ] Documentation and logs contain no passwords, tokens, cookies, complete authenticated URLs, or user file contents.

## Recoverability

- [ ] No undocumented partial step, temporary diagnostic code, or background task remains.
- [ ] The next session can determine current state, verification commands, and the next task from repository documentation alone.
- [ ] No commit or push was performed without explicit user authorization.