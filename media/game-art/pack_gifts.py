"""Packs rendered gift art into the app: icons -> assets/gifts/<id>.webp, animations -> anim_<id>.webp.

    python3 pack_gifts.py <render dir> <anim dir> <app assets/gifts dir>
"""
import glob, os, sys
from PIL import Image

src, anim_dir, dst = sys.argv[1:4]
os.makedirs(dst, exist_ok=True)

for f in sorted(glob.glob(os.path.join(src, 'gift_*.png'))):
    name = os.path.basename(f)[5:-4]
    im = Image.open(f).convert('RGBA')
    bb = im.getbbox()
    if bb:
        im = im.crop(bb)
    w, h = im.size
    side = max(w, h) + 8
    sq = Image.new('RGBA', (side, side))
    sq.paste(im, ((side - w) // 2, (side - h) // 2))
    sq = sq.resize((192, 192), Image.LANCZOS)
    sq.save(os.path.join(dst, f'{name}.webp'), 'WEBP', quality=88, method=6)
    print('icon', name)

for d in sorted(glob.glob(os.path.join(anim_dir, '*'))):
    if not os.path.isdir(d):
        continue
    name = os.path.basename(d)
    frames = [Image.open(f).convert('RGBA') for f in sorted(glob.glob(os.path.join(d, '*.png')))]
    if not frames:
        continue
    # crop to the area any frame uses, so the object fills the animation
    box = None
    for fr in frames:
        bb = fr.getbbox()
        if bb:
            box = bb if box is None else (min(box[0], bb[0]), min(box[1], bb[1]), max(box[2], bb[2]), max(box[3], bb[3]))
    if box:
        w, h = box[2] - box[0], box[3] - box[1]
        side = max(w, h)
        cx, cy = (box[0] + box[2]) // 2, (box[1] + box[3]) // 2
        crop = (cx - side // 2, cy - side // 2, cx - side // 2 + side, cy - side // 2 + side)
        frames = [fr.crop(crop) for fr in frames]
    out_size = 360
    frames = [fr.resize((out_size, out_size), Image.LANCZOS) for fr in frames]
    # hold the last frame a little longer
    durations = [62] * (len(frames) - 1) + [900]
    out = os.path.join(dst, f'anim_{name}.webp')
    frames[0].save(out, 'WEBP', save_all=True, append_images=frames[1:], duration=durations, loop=1, quality=72, method=4, minimize_size=True)
    print('anim', name, len(frames), os.path.getsize(out) // 1024, 'KB')
