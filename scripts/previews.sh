#!/bin/bash
# Makes the gallery's preview pictures (assets/efectos/*.jpg) by running the model's photo
# (assets/modelo/persona.png, and the same room empty in fondo.png) through the app's own compositor.
# Run it again after changing how an effect looks.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build assets/efectos
swiftc -O -o build/previews tools/previews/main.swift \
  Sources/kawaru/{Compositor,Trunk,Smoke,Card,Overlays,Wording}.swift
build/previews assets/modelo/persona.png assets/modelo/fondo.png assets/efectos
