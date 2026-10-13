#!/bin/bash
# Generates the alarm sounds and converts them to CAF in build/resources/,
# the folder both build.sh and the Xcode project (project.yml) copy into the app.
# Needs macOS (afconvert); the WAVs are cached between runs.
set -euo pipefail

cd "$(dirname "$0")/.."
SOUND_DIR="build/sounds"
OUT_DIR="build/resources"

# Sounds are synthesized from scratch (license-free) and cached between builds.
if [ ! -f "${SOUND_DIR}/.stamp" ] || [ scripts/generate_sounds.py -nt "${SOUND_DIR}/.stamp" ]; then
    echo "Generating sounds..."
    rm -rf "${SOUND_DIR}"
    python3 scripts/generate_sounds.py --out "${SOUND_DIR}"
    touch "${SOUND_DIR}/.stamp"
fi

echo "Converting sounds..."
rm -rf "${OUT_DIR}"
mkdir -p "${OUT_DIR}"
for wav in "${SOUND_DIR}"/*.wav; do
    afconvert -f caff -d ima4 "${wav}" "${OUT_DIR}/$(basename "${wav}" .wav).caf"
done
cp "${SOUND_DIR}/Sounds.json" "${OUT_DIR}/Sounds.json"
