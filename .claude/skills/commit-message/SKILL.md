---
name: commit-message
description: Write Conventional Commits-style git commit messages. Use when crafting or reviewing a commit message, staging changes for commit, or when the user asks to "commit", "write a commit message", or "follow the commit convention". Produces a structured summary plus per-file bullet points and never adds Co-authored-by trailers.
---

## Use Cases

- Writing a commit message for staged or working-tree changes
- Reviewing/rewriting a draft commit message to match the convention
- Generating the message body when running `git commit`

## Format

Structure every commit message as:

```
<type>[optional scope]: <description>

<summary of the changes>

- <file or area>: what changed and why
- <file or area>: what changed and why

[optional footer(s)]
```

- The subject line is a [Conventional Commit](https://www.conventionalcommits.org/): `<type>(<scope>): <description>`.
- Follow the subject with a one-line summary, then a bullet list detailing the files changed, what changed, and the reason for the change.

## Allowed types

| Type | Meaning | SemVer |
|------|---------|--------|
| `fix` | Patches a bug | PATCH |
| `feat` | Adds a new feature | MINOR |
| `docs` | Documentation only | — |
| `chore` | Maintenance, tooling | — |
| `ci` | CI/CD changes | — |
| `refactor` | Code change, no behavior change | — |
| `perf` | Performance improvement | — |
| `test` | Adding or fixing tests | — |
| `build` | Build system or dependencies | — |
| `style` | Formatting, whitespace | — |

## Breaking changes

Signal a breaking change either way (correlates with a MAJOR bump):

- Append `!` after the type/scope: `feat(api)!: drop legacy auth`
- Or add a footer: `BREAKING CHANGE: <description>`

A breaking change can accompany any type.

## Scope

A scope adds context in parentheses, e.g. `feat(parser): add ability to parse arrays`. In this repo, prefer the release or component name as scope (`grafana`, `cilium`, `talos`, etc.).

## Rules

- **Never** add `Co-authored-by` or any co-author trailer.
- Subject line in imperative mood, lowercase description, no trailing period.
- Keep the subject under ~72 characters; wrap the body at ~72.

## Example

```
fix(grafana): move admin credentials to gitignored secret.yaml

Admin username and password were stored in plaintext in values.yaml.
Move them to an encrypted, gitignored secret to stop leaking creds.

- releases/grafana/values.yaml: remove plaintext admin.user/admin.password
- releases/grafana/secret.yaml: add gitignored secret with credentials
- .gitignore: ignore the new secret file
```
