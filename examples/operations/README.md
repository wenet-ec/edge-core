# Edge Admin — One-off Operations

Compose files for running Edge Admin tasks as **one-off jobs** — container exits when the task is done. Useful as a Kubernetes Job, a CI step, or a manual operator action before/around a release.

The admin image exposes three commands:

| Command             | What it does                                                                                                                            |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `/start`            | Default. Runs migrate + rotate Cloak key + create Netmaker superadmin + create default cluster (all idempotent), then starts the admin. |
| `/migrate`          | Runs database migrations and exits.                                                                                                     |
| `/rotate_cloak_key` | Re-encrypts every Cloak-encrypted column from an old key to a new one. Idempotent. Exits.                                               |

The compose files in this directory just override `command:` to invoke `/migrate` or `/rotate_cloak_key` instead of the default `/start`:

| File                   | Invokes             |
| ---------------------- | ------------------- |
| `migrate.yml`          | `/migrate`          |
| `rotate_cloak_key.yml` | `/rotate_cloak_key` |

`/start` already runs both on every admin boot, so a single-admin deployment doesn't need anything in this directory. These files are for invoking those steps **separately** — e.g. migrate before rolling out a new image, or rotate keys on a schedule independent of admin restarts.

## Usage

Both files expect a `.env` file in this directory with the same variables your running admin uses (DB connection, `CLOAK_KEY`/`CLOAK_TAG`, etc.). Easiest path:

```bash
ln -s ../standard/.env .env     # or ../lite/.env
```

Then:

```bash
# Run migrations once and exit
docker compose -f migrate.yml run --rm edge_admin_migrate

# Rotate the Cloak key once and exit (requires ROTATE_OLD_* + ROTATE_NEW_* envs)
docker compose -f rotate_cloak_key.yml run --rm edge_admin_rotate_cloak_key
```

`run --rm` is the right invocation — the container is meant to start, do the work, exit, and be cleaned up. `up` would also work but leaves the stopped container around.

## Cloak key rotation specifics

The four `ROTATE_*` env vars must all be set for `rotate_cloak_key.yml` to do anything. If any is missing, the task logs `skip` and exits 0 — that is intentional, since `/start` calls the same task on every boot and we don't want it to fail when there's no rotation in progress.

```env
ROTATE_OLD_CLOAK_KEY=<current key, base64, 32 bytes>
ROTATE_OLD_CLOAK_TAG=AES.GCM.V1
ROTATE_NEW_CLOAK_KEY=<new key, base64, 32 bytes>
ROTATE_NEW_CLOAK_TAG=AES.GCM.V2
```

After the task succeeds, update `CLOAK_KEY`/`CLOAK_TAG` on the running admins to the new key/tag and restart them. The old key can then be retired.

## Why these exist

The regular admin `/start` already runs `migrate` and `rotate_cloak_key` at boot, so a single-admin deployment doesn't need either of these files. They become useful when:

- **You run multiple admins** and want to run migrations exactly once (rather than racing N admins through the migration lock at boot).
- **You deploy on Kubernetes** and want a `Job` or `initContainer` for migrations rather than baking them into the main container's startup.
- **You rotate the Cloak key on a schedule** independent of admin rollouts.
- **You're debugging a migration or rotation** and want to run it in isolation without the rest of the admin starting up.

For everyday self-hosted Compose deployments, the built-in `/start` flow is fine — these are the escape hatches.
