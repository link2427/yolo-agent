---
name: yolo-gitea
description: Clone, push, open pull requests, comment and review on the lab Gitea server (192.168.1.27:3000). Use whenever work should be saved to git, a PR opened, or an issue or PR read or commented on.
---

# Gitea in the lab

Git is already configured: identity, and a stored credential for the Gitea
token. `git clone`, `git push` and `git pull` work without prompts.

- Web and API: `http://192.168.1.27:3000`, API under `/api/v1`
- The helper `yolo-gitea` wraps the API with the stored token.

## Common tasks

```bash
# clone
git clone http://192.168.1.27:3000/<owner>/<repo>.git

# new branch, commit, push
git switch -c fix/short-name
git add -A && git commit -m "Describe the change"
git push -u origin HEAD

# open a pull request (owner/repo, head branch, base branch, title, body file)
yolo-gitea pr-create <owner>/<repo> fix/short-name main "Title" body.md

# read a pull request and its diff
yolo-gitea pr-view <owner>/<repo> <number>
yolo-gitea pr-diff <owner>/<repo> <number>

# comment on a PR or issue
yolo-gitea comment <owner>/<repo> <number> comment.md

# anything else: raw API call
yolo-gitea api GET /repos/<owner>/<repo>/pulls?state=open
```

## Rules

- Never print, echo or commit the token. It lives in `~/.git-credentials`
  and `~/.yolo/secrets.env`.
- Commit messages: short imperative subject, then a body explaining why.
- Open a pull request rather than pushing to `main`, unless told otherwise.
