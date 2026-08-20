# rclonebrowser-docker

RcloneBrowser in a maintained Docker image with web/VNC access. The image builds the upstream `kapitainsky/RcloneBrowser` source with compatibility fixes for current rclone output, so the Jobs view shows transferred size, total size, bandwidth, ETA, transfer counts and per-file progress again.

## Image

```text
ghcr.io/mega-bits/rclonebrowser-docker:latest
```

The GitHub Actions workflow validates the image before publishing it on every push to `master`, once every 24 hours, and on manual dispatch. Every build publishes these tags:

- `latest`
- the repository version from `VERSION` (for example `v5.0.0`)
- `<repository-version>-rclone-<version>` for an exact app/rclone combination
- `rclone-<version>` for the rclone release included in the build
- `sha-<commit>` for source traceability

The scheduled build resolves the newest stable rclone release before building, so `latest` follows new rclone releases even when this repository itself did not change.

## Run

The included `docker-compose.yaml` binds the web and VNC ports to localhost by default and enables `no-new-privileges`:

```bash
docker compose up -d
```

Open `http://127.0.0.1:5800` on the Docker host. Port `5900` is optional and only needed for a native VNC client.

For direct `docker run`, use the same hardened network defaults:

```bash
docker run -d \
  --name rclonebrowser \
  --restart unless-stopped \
  --security-opt no-new-privileges:true \
  -p 127.0.0.1:5800:5800 \
  -p 127.0.0.1:5900:5900 \
  -e USER_ID=1000 \
  -e GROUP_ID=1000 \
  -e TZ=Europe/Amsterdam \
  -v ./config:/config \
  -v ./media:/media \
  ghcr.io/mega-bits/rclonebrowser-docker:latest
```

If remote access is required, prefer a VPN, SSH tunnel, or an authenticated TLS reverse proxy rather than changing the bindings to `0.0.0.0`.

## Health monitoring

The image includes a Docker healthcheck. A container is considered healthy only when both conditions are true:

- the exact `rclone-browser` process is running;
- the local web UI on port `5800` accepts a connection over HTTP or HTTPS.

The web probe intentionally does not require a `2xx` status code, because authentication can legitimately return another HTTP status while the service itself is healthy. HTTPS is probed with certificate verification disabled only against `127.0.0.1`, so a locally generated certificate does not create false failures.

The healthcheck is read-only and does not invoke rclone operations, access configured remotes, or modify `/config` or `/media`.

Check the current state with:

```bash
docker inspect --format '{{.State.Health.Status}}' rclonebrowser
```

The image uses a 45-second startup grace period, a 30-second interval, a 6-second timeout, and marks the container unhealthy after three consecutive failed checks.

## Persistent data

- `/config` stores RcloneBrowser settings and the rclone configuration.
- `/media` is the default path for files you want to expose to RcloneBrowser.
- rclone uses `/config/rclone/rclone.conf` by default through `RCLONE_CONFIG`.

## Read-only local data mode

If you only need to browse or copy data *from* local storage, use the included read-only compose overlay:

```bash
docker compose -f docker-compose.yaml -f docker-compose.readonly.yaml up -d
```

It changes the local media mount to:

```yaml
volumes:
  - ./config:/config
  - ./media:/media:ro
```

This prevents the container from modifying files under `/media`. It does not make configured cloud/remotes read-only; their permissions are controlled by the credentials and provider configuration in `rclone.conf`. It also prevents copying or moving files *to* `/media`, so use the normal compose file when local writes are intentionally required.

## Security

The browser and VNC interfaces provide access to configured remotes and mounted files. The default compose file therefore listens only on `127.0.0.1` and uses Docker's `no-new-privileges` option. Do not expose ports `5800` or `5900` directly to an untrusted network.

Treat `/config/rclone/rclone.conf` as a secret because it can contain credentials or access tokens. Never commit `/config`, exported rclone configuration, passwords, or tokens to this repository.

Only grant extra container privileges when required. In particular, `SYS_ADMIN` and `/dev/fuse` are intentionally absent from the default configuration because they materially increase container privileges.

Keep the image updated so scheduled rebuilds can pick up current base-image and rclone fixes.

## Data loss and destructive operations

RcloneBrowser can invoke rclone operations that delete, move, overwrite, or synchronize files on both local and remote storage. A mistaken source, destination, or sync direction can cause irreversible data loss. No container image can make an intentionally destructive rclone command universally safe.

Before using destructive operations:

- test with disposable data or a read-only remote first;
- use rclone dry-run functionality where the selected operation supports it;
- verify the source, destination, filters, and sync direction;
- keep independent backups or snapshots for important data;
- avoid granting write access to remotes that do not need it.

The container does not add a safety layer around rclone commands; RcloneBrowser and rclone have the same access that you grant through mounted volumes and configured remotes.

## Rclone mounts

If you use `rclone mount`, the container needs access to FUSE. Add this only when you actually need mounts:

```yaml
devices:
  - /dev/fuse:/dev/fuse
cap_add:
  - SYS_ADMIN
```

`SYS_ADMIN` is a broad capability, so it is intentionally not enabled in the default compose file.

## Transfer statistics fix

The original RcloneBrowser parser expected older rclone console formats. Newer rclone versions changed the `Transferred` and per-file progress lines, which caused the GUI fields for bandwidth, size and remaining time to stay empty. This image applies a small source patch during the build that accepts current output and also displays per-file bandwidth and ETA directly in each progress bar.

## Build locally

```bash
docker buildx build --load --platform linux/amd64 -t rclonebrowser:local .
```

To pin rclone explicitly:

```bash
docker buildx build --load \
  --build-arg RCLONE_VERSION=1.75.0 \
  -t rclonebrowser:local .
```

`RCLONE_VERSION=current` uses rclone's official current-download alias. A numeric version such as `1.75.0` is downloaded from the matching versioned GitHub release asset. The build executes `rclone version` and rejects a numeric release if the installed binary does not report the requested version.

## Testing

Before a multi-architecture image is published, GitHub Actions now builds a `linux/amd64` test image and performs runtime checks inside the resulting container. The disposable data-integrity suite in `tests/data-integrity.sh` exercises local rclone operations only inside a newly created `/tmp` directory and verifies file trees with SHA-256 manifests.

The CI currently checks:

- the `rclone`, `rclone-browser`, startup, and healthcheck binaries exist and are executable;
- the installed rclone binary starts and reports its version;
- local copy preserves the complete test fixture;
- overwriting an existing destination produces the same SHA-256 file tree as the source;
- move transfers the fixture and only removes the disposable source after the move;
- sync produces the exact source file tree and removes only the deliberately created obsolete fixture file;
- filenames with spaces, a UTF-8 filename, an empty file, nested paths, and a deterministic binary file;
- the normal container starts with `no-new-privileges` and reaches Docker's `healthy` state through the same healthcheck shipped in the image;
- the final publish build still targets both `linux/amd64` and `linux/arm64`.

These checks cover the local disposable fixtures above. They do **not** certify provider-specific remotes, FUSE mounts, failure recovery, concurrent changes, or arbitrary destructive commands as data-loss safe. Important data should still have independent backups or snapshots.

## Architecture

The GHCR workflow publishes multi-architecture images for `linux/amd64` and `linux/arm64`.
