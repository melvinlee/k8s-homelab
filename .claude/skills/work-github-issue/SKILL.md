---
name: work-github-issue
description: Start working on a GitHub issue in an isolated worktree - read the issue with gh, create a Supacode worktree on branch <issue-number>-<slug> based on main, copy gitignored local files into it, then launch a sandboxed Claude ("sbx run claude") primed as the devops subagent with the issue as context. Trigger when the user asks to work on, start, or pick up a GitHub issue.
---

# Start Working on a GitHub Issue in a Worktree

## Prerequisites

Run from the main repo root inside a Supacode terminal (`$SUPACODE_REPO_ID` is set), with `gh` authenticated and `sbx` + `jq` installed.

## Steps

Get the issue number from the user (resolve title/URL via `gh issue list` if needed). Then run everything below as **one single Bash call** — variables like `$BRANCH` and `$WORKTREE_PATH` are lost across separate tool calls.

```sh
ISSUE=<number>

# 1. Read the issue
gh issue view "$ISSUE" --json number,title,body,url > "/tmp/issue-$ISSUE.json"
# Compose the slug yourself: short kebab-case of the title with any conventional-commit
# "type(scope):" prefix stripped, e.g. "feat(security): add Trivy Operator for cluster
# vulnerability scanning" -> 61-trivy-operator-vulnerability-scanning
BRANCH="$ISSUE-<slug>"

# 2. Create the worktree — it prints the new worktree ID (percent-encoded path) to stdout; capture it.
#    The checkout lands asynchronously, so poll git for the filesystem path.
#    (No awk with $-field references here: slash-command argument templating mangles them.)
WORKTREE_ID=$(supacode repo worktree-new -r "$SUPACODE_REPO_ID" --branch "$BRANCH" --base main --name "$BRANCH")
WORKTREE_PATH=""
for _ in $(seq 1 30); do
  WORKTREE_PATH=$(git worktree list --porcelain | grep -B2 -x "branch refs/heads/$BRANCH" | sed -n 's/^worktree //p')
  [ -n "$WORKTREE_PATH" ] && break
  sleep 1
done
[ -n "$WORKTREE_PATH" ] || { echo "ERROR: worktree for $BRANCH never appeared" >&2; exit 1; }

# 3. Copy gitignored-but-needed local files (.envrc, talos/configs/, */resources/secret.yaml,
#    .claude/settings.local.json, .terraform.lock.hcl). Excludes OS junk and the regenerable
#    terraform provider cache — run `terraform init` in the worktree if the issue touches terraform/.
git ls-files --others --ignored --exclude-standard -z -- ':!*.DS_Store' ':!terraform/.terraform/**' \
  | tar -cf - --null -T - | tar -xf - -C "$WORKTREE_PATH"

# 4. Drop the issue + devops-subagent context into the worktree for the sandboxed agent
jq -r '"# Issue #\(.number): \(.title)\n\n\(.url)\n\n\(.body)"' "/tmp/issue-$ISSUE.json" > "$WORKTREE_PATH/TASK.md"
cat >> "$WORKTREE_PATH/TASK.md" <<'EOF'

---
## Agent context
You are working this issue in an isolated worktree inside a Docker sandbox. Launch the **devops-expert** subagent (defined in `.claude/agents/devops-expert.md`) to drive the deployment work. Follow CLAUDE.md. Commits use Conventional Commits with no Co-authored-by trailers, and require explicit user approval first. Never commit TASK.md. Do not push or open a PR without the user saying so.
EOF

# 5. Launch the sandboxed agent in a new Supacode tab on the worktree (tab ID must be captured — see
#    supacode-cli skill). The MAIN repo must be mounted as a second workspace: a linked worktree is
#    not self-contained — its .git file points into the parent repo's .git/worktrees/<name>, and
#    commits write objects/refs there. Without the parent repo mounted read-write at its identical
#    host path, every git command in the sandbox fails with "fatal: not a git repository".
TAB_ID=$(supacode tab new -w "$WORKTREE_ID" -i "sbx run claude '$WORKTREE_PATH' '$PWD' -- --dangerously-skip-permissions 'Read TASK.md at the repo root and use the devops-expert subagent to work the issue it describes.'")
echo "branch=$BRANCH worktree=$WORKTREE_PATH tab=$TAB_ID"
```

Skipping permission prompts is safe here because the agent runs inside the Docker sandbox, isolated to the worktree.

If not inside a Supacode terminal, stop after step 4 and tell the user to run `sbx run claude "$WORKTREE_PATH" "<main-repo-root>" -- --dangerously-skip-permissions '<same prompt>'` themselves.

## Report back

Tell the user the issue number/title, branch name, worktree path, and that the sandboxed devops agent is running in the new tab. Do not manage the sandboxed agent afterwards — the user drives it from the tab.

## Cleanup (after the issue is merged)

`supacode worktree delete -w <worktree-id>` — or closing the worktree in the Supacode UI — removes **both** the worktree directory and its branch. `sbx rm --force claude-<branch>` removes the sandbox (`--force` is required non-interactively). Warn the user not to close the worktree while the issue is still in progress: uncommitted work and the copied local files go with it.
