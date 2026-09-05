#!/bin/bash
set -euo pipefail

# ====== Configuration (edit these) ======
DOCKERHUB_USER="roshini31"
IMAGE_BASE="devops-build"

BRANCH=$(git rev-parse --abbrev-ref HEAD)
COMMIT_TAG=$(git rev-parse --short HEAD)

# dev branch -> *-dev repo | master branch -> *-prod repo
if [ "$BRANCH" = "master" ] || [ "$BRANCH" = "main" ]; then
  TARGET_REPO="prod"
else
  TARGET_REPO="dev"
fi

IMAGE="${DOCKERHUB_USER}/${IMAGE_BASE}-${TARGET_REPO}"

echo ">>> Building image: ${IMAGE}:${COMMIT_TAG}"
docker build -t "${IMAGE}:${COMMIT_TAG}" -t "${IMAGE}:latest" .

echo ">>> Logging in to Docker Hub"
echo "${DOCKERHUB_PASS}" | docker login -u "${DOCKERHUB_USER}" --password-stdin

echo ">>> Pushing ${IMAGE}:${COMMIT_TAG} and :latest"
docker push "${IMAGE}:${COMMIT_TAG}"
docker push "${IMAGE}:latest"

echo ">>> Done. Pushed to ${TARGET_REPO} repo on Docker Hub."
