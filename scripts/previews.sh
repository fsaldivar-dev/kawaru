#!/bin/bash
# Makes the gallery's preview pictures (assets/efectos/*.jpg) by running the model's photo
# (assets/modelo/persona.png, and the same room empty in fondo.png) through the app's own compositor.
# Run it again after changing how an effect looks.
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p build assets/efectos
swiftc -O -o build/previews tools/previews/main.swift \
  Sources/kawaru/{Compositor,Trunk,Smoke,Card,Overlays,Wording,Rotulos,Idioma}.swift
# Everyone photographed in the same empty room (fondo.png) takes a turn: one effect each, in order.
people=(assets/modelo/persona.png)
[[ -f assets/modelo/mujer.png ]] && people+=(assets/modelo/mujer.png)
build/previews assets/modelo/fondo.png assets/efectos "${people[@]}"
# The effects that show words, once more in each of the other languages (assets/efectos/<language>/).
for lproj in assets/idiomas/*.lproj; do
  language="$(basename "$lproj" .lproj)"
  [[ "$language" == es || ! -f "$lproj/Localizable.strings" ]] && continue
  mkdir -p "assets/efectos/$language"
  KAWARU_IDIOMA="$PWD/$lproj" build/previews assets/modelo/fondo.png "assets/efectos/$language" "${people[@]}"
done
