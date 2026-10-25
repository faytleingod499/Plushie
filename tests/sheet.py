#!/usr/bin/env python3
# sheet.py DIR OUT.png  -> contact sheet of DIR/<pose>_<view>.png (rows = poses, columns = views)
import sys, os, glob
from PIL import Image, ImageDraw
d, out = sys.argv[1], sys.argv[2]
files = sorted(glob.glob(os.path.join(d, "*_*.png")))
poses = []
views = []
for f in files:
    n = os.path.basename(f)[:-4]
    p, v = n.rsplit("_", 1)
    if p not in poses: poses.append(p)
    if v not in views: views.append(v)
order = sys.argv[3].split(",") if len(sys.argv) > 3 else poses
vorder = sys.argv[4].split(",") if len(sys.argv) > 4 else views
CW, CH = 520, 400
sheet = Image.new("RGB", (CW * len(vorder), CH * len(order)), (30, 30, 40))
dr = ImageDraw.Draw(sheet)
for r, p in enumerate(order):
    for c, v in enumerate(vorder):
        fp = os.path.join(d, f"{p}_{v}.png")
        if not os.path.exists(fp): continue
        im = Image.open(fp).convert("RGB")
        w, h = im.size
        # crop the middle: the plushie is centred
        cx, cy = w // 2, h // 2
        crop = im.crop((cx - 430, cy - 330, cx + 430, cy + 330)).resize((CW, CH))
        sheet.paste(crop, (c * CW, r * CH))
        dr.text((c * CW + 8, r * CH + 6), f"{p} / {v}", fill=(255, 255, 255))
sheet.save(out)
print(out, sheet.size)
