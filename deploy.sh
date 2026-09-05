#!/bin/bash
set -euo pipefail

# ====== Configuration (edit these) ======
DOCKERHUB_USER="roshini31"
IMAGE_BASE="devops-build"
CONTAINER_NAME="devops-build-app"

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null || echo "master")

if [ "$BRANCH" = "master" ] || [ "$BRANCH" = "main" ]; then
  TARGET_REPO="prod"
else
  TARGET_REPO="dev"
fi

IMAGE="${DOCKERHUB_USER}/${IMAGE_BASE}-${TARGET_REPO}:latest"

echo ">>> Pulling ${IMAGE}"
docker pull "${IMAGE}"

echo ">>> Removing old container (if any)"
docker stop "${CONTAINER_NAME}" 2>/dev/null || true
docker rm "${CONTAINER_NAME}" 2>/dev/null || true

echo ">>> Starting new container on port 80"
docker run -d \
  --name "${CONTAINER_NAME}" \
  -p 80:80 \
  --restart unless-stopped \
  "${IMAGE}"

echo ">>> Deployment complete."
docker ps --filter "name=${CONTAINER_NAME}"
