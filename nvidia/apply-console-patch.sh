#!/bin/bash
# Re-apply the Surface Studio console-offset patch to every installed nvidia DKMS source tree.
# Runs from a pacman hook before 70-dkms-*.hook rebuilds the modules.
P=/etc/studio-nvidia/surface-studio-console-offset.patch
for src in /usr/src/nvidia-*/; do
    [ -f "$src/kernel-open/nvidia/nv.c" ] || continue
    if patch -d "$src" -p1 -R -s -f --dry-run < "$P" >/dev/null; then
        echo "studio-nvidia: console patch already in $src"
    elif patch -d "$src" -p1 -s -f --dry-run < "$P" >/dev/null; then
        patch -d "$src" -p1 -s -f < "$P" && echo "studio-nvidia: console patch applied to $src"
    else
        echo "studio-nvidia: WARNING console patch does not apply to $src - driver will be STOCK (panel corrupts under CUDA)" >&2
    fi
done
