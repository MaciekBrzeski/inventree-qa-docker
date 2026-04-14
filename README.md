# InvenTree QA Docker — portable seeded stack

A ready-to-run [InvenTree](https://inventree.org) Docker Compose stack, pre-seeded
with a Postgres dump + media files. Drop it on any machine with Docker, run one
script, and you have an InvenTree instance populated with the same QA test data
used by the [QAHackaton](https://github.com/) automation suite.

Built for the QAHub AI Hackathon 2026 submission so graders can reproduce the
exact parts, categories, BOMs, price breaks, test templates, parameters and
related-parts state the automated tests expect.

## Stack

- **inventree-server** — gunicorn, `inventree/inventree:stable`
- **inventree-worker** — django-q background worker
- **inventree-db** — Postgres 17
- **inventree-cache** — Redis 7
- **inventree-proxy** — Caddy (reverse proxy + static/media file server)

## Prerequisites

- Docker Engine 24+ and Docker Compose v2 (`docker compose version`)
- ~2 GB free disk for the container images
- Port 80 (and optionally 443) free on the host, or edit `.env` to change
- If your user is not in the `docker` group, the setup script will auto-`sudo`

## Quick start

```bash
git clone https://github.com/MaciekBrzeski/inventree-qa-docker.git
cd inventree-qa-docker
./setup.sh
```

The script:

1. Copies `.env.example` → `.env` if missing.
2. Starts `inventree-db`, waits for Postgres to be ready.
3. Restores `seed/inventree-seed.sql.gz` into the `inventree` database (only
   if the `part_part` table is absent — re-runs are idempotent).
4. Starts the rest of the stack.
5. Restores `seed/inventree-media.tar.gz` into
   `/home/inventree/data/media` inside the server container (only once; marker
   file `seed/.media-restored` skips it on re-runs).

First boot takes roughly a minute while migrations apply. Once done, open:

- **Web UI**: <http://inventree.localhost>
- **API**: <http://inventree.localhost/api/>
- **Admin login**: `admin` / `changeme`

> `inventree.localhost` resolves to 127.0.0.1 on most Linux distros and modern
> browsers. If yours doesn't, add `127.0.0.1 inventree.localhost` to
> `/etc/hosts` or change `INVENTREE_SITE_URL` in `.env` to `http://localhost`.

## Getting an API token

```bash
curl -u admin:changeme http://inventree.localhost/api/user/token/
# → {"token": "inv-..."}
```

Then:

```bash
curl -H 'Authorization: Token inv-...' http://inventree.localhost/api/part/
```

## Files

| File | Purpose |
|---|---|
| `docker-compose.yml` | Service definitions (upstream InvenTree compose recipe) |
| `Caddyfile` | Reverse proxy + static/media file server config |
| `.env.example` | Non-secret defaults — credentials are throwaway test creds |
| `setup.sh` | Bootstrap + seed restore script |
| `seed/inventree-seed.sql.gz` | Postgres dump of the `inventree` database |
| `seed/inventree-media.tar.gz` | Media files from `/home/inventree/data/media` |
| `seed/inventree-static.tar.gz` | Static files (web frontend, admin, DRF) from `/home/inventree/data/static` — ships the pre-built SPA so a fresh clone does not need to download and build it |
| `.gitignore` | Excludes `.env`, `inventree-data/`, restore markers |

## What's in the seed?

The seed dump ships the QA-ROOT category and all child entities created by the
QAHackaton automation suite during its most recent full run:

- Root + sub-categories
- ~50 parts (assembly, component, purchaseable, salable variants)
- BOMs with substitutes and validation history
- Internal + sale price breaks
- Test templates with required/optional flags
- Part parameters + parameter templates
- Related-parts links
- Attachments metadata (referenced files live in the media tarball)

An `admin` superuser with password `changeme` is pre-created — these are
throwaway QA credentials, not production secrets.

## Reset

```bash
./setup.sh           # idempotent — skips seed if DB already populated
```

Full wipe:

```bash
docker compose down -v
sudo rm -rf inventree-data seed/.media-restored
./setup.sh
```

## Stop

```bash
docker compose down
```

Data persists in `./inventree-data/` between restarts.

## Refreshing the seed

To capture a new dump from a running stack:

```bash
docker exec inventree-db pg_dump -U pguser -d inventree | gzip > seed/inventree-seed.sql.gz
docker exec inventree-server tar czf - -C /home/inventree/data media  > seed/inventree-media.tar.gz
docker exec inventree-server tar czf - -C /home/inventree/data static > seed/inventree-static.tar.gz
```

Commit and push. Others pulling the repo will get the refreshed state on
their next `setup.sh` run (after a full wipe, or by manually dropping the DB).

## License

Seed data and scripts: MIT. InvenTree itself is MIT-licensed upstream — see
<https://github.com/inventree/InvenTree>.
