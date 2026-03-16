# ── SUSE BCI — Base Container Image ─────────────────────────────────────────
# registry.suse.com/bci/nodejs:20
#
# SUSE BCI (Base Container Images) are the same trusted, enterprise-grade
# foundation as SUSE Linux Micro — FIPS-ready, OCI-compliant, continuously
# updated, and fully supported by SUSE.
#
# Available BCI Node.js tags:
#   registry.suse.com/bci/nodejs:20      ← Node.js 20 LTS (recommended)
#   registry.suse.com/bci/nodejs:22      ← Node.js 22 LTS
#
# Multi-arch: both linux/amd64 and linux/arm64 are published — the same
# image tag works on your x86 NUC and your Raspberry Pi 5 clusters.
#
# BCI docs: https://registry.suse.com
#           https://opensource.suse.com/bci
# ─────────────────────────────────────────────────────────────────────────────
FROM registry.suse.com/bci/nodejs:20

LABEL org.opencontainers.image.title="geeko-nostromo"
LABEL org.opencontainers.image.description="SUSE Edge cluster info terminal — Geeko-Alien edition"
LABEL org.opencontainers.image.source="https://github.com/suse-edge/geeko-nostromo"
LABEL org.opencontainers.image.vendor="SUSE"
LABEL org.opencontainers.image.base.name="registry.suse.com/bci/nodejs:20"

# All setup runs as root so we have full control over ownership
# before dropping privileges at the end
WORKDIR /app

# Create the non-root user and group with explicit UID/GID 1000
# so it matches the runAsUser: 1000 in the Deployment securityContext.
# Without --uid/--gid, useradd --system picks a UID in the 100-999 range
# which does NOT match what Kubernetes injects, causing EACCES at runtime.
RUN groupadd --gid 1000 geeko && \
    useradd  --uid 1000 --gid geeko --no-create-home --shell /sbin/nologin geeko

# Copy files as root — then chown in the same RUN layer
# Doing COPY + chown in one RUN avoids a separate layer with wrong ownership
COPY app/server.js  /app/server.js
COPY app/index.html /app/index.html

# Set correct ownership — geeko (1000) owns the files.
# 550/440 would work but 755/644 is more defensive: any valid non-root UID
# that Kubernetes might inject can still read the files.
RUN chown -R geeko:geeko /app && \
    chmod 755 /app/server.js && \
    chmod 644 /app/index.html

# Drop to non-root for runtime — geeko owns the files so Node.js can read them
USER geeko

EXPOSE 3000

ENV PORT=3000 \
    NODE_ENV=production

# BCI includes curl — use it instead of wget for the healthcheck
HEALTHCHECK --interval=15s --timeout=5s --start-period=10s --retries=3 \
  CMD curl -sf http://localhost:3000/health || exit 1

CMD ["node", "/app/server.js"]
