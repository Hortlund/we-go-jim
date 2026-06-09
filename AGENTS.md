# WGJ Agent Playbook

- Inspect the repo and current worktree before changing code.
- Keep WGJ local-first. Active workout progress and template edits persist locally during edits; CloudKit backup is best-effort only at explicit save boundaries.
- Keep SwiftUI thin. Put persistence and business rules in repositories/services, not view bodies.
- Respect SwiftData boundaries. Avoid broad background sync, no-op save churn, and CloudKit work on interaction paths.
- Verify with focused builds/tests when requested. If verification is skipped by request, say so clearly.
