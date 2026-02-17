#!/bin/bash
set -euo pipefail

# Auto-load .env or vars.env if present
ENV_FILE="vars.env"

if [ -f "$ENV_FILE" ]; then
  echo "Loading environment from $ENV_FILE"
  set -a
  source "$ENV_FILE"
  set +a
fi

sudo podman run \
  --rm \
  -it \
  --privileged \
  --pull=newer \
  --security-opt label=type:unconfined_t \
  -v "$(pwd)/output:/output" \
  -v /var/lib/containers/storage:/var/lib/containers/storage \
  -v "$(pwd)/config.toml:/config.toml" \
  registry.redhat.io/rhel9/bootc-image-builder:latest \
  build \
  --type iso \
  "${IMAGE_REF}"