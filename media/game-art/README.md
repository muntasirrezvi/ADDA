# 3D game art

The game pictures in `app/assets/games/` are rendered with Blender (Cycles) from these scripts.

    pip install bpy
    OUT=out python3 assets.py            # everything
    OUT=out python3 assets.py -- dice    # one group

Then convert the PNGs to WebP (quality 86) into `app/assets/games/`.
