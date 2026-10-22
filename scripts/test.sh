#!/bin/sh
set -eu
cd "$(dirname "$0")/.."
task_tmp="$(mktemp -d "${TMPDIR:-/tmp}/deskpet-tests.XXXXXX")"
trap 'rm -rf "$task_tmp"' EXIT HUP INT TERM
swiftc DeskPet/Gaze.swift DeskPet/PetBehavior.swift DeskPet/ConversationCore.swift DeskPet/WakeAudioGain.swift DeskPet/DuplexGate.swift DeskPet/CaptureCadence.swift \
    Tests/main.swift -o "$task_tmp/deskpet-tests"
"$task_tmp/deskpet-tests"
