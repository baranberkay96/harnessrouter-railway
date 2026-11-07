# HarnessRouter Community Edition on Railway (community template, not affiliated with HarnessRouter).
#
# Upstream's published all-in-one image, pinned by release tag AND index digest, plus one start
# wrapper. No upstream file is changed: the wrapper execs /app/entrypoint.sh as the image would.
# Upgrade: change the tag and digest together (Docker Hub harnessrouter/harnessrouter), redeploy.
ARG HR_IMAGE=docker.io/harnessrouter/harnessrouter:0.38.2@sha256:444e92aab1bce6046e404570376faadc71154f98dbd0210dee379b9488f15b00
FROM ${HR_IMAGE}

# Railway runs podman-init as PID 1, so the image's tini is a child process. As a subreaper it
# still collects orphaned agent subprocesses (and does not print its "not PID 1" warning).
ENV TINI_SUBREAPER=1

# Root-owned and not writable by the product user, like everything else root runs in this image.
COPY railway-entrypoint.sh /usr/local/bin/hr-railway-entrypoint
RUN chmod 0755 /usr/local/bin/hr-railway-entrypoint \
    && bash -n /usr/local/bin/hr-railway-entrypoint \
    && test -x /app/entrypoint.sh \
    && test -x /usr/bin/tini \
    && test -x /usr/local/bin/python3

ENTRYPOINT ["/usr/bin/tini", "--", "/usr/local/bin/hr-railway-entrypoint"]
