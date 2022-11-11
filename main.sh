#!/usr/bin/env bash

podman build -t "bd-compare" .
podman image prune -a -f

ENCODERS=("x265" "aomenc")
VIDEOS=("bbb_short.mkv")

for ENCODER in "${ENCODERS[@]}"; do
    for VIDEO in "${VIDEOS[@]}"; do
        podman run --rm -v "${HOME}/Videos:/videos:z" -v "$(pwd):/app:z" bd-compare scripts/run.sh -i "/videos/${VIDEO}" --enc "$ENCODER" --output /videos --bd "steps/quality_${ENCODER}" --preset "steps/preset_${ENCODER}" --resume
    done
done