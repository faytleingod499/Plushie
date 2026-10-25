#!/bin/bash
# Makes the two zips from package/ (rebuild package/Plushie/Plushie.pck first with pack.gd, see the README):
#   out/Plushie-mod.zip         the Plushie folder to drop into GDWeave/mods
#   out/Plushie-<version>.zip   the Thunderstore upload
set -e
cd "$(dirname "$0")"
mkdir -p out
V=$(python3 -c "import json;print(json.load(open('thunderstore/manifest.json'))['version_number'])")
rm -f out/Plushie-mod.zip out/Plushie-$V.zip
(cd package && zip -qr ../out/Plushie-mod.zip Plushie)
T=$(mktemp -d)
cp thunderstore/manifest.json thunderstore/README.md thunderstore/CHANGELOG.md thunderstore/icon.png $T/
cp LICENSE $T/
mkdir -p $T/GDWeave/mods/Plushie
cp package/Plushie/manifest.json package/Plushie/Plushie.pck $T/GDWeave/mods/Plushie/
(cd $T && zip -qr - .) > out/Plushie-$V.zip
rm -rf $T
echo "out/Plushie-mod.zip"
echo "out/Plushie-$V.zip"
