# Working in the yolo-agent lab container

You are running inside an air-gapped lab container. Read this before acting.

## Environment

- **No internet.** Only the lab network exists: the model server (SEC09,
  `192.168.1.101:8000`) and Gitea (`192.168.1.27:3000`). `pip install`,
  `npm install`, `apt-get` and downloads from the internet fail; do not try
  them and do not retry them. Use what is installed (`yolo tools`, `pip list`).
- **Your files** are in `/workspace`. That is the person's folder: put code,
  notes and results there. Everything outside `/workspace` and the home
  directory is replaced when the container is upgraded.
- **Git** is configured with a stored Gitea credential: clone, commit and push
  work without prompts. Open pull requests with `yolo-gitea pr-create`
  (see the `yolo-gitea` skill) instead of pushing to `main`.
- **Commands run without confirmation prompts.** Be careful with anything
  destructive: never delete or rewrite files outside the task, never
  force-push, never rewrite published history.
- **Skills**: only the skills the person enabled are available. `yolo skills`
  lists the library.

## How to work

- Read the existing code before changing it, and follow its style.
- Prefer small, verifiable steps. Build and run the tests after a change.
- When you finish, say what changed, what you checked, and what you did not.
