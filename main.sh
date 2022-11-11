#!/usr/bin/env bash

podman build -t "bd-compare" .
podman image prune -a -f

ENCODERS=("x265" "rav1e" "aomenc")
VIDEOS=("bbb.mkv")

for ENCODER in "${ENCODERS[@]}"; do
    for VIDEO in "${VIDEOS[@]}"; do
        podman run --rm -v "${HOME}/Videos:/videos:z" bd-compare scripts/run.sh -i "/videos/${VIDEO}" --enc "$ENCODER" --output /videos --bd "steps/steps_$ENCODER" --resume
    done
done