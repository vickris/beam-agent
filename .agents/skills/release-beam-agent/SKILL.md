---
name: release-beam-agent
description: "Use when preparing, validating, or publishing a BeamAgent release, including version changes, changelog review, package contents, documentation, tests, and release checks."
---

# Prepare a BeamAgent Release

## Release checklist

1. Inspect the current version in `mix.exs`, `CHANGELOG.md`, repository status, and the changes since the last release. Do not assume a version bump or release date; determine the intended release scope and follow the project's SemVer/Keep a Changelog conventions.
2. Verify that the changelog describes user-visible changes under the correct version and that breaking changes are clearly called out. Do not rewrite historical entries unnecessarily.
3. Review `mix.exs` package configuration. Confirm the source, README, license, changelog, and intended public documentation are included; call out that repository-only agent guidance and planning files should not be shipped unless explicitly intended.
4. Check that README/API documentation matches the public API and that supported Elixir requirements are unchanged or deliberately updated.
5. Run `mix format --check-formatted`, `mix compile`, and `mix test`. Run the documentation build (for example, `mix docs`) if the release changes public docs and the dev dependencies are available. Report any unavailable check rather than claiming success.
6. Review the final diff for generated files, accidental secrets, unrelated changes, stale version references, and package contents. Make no release commit, tag, push, or package publication unless explicitly requested.
7. Summarize readiness, version/changelog changes, checks and their results, and any remaining release blockers.
