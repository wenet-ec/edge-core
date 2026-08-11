# Edge Admin — One-off Operations

## Live Admin console

The Admin image also exposes `/console`, which attaches IEx to an already-running
Admin node. It does not start a second Admin container or rerun VPN membership.

For local Compose:

```bash
./bin/run cloud admin:console

# Lite/SQLite deployment:
VARIANT=lite ./bin/run cloud admin:console
```

For a production or production-test container:

```bash
docker exec -it production_edge_admin_a1 /console
```

The console wrapper discovers the current ephemeral Erlang node through the
authenticated `GET /api/v1/admins/me` endpoint, using the Admin container's
`API_KEY` or `MASTER_KEY`, and connects with the configured
`VPN_CLUSTER_COOKIE`. The Admin must be healthy and have completed membership
startup first.

The console runs IEx against the live Admin application. Press `Ctrl+C` twice to
disconnect without stopping the Admin node. Do not call `:init.stop()` from the
console because that can stop the Admin runtime itself.

Compose files for running Edge Admin tasks as **one-off jobs** — container exits when the task is done. Useful as a Kubernetes Job, a CI step, or a manual operator action before/around a release.

The admin image exposes three commands:

| Command             | What it does                                                                                                                            |
| ------------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| `/start`            | Default. Runs migrate + rotate encryption key + bootstrap Edge VPN admin + create default cluster (all idempotent), then starts the admin. |
| `/migrate`          | Runs database migrations and exits.                                                                                                     |
| `/rotate_encryption_key` | Re-encrypts every encrypted column from an old key to a new one. Idempotent. Exits.                                             |

The compose files in this directory just override `command:` to invoke `/migrate` or `/rotate_encryption_key` instead of the default `/start`:

| File                   | Invokes             |
| ---------------------- | ------------------- |
| `migrate.yml`          | `/migrate`          |
| `rotate_encryption_key.yml` | `/rotate_encryption_key` |

`/start` already runs both on every admin boot, so a single-admin deployment doesn't need anything in this directory. These files are for invoking those steps **separately** — e.g. migrate before rolling out a new image, or rotate keys on a schedule independent of admin restarts.

## Usage

Both files expect a `.env` file in this directory with the same variables your running admin uses (DB connection, `ENCRYPTION_KEY`/`ENCRYPTION_TAG`, etc.). Easiest path:

```bash
ln -s ../standard/.env .env     # or ../lite/.env
```

Then:

```bash
# Run migrations once and exit
docker compose -f migrate.yml run --rm edge_admin_migrate

# Rotate the encryption key once and exit (requires ROTATE_OLD_* + ROTATE_NEW_* envs)
docker compose -f rotate_encryption_key.yml run --rm edge_admin_rotate_encryption_key
```

`run --rm` is the right invocation — the container is meant to start, do the work, exit, and be cleaned up. `up` would also work but leaves the stopped container around.

## Encryption key rotation specifics

The four `ROTATE_*` env vars must all be set for `rotate_encryption_key.yml` to do anything. If any is missing, the task logs `skip` and exits 0 — that is intentional, since `/start` calls the same task on every boot and we don't want it to fail when there's no rotation in progress.

```env
ROTATE_OLD_ENCRYPTION_KEY=<current key, base64, 32 bytes>
ROTATE_OLD_ENCRYPTION_TAG=AES.GCM.V1
ROTATE_NEW_ENCRYPTION_KEY=<new key, base64, 32 bytes>
ROTATE_NEW_ENCRYPTION_TAG=AES.GCM.V2
```

After the task succeeds, update `ENCRYPTION_KEY`/`ENCRYPTION_TAG` on the running admins to the new key/tag and restart them. The old key can then be retired.

## Why these exist

The regular admin `/start` already runs `migrate` and `rotate_encryption_key` at boot, so a single-admin deployment doesn't need either of these files. They become useful when:

- **You run multiple admins** and want to run migrations exactly once (rather than racing N admins through the migration lock at boot).
- **You deploy on Kubernetes** and want a `Job` or `initContainer` for migrations rather than baking them into the main container's startup.
- **You rotate the encryption key on a schedule** independent of admin rollouts.
- **You're debugging a migration or rotation** and want to run it in isolation without the rest of the admin starting up.

For everyday self-hosted Compose deployments, the built-in `/start` flow is fine — these are the escape hatches.

## Files in this directory

Browse the actual files on GitHub:

| File | Purpose |
| --- | --- |
| [`migrate.yml`](https://github.com/wenet-ec/edge-core/blob/main/examples/operations/migrate.yml) | Runs `/migrate` — database migrations, then exits |
| [`rotate_encryption_key.yml`](https://github.com/wenet-ec/edge-core/blob/main/examples/operations/rotate_encryption_key.yml) | Runs `/rotate_encryption_key` — re-encrypts encrypted columns to a new key, then exits |

Or browse the whole directory: [`examples/operations/`](https://github.com/wenet-ec/edge-core/tree/main/examples/operations).
