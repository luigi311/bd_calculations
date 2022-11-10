podman build -t "bd-compare" .
podman image prune -a -f
podman run --rm -v "${HOME}/Videos:/videos:z" bd-compare scripts/run.sh -i /videos/source.mkv --enc aomenc --output /videos --bd steps/steps_aomenc 
