#!/bin/bash

# Comprehensive ALSA warning suppression
export ALSA_PCM_CARD=default
export ALSA_PCM_DEVICE=0
export ALSA_MMAP=no
export ALSA_MIXER=no

# Redirect ALSA errors to /dev/null
exec 2> >(grep -v "ALSA lib" >&2)

# Start PulseAudio if needed
if ! pulseaudio --check; then
    pulseaudio --start --exit-idle-time=-1 2>/dev/null
fi

# Execute the command passed to the container
exec "$@"