# Development and Release

The packages in this manual are developed as a set of colocated Jujutsu repositories with one published branch each. This chapter describes the delivery rules a change follows: how work is tracked, how a commit is written and checked, how it reaches the remotes, how an integrated checkpoint is recorded, and how history is inspected or recovered. It defines no interfaces; it is the process that keeps the revisions in `workspace.json` meaningful.

## One working copy, one writer

<!-- index: colocated repository; working copy; workspace -->

Each repository is a Jujutsu repository colocated with Git. Jujutsu owns the working copy: the current commit `@` is the working copy, every command snapshots files into it, and Git's detached `HEAD` is expected. A commit is sealed with `jj commit <paths> -m "…"`, which puts the named paths into a finished change and starts an empty `@`; naming paths seals only your work, so a commit never sweeps up someone else's unfinished changes. A working copy has one writer: run `jj st` before editing, and when `@` already holds changes you did not make, seal only your own paths and coordinate before touching a file you both edit. Parallel work uses a separate `jj workspace add <dir>` checkout, never a Git worktree. Published history is the exception that must be respected: `immutable_heads()` includes remote bookmarks, so a published commit is not rewritten by accident.

## Commits

<!-- index: conventional commit; validation footer; breaking change -->

A commit is one explainable, independently reviewable and revertible change — one coherent feature, fix, move or documentation update with its regression coverage and documentation where they belong, not a fixed count of files. Unrelated changes are split so that each commit remains usable for bisection. Messages follow Conventional Commits: `type(scope): concrete imperative English summary`, where the type is one of `feat`, `fix`, `docs`, `refactor`, `perf`, `test`, `build`, `ci`, `chore` or `revert`. The title is at most 72 characters and avoids generic phrases; after a blank line the body explains the problem and the resulting behavior or the reason for the change. A `Validation:` line names the commands that were actually run and their results, or says why a check was not run. A breaking change carries both `!` in the title and a `BREAKING CHANGE:` footer that explains the impact and the migration. Generated merge or revert messages are edited to follow the same contract; the message checker verifies the format, not the facts.

## Checks before publishing

<!-- index: commit message check; staged tree; fast-forward -->

Before anything is published, every commit in the publish range is checked, and so is the tree it produces. From the repository being published, the four checks are: render each commit's description to a file and run `python3 scripts/check-commit-message.py` on it; run `python3 scripts/check-repository.py --staged` from the repository root, which validates the sealed tree the colocated Git index mirrors; run `jj log -r '(<range>) & (conflicts() | divergent() | description(exact:""))'`, which must print nothing; and confirm that `@-..main@<remote>` is empty, so publishing is a fast-forward. A secondary workspace checkout has no Git index, so there `--staged` accepts only an empty `@` and checks that sealed working copy instead. The workspace root's copy of the checker defaults its root to the workspace, so the command is run from the child repository whose tree is being checked.

## Publishing

<!-- index: remote; bookmark; provider first -->

Each repository keeps two remotes: `aliyun` as the delivery remote and `laycat` as a second mirror; `origin` is reserved and left unconfigured. The published bookmark is the `branch` recorded in `workspace.json`, currently `main`. Jujutsu does not derive a push remote from tracking, so the remote and the bookmark are always named explicitly: `jj bookmark set main -r @-` followed by `jj git push --remote aliyun -b main`. Publishing only fast-forwards; when the remote has commits the local branch does not, the unpublished commits are rebased onto the remote and the checks are repeated rather than force-pushing. A provider is committed and published before a consumer that depends on its interface, and consumer messages quote published provider commit identifiers rather than local ones. When authentication or connectivity prevents a push, the commits stay local and the delivery failure is reported; an unpushed commit is never claimed to be backed up remotely.

## Integrated checkpoints

<!-- index: checkpoint; recorded revision -->

At an integrated checkpoint, every child repository's published `main` commit is recorded in `workspace.json` together with the checks that were run, which is what makes a combination of revisions reproducible. `python3 scripts/workspace.py status` compares the repository bookmarks against those recorded revisions — not the working copies — so a recorded checkpoint always names published commits, never an unsealed `@`. An integrated run of the workspace checks is performed on a quiet tree, after editing and committing are complete: a source change during measurement marks the run unverified.

## History and recovery

<!-- index: bisection; operation log; undo -->

Two shapes of recovery cover most needs. To find where a regression entered, `jj log -p <path>` shows one file's history, `jj file annotate <path>` blames a line, and `jj bisect run --range <good>..<bad> -- <command>` bisects a range of commits; bisection edits the working copy, so it runs in a separate workspace, and exit status 125 skips a revision that cannot be tested rather than marking it bad. To undo a mistake, `jj undo` reverses the last operation, and `jj op log` with `jj op restore <operation>` returns the repository to an earlier state; `jj evolog -p -r <rev>` shows how one change itself was rewritten, which is different from a file's history.

## The manual and the changelog ride with the code

<!-- index: documentation delivery; changelog -->

A change to a public interface is delivered together with its documentation: the affected manual chapters are updated in both languages, the book gate runs as part of the package checks, and a user-visible change is recorded in the changelog following Keep a Changelog, under a release heading or `Unreleased`. When a version header changes, a manual passage that names the package and version is updated to match, because the book gate checks that span against the entry file. This is the rule that keeps the manual a description of the current code instead of a snapshot of an earlier one.
