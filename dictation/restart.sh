#!/bin/bash

pkill -9 -f "voice_input.py" || true
"$(dirname "$0")"/venv/bin/python voice_input.py --model large-v3
