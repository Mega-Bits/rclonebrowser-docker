# rclonebrowser-docker

RcloneBrowser in a maintained Docker image with web/VNC access. The image builds the upstream `kapitainsky/RcloneBrowser` source with compatibility fixes for current rclone output, so the Jobs view shows transferred size, total size, bandwidth, ETA, transfer counts and per-file progress again.

## Image

```text
ghcr.io/mega-bits/rclonebrowser-docker:latest
```

The GitHub Actions workflow validates pull requests, then rebuilds and publishes the image on every push to `master`, once every 24 hours, and on manual dispatch. Every build publishes these tags:

- `latest`
- the repository version from `VERSION` (for example `v5.0.0`)
- `<repository-version>-rclone-<version>` for an exact app/rclone combination
- `rclone-<version>` for the rclone release included in the build
- `sha-<commit>` for source traceability

The scheduled build resolves the newest stable rclone release before building, so `latest` follows new rclone releases even when this repository itself did not change.

## Run

```bash
docker run -d \
  --name rclonebrowser \
  --restart unless-stopped \
  -p 5800:5800 \
  -p 5900:5900 \
  -e USER_ID=1000 \
  -e GROUP_ID=1000 \
  -e TZ=Europe/Amsterdam \
  -v ./config:/config \
  -v ./media:/media \
  ghcr.io/mega-bits/rclonebrowser-docker:latest
```

Open `http://<docker-host>:5800` for the browser UI. Port `5900` is optional and only needed for a native VNC client.

A matching `docker-compose.yaml` is included in the repository.

## Persistent data

- `/config` stores RcloneBrowser settings and the rclone configuration.
- `/media` is the default path for files you want to expose to RcloneBrowser.
- rclone uses `/config/rclone/rclone.conf` by default through `RCLONE_CONFIG`.

## Security

The browser and VNC interfaces provide access to configured remotes and mounted files. Do not expose ports `5800` or `5900` directly to an untrusted network. Prefer a trusted LAN, VPN, or a reverse proxy with TLS and authentication. The jlesage base image also supports its built-in web authentication and secure-connection options.

Treat `/config/rclone/rclone.conf` as a secret because it can contain credentials or access tokens. Never commit `/config`, exported rclone configuration, passwords, or tokens to this repository.

Only grant extra container privileges when required. In particular, `SYS_ADMIN` and `/dev/fuse` are intentionally absent from the default configuration because they materially increase container privileges.

Keep the image updated so scheduled rebuilds can pick up current base-image and rclone fixes.

## Data loss and destructive operations

RcloneBrowser can invoke rclone operations that delete, move, overwrite, or synchronize files on both local and remote storage. A mistaken source, destination, or sync direction can cause irreversible data loss.

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

`RCLONE_VERSION=current` uses rclone's official current-download alias. A numeric version such as `1.75.0` is downloaded from the matching immutable GitHub release asset.

## Testing

Pull requests against `master` run the same multi-architecture Docker build used for publishing, but with `push: false`. This validates both `linux/amd64` and `linux/arm64` without publishing an image.

Before treating a release as production-ready, verify at minimum:

- the container starts and the browser UI is reachable on port `5800`;
- `/config` persists RcloneBrowser settings and the rclone configuration across restarts;
- a small upload and download work against a disposable test remote;
- transferred size, total size, bandwidth, ETA, transfer counts and per-file progress update in the Jobs view;
- FUSE mounts work only when the optional FUSE privileges are enabled;
- destructive operations are tested only against disposable data first.

Do not interpret a successful image build as proof that a particular remote provider or destructive workflow is safe. Provider-specific behavior should be tested with non-critical data.

## Architecture

The GHCR workflow publishes multi-architecture images for `linux/amd64` and `linux/arm64`.
