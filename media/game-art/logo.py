"""Adda app logo: a gold studio microphone with sound waves. Renders the transparent mark."""
import sys, os, math
sys.path.insert(0, os.path.dirname(__file__))
from lib import *
from assets import gold

reset(1024, samples=96)
g = gold('mic', 0.14)
dark = mat('grille', (0.08, 0.05, 0.03), rough=0.35, metal=0.8)
# microphone head: a capsule with grille rings
head = sphere(0.62, (0, 0, 0.75), m=g, seg=64, rings=32)
head.scale = (0.82, 0.82, 1.0)
for z in (0.35, 0.55, 0.75, 0.95, 1.15):
    r = 0.62 * 0.82 * math.sqrt(max(0.0, 1 - ((z - 0.75) / 0.62) ** 2)) + 0.005
    torus(r, 0.022, (0, 0, z), m=dark, maj=96, mino=12)
band = cyl(0.52, 0.12, (0, 0, 0.32), m=g, verts=96); bev(band, 0.03)
# handle
h = cyl(0.17, 0.85, (0, 0, -0.25), m=g, verts=64); bev(h, 0.04)
cone(0.2, 0.17, 0.12, (0, 0, -0.7), m=g)
# stand: a U arc and a base
arc = torus(0.78, 0.055, (0, 0, 0.55), m=g, rot=(math.pi / 2, 0, 0), maj=128, mino=16)
cut = cube((2, 2, 1.0), (0, 0, 1.15))
md = arc.modifiers.new('b', 'BOOLEAN'); md.operation = 'DIFFERENCE'; md.object = cut; md.solver = 'EXACT'
apply_all(arc); bpy.data.objects.remove(cut)
cyl(0.06, 0.55, (0, 0, -0.5), m=g)
base = cyl(0.45, 0.1, (0, 0, -0.82), m=g, verts=96); bev(base, 0.04)
# sound waves on both sides
for s in (-1, 1):
    for k, R in enumerate((1.15, 1.45)):
        w = torus(R, 0.05, (0, 0, 0.6), m=g, rot=(math.pi / 2, 0, 0), maj=128, mino=16)
        keep = cube((1.2, 2, 1.3), (s * (R + 0.45), 0, 0.6))
        md = w.modifiers.new('b', 'BOOLEAN'); md.operation = 'INTERSECT'; md.object = keep; md.solver = 'EXACT'
        apply_all(w); bpy.data.objects.remove(keep)
render('logo_mark', yaw=0, elev=math.radians(6), pad=1.04)
