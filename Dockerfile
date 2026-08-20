# syntax=docker/dockerfile:1.7

FROM debian:12-slim AS rclonebrowser-builder

ARG RCLONEBROWSER_REF=45bf7411839b0919c488a3e3a0a5272b50c9fc7b

RUN apt-get update \
    && apt-get install -y --no-install-recommends \
        build-essential \
        ca-certificates \
        cmake \
        git \
        patch \
        qtbase5-dev \
    && rm -rf /var/lib/apt/lists/*

WORKDIR /src
RUN git clone https://github.com/kapitainsky/RcloneBrowser.git . \
    && git checkout --detach "${RCLONEBROWSER_REF}"

COPY patches/rclonebrowser-modern-rclone.patch /tmp/rclonebrowser-modern-rclone.patch
RUN patch -p1 < /tmp/rclonebrowser-modern-rclone.patch \
    && cmake -S . -B /build -DCMAKE_BUILD_TYPE=Release -DCMAKE_CXX_FLAGS="-Wno-error=deprecated-declarations" \
    && cmake --build /build --parallel "$(nproc)"

FROM jlesage/baseimage-gui:debian-12-v4

ARG TARGETARCH
ARG IMAGE_VERSION=unknown
ARG RCLONE_VERSION=current
ARG BUILD_DATE=unknown

RUN add-pkg \
        ca-certificates \
        curl \
        dbus-x11 \
        fuse3 \
        libqt5core5a \
        libqt5gui5 \
        libqt5network5 \
        libqt5widgets5 \
        xterm \
        unzip \
    && case "${TARGETARCH}" in \
        amd64) RCLONE_ARCH=amd64 ;; \
        arm64) RCLONE_ARCH=arm64 ;; \
        *) echo "Unsupported TARGETARCH: ${TARGETARCH}" >&2; exit 1 ;; \
       esac \
    && if [ "${RCLONE_VERSION}" = "current" ]; then \
         RCLONE_URL="https://downloads.rclone.org/rclone-current-linux-${RCLONE_ARCH}.zip"; \
       else \
         RCLONE_URL="https://github.com/rclone/rclone/releases/download/v${RCLONE_VERSION}/rclone-v${RCLONE_VERSION}-linux-${RCLONE_ARCH}.zip"; \
       fi \
    && curl --fail --show-error --location --retry 3 --output /tmp/rclone.zip "${RCLONE_URL}" \
    && mkdir -p /tmp/rclone \
    && unzip -q /tmp/rclone.zip -d /tmp/rclone \
    && RCLONE_BIN="$(find /tmp/rclone -type f -name rclone -print -quit)" \
    && test -n "${RCLONE_BIN}" \
    && install -m 0755 "${RCLONE_BIN}" /usr/bin/rclone \
    && rm -rf /tmp/rclone /tmp/rclone.zip

COPY --from=rclonebrowser-builder /build/build/rclone-browser /usr/bin/rclone-browser
COPY rootfs/ /

RUN chmod +x /startapp.sh \
    && set-cont-env APP_NAME "RcloneBrowser" \
    && set-cont-env APP_VERSION "${IMAGE_VERSION} (rclone ${RCLONE_VERSION})" \
    && printf '<Title>Rclone Browser</Title>\n<Type>normal</Type>\n' > /etc/openbox/main-window-selection.xml

ENV RCLONE_CONFIG=/config/rclone/rclone.conf \
    QT_X11_NO_MITSHM=1

VOLUME ["/config", "/media"]

LABEL org.opencontainers.image.title="RcloneBrowser" \
      org.opencontainers.image.description="RcloneBrowser GUI container with current rclone and web/VNC access" \
      org.opencontainers.image.source="https://github.com/Mega-Bits/rclonebrowser-docker" \
      org.opencontainers.image.version="${IMAGE_VERSION}" \
      org.opencontainers.image.created="${BUILD_DATE}"
