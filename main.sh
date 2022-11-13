#!/usr/bin/env bash

podman image prune -a -f
podman build -t "bd-compare" .

ENCODERS=("x265" "aomenc")
VIDEOS=("bbb_shorter.mkv")

for ENCODER in "${ENCODERS[@]}"; do
    for VIDEO in "${VIDEOS[@]}"; do
        podman run --rm -v "${HOME}/Videos:/videos:z" -v "$(pwd):/app:z" bd-compare scripts/run.sh -i "/videos/${VIDEO}" --enc "$ENCODER" --output /videos --bd "steps/quality_${ENCODER}" --preset "steps/preset_${ENCODER}" --resume -e 2 --decode
    done
done
