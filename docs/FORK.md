# Keeping your station in a private repo

Ealta is **configured, not forked** — for a Pi on your own network, a station profile plus a
gitignored `.env` is the whole story, and you never need this document.

This is for the other case: you want your profile under version control, your own cloud
deploy with CI, and engine updates on tap. Then keep a **private repo that shares the
engine's git history** — the engine at the root, your station committed at
`stations/yourstation/`, and `git pull upstream main` to take updates.

## Not the GitHub fork button

Forks of a public repo **cannot be private** on GitHub, and a station repo holds your
place, your coordinates and your infra values. "Fork" here means only *shared git
history*: clone the engine, keep it as an `upstream` remote, and point `origin` at your own
private repo. `git pull upstream main` then works exactly like a fork, with none of
GitHub's fork semantics.

## 1. Build it

```bash
git clone git@github.com:benwalsh/ealta.git yourstation
cd yourstation
git remote rename origin upstream                 # the engine, from day one
git remote add origin git@github.com:you/yourstation.git
git fetch origin

# THE FOOTGUN: after the rename, a bare `git push` targets the PUBLIC ENGINE.
# Re-point tracking at your fork and make pushes default there — before your first push.
git branch --set-upstream-to=origin/main main
git config remote.pushdefault origin
```

## 2. What's yours

| path | committed? | what |
|---|---|---|
| `stations/yourstation/` | yes | your profile — `make new-station NAME=yourstation` |
| `.env` (repo root) | gitignored | `STATION_PROFILE` **absolute**, pointing at *this* checkout |
| `infrastructure/terraform.tfvars` | gitignored | from `.example` |
| `infrastructure/backend.hcl` | gitignored | from `.example` |
| `dashboard/storage/*.sqlite3` | gitignored | the detections DB lives in-repo safely |

`terraform.tfvars`:

```hcl
station_name      = "yourstation"
domain_name       = "yourstation.example"
github_repository = "you/yourstation"
# db_username / db_name default to "ealta". If you are adopting an EXISTING database,
# pin them to its real names or tofu will plan to rebuild the database.
```

`backend.hcl` — where the state lives:

```hcl
bucket         = "yourstation-tfstate"
region         = "eu-west-1"
dynamodb_table = "yourstation-tflock"
```

## 3. Verify before you touch anything remote

```bash
make setup && make serve        # localhost:4030 — your birds, lore, names, brand

cd infrastructure
tofu init -backend-config=backend.hcl
tofu plan
```

A **new** station: the plan creates everything. **Adopting existing infra**: expect
`No changes.` — anything else, stop and read the diff before proceeding. An empty plan is
the proof that adopting the engine's templates didn't disturb your live state.

## 4. Deploy

In the repo settings (Settings → Secrets and variables → Actions → **Variables**), set the
four the engine's deploy workflow reads:

| variable | value |
|---|---|
| `STATION_NAME` | `yourstation` |
| `AWS_REGION` | your region |
| `DEPLOY_ROLE_ARN` | `tofu output -raw github_deploy_role_arn` |
| `ECR_REPO` | `tofu output -raw ecr_repository_url` |

Push to `main` (or Actions → Deploy → Run workflow) and it builds with your committed
profile.

## 5. Illustrations

The PNGs live on S3, not in git. `bin/sync-illustrations push|pull` moves them between
`$STATION_PROFILE/illustrations` and your bucket; it requires `ILLUSTRATIONS_BUCKET` and
ships **no default**, because a default would sync one station's art into another's bucket.

## Taking engine updates

```bash
git pull upstream main
```

Keep your changes inside `stations/yourstation/` and your gitignored config. That is what
keeps merges clean — edits to engine files are what generate conflicts. If you fix
something that isn't specific to your place, send it upstream instead of carrying it.

## Converting an existing station repo

If you already have a station repo with its own history, tag the old layout first — that
tag is the whole rollback plan:

```bash
git tag pre-fork && git push origin main --tags
```

Rebuild `main` on the engine's history as above, copy your profile and config across, run
the step 3 checks, then `git push origin main --force`. To roll back,
`git push origin pre-fork:main --force` restores the old layout exactly; the infra state is
untouched by the conversion.
