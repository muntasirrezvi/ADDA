"""3D gift art for Adda: a still icon for every gift and short animations for the big gifts.

    OUT=out python3 gifts.py icons            # all icons (PNG)
    OUT=out python3 gifts.py anim car jet     # animation frames (PNG sequence per gift)
"""
import sys, os, math, random
sys.path.insert(0, os.path.dirname(__file__))
from lib import *
from mathutils import Vector, Euler
import bmesh

from assets import gold, leaf, stem, brilliant, star_mesh

B = {}


def model(fn):
    B[fn.__name__] = fn
    return fn


def objs():
    return [o for o in bpy.context.scene.objects if o.type in ('MESH', 'CURVE', 'FONT', 'EMPTY') and o.parent is None]


def wrap(name):
    root = group(objs(), name)
    return root


# ---------------------------------------------------------------- small gifts
@model
def rose():
    petal = mat('petal', (0.62, 0.0, 0.04), rough=0.35, sss=0.35, sheen=0.4)
    rnd = random.Random(3)
    # spiral of cupped petals, tighter in the middle
    for i in range(16):
        t = i / 15
        a = i * 2.4
        r = 0.08 + 0.42 * t
        p = sphere(0.36 + 0.18 * t, (r * math.cos(a), r * math.sin(a), 1.25 - 0.25 * t), seg=32, rings=16, m=petal)
        p.scale = (1.0, 0.18 + 0.1 * t, 0.95)
        p.rotation_euler = (math.radians(25 + 45 * t), 0, a + math.pi / 2)
    core = sphere(0.22, (0, 0, 1.25), m=petal)
    core.scale = (1, 1, 1.4)
    sepal = mat('sepal', (0.1, 0.35, 0.06), rough=0.5, sss=0.2)
    for k in range(5):
        a = k * 2 * math.pi / 5
        leaf((0.28 * math.cos(a), 0.28 * math.sin(a), 0.78), (math.radians(60), 0, a + math.pi / 2), 0.3, sepal)
    stem([(0, 0, 0.8), (0.05, 0, 0.0), (-0.05, 0, -1.2)], 0.05, sepal)
    leaf((0.35, 0, -0.2), (0, math.radians(-50), 0.3), 0.42, sepal)
    leaf((-0.3, 0, -0.6), (0, math.radians(50), -0.4), 0.36, sepal)


@model
def coffee():
    glass = mat('glass', (1, 1, 1), rough=0.02, trans=1.0, ior=1.5)
    tea = mat('tea', (0.55, 0.28, 0.1), rough=0.1, trans=0.6, sss=0.3)
    revolve([(0.0, 0.0), (0.42, 0.0), (0.46, 0.05), (0.55, 0.9), (0.62, 1.35), (0.6, 1.37), (0.53, 0.9), (0.42, 0.08), (0.0, 0.08)], m=glass)
    revolve([(0.0, 0.1), (0.42, 0.1), (0.52, 0.9), (0.57, 1.15), (0.0, 1.15)], m=tea)
    foam = mat('foam', (0.92, 0.8, 0.62), rough=0.7)
    cyl(0.56, 0.04, (0, 0, 1.16), m=foam)
    saucer = gold('saucer', 0.18)
    revolve([(0.0, -0.12), (0.9, -0.1), (1.05, 0.0), (1.06, 0.03), (0.9, -0.05), (0.0, -0.06)], m=saucer)
    # little steam wisps
    steam = mat('steam', (1, 1, 1), rough=1, trans=0.3, alpha=0.35)
    for k in range(2):
        stem([(0.1 * k - 0.05, 0, 1.4), (0.2 - 0.25 * k, 0, 1.8), (0.0, 0, 2.2)], 0.035, steam)


@model
def kiss():
    red = mat('lip', (0.78, 0.0, 0.1), rough=0.08, coat=1.0, sss=0.25)
    # parametric heart: a smooth closed surface, no seams
    me = bpy.data.meshes.new('heart'); bm = bmesh.new()
    n_u, n_v = 96, 48
    rows = []
    for j in range(n_v + 1):
        v = math.pi * j / n_v
        row = []
        for i in range(n_u):
            u = 2 * math.pi * i / n_u
            x = 16 * math.sin(u) ** 3
            z = 13 * math.cos(u) - 5 * math.cos(2 * u) - 2 * math.cos(3 * u) - math.cos(4 * u)
            r = math.sin(v)
            row.append(bm.verts.new((x * r / 16, math.cos(v) * 0.42, z * r / 16)))
        rows.append(row)
    for j in range(n_v):
        for i in range(n_u):
            a, b, c, d = rows[j][i], rows[j][(i + 1) % n_u], rows[j + 1][(i + 1) % n_u], rows[j + 1][i]
            try:
                bm.faces.new((a, b, c, d))
            except ValueError:
                pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-4)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    h = link(bpy.data.objects.new('heart', me)); give(h, red); smooth(h)
    sm = h.modifiers.new('s', 'SMOOTH'); sm.iterations = 6; sm.factor = 0.6
    subsurf(h, 1)
    # a little gold heart charm
    g = gold('rim', 0.15)
    c = link(bpy.data.objects.new('charm', me.copy())); give(c, g); smooth(c)
    c.scale = (0.22, 0.4, 0.22); c.location = (0.85, -0.25, 0.75); c.rotation_euler = (0, 0.4, 0)

@model
def perfume():
    glass = mat('pglass', (0.95, 0.85, 0.65), rough=0.02, trans=1.0, ior=1.52)
    oud = mat('oud', (0.55, 0.25, 0.05), rough=0.05, trans=0.9, ior=1.4)
    b = cube((1.3, 0.75, 1.35), (0, 0, 0.67), m=glass, bevel=0.12)
    cube((1.1, 0.55, 0.95), (0, 0, 0.55), m=oud, bevel=0.1)
    g = gold('cap', 0.1)
    cyl(0.18, 0.25, (0, 0, 1.45), m=g)
    cap = revolve([(0.0, 1.55), (0.42, 1.6), (0.48, 1.85), (0.3, 2.15), (0.0, 2.3)], m=g)
    sphere(0.12, (0, 0, 2.32), m=g)
    torus(0.32, 0.03, (0, 0, 1.58), m=g)


@model
def teddy():
    fur = mat('fur', (0.55, 0.32, 0.14), rough=0.8, sheen=1.0, sss=0.1)
    bump(fur, 120, 0.5)
    light = mat('muzzle', (0.85, 0.66, 0.45), rough=0.8, sheen=0.8)
    eye = mat('eye', (0.02, 0.02, 0.02), rough=0.05, coat=1.0)
    body = sphere(0.85, (0, 0, 0.75), m=fur); body.scale = (1, 0.85, 1.05)
    sphere(0.5, (0, -0.62, 0.65), m=light).scale = (0.9, 0.5, 1.0)
    head = sphere(0.68, (0, 0, 1.95), m=fur)
    for s in (-1, 1):
        sphere(0.26, (0.52 * s, 0.05, 2.5), m=fur).scale = (1, 0.6, 1)
        sphere(0.16, (0.52 * s, -0.08, 2.5), m=light).scale = (1, 0.4, 1)
        sphere(0.3, (0.8 * s, -0.2, 1.05), m=fur).scale = (0.8, 0.8, 1.2)   # arms
        sphere(0.36, (0.5 * s, -0.45, 0.12), m=fur).scale = (0.9, 1.2, 0.7)  # legs
        sphere(0.2, (0.5 * s, -0.85, 0.12), m=light).scale = (1, 0.3, 1)
        sphere(0.08, (0.24 * s, -0.6, 2.08), m=eye)
    sphere(0.3, (0, -0.58, 1.82), m=light).scale = (1.1, 0.7, 0.8)
    sphere(0.09, (0, -0.8, 1.9), m=eye).scale = (1.3, 1, 0.9)
    bow = mat('bow', (0.8, 0.02, 0.1), rough=0.3, sheen=0.6)
    for s in (-1, 1):
        sphere(0.22, (0.22 * s, -0.55, 1.42), m=bow).scale = (1.2, 0.5, 0.8)
    sphere(0.1, (0, -0.62, 1.42), m=bow)


@model
def snowflake():
    ice = mat('ice', (0.75, 0.9, 1.0), rough=0.05, trans=1.0, ior=1.31, emit=(0.4, 0.7, 1.0), emit_str=0.3)
    parts = []
    for k in range(6):
        a = k * math.pi / 3
        arm = cube((0.18, 2.2, 0.12), (0, 0, 0), m=ice, bevel=0.04)
        arm.rotation_euler = (0, 0, a)
        parts.append(arm)
        for d, ln in ((0.55, 0.7), (0.85, 0.5)):
            for s in (-1, 1):
                br = cube((0.12, ln, 0.1), (0, 0, 0), m=ice, bevel=0.03)
                ang = a + s * math.radians(45)
                br.location = (math.cos(a + math.pi / 2) * d + math.cos(ang + math.pi / 2) * ln / 2,
                               math.sin(a + math.pi / 2) * d + math.sin(ang + math.pi / 2) * ln / 2, 0)
                br.rotation_euler = (0, 0, ang)
                parts.append(br)
    hexc = cyl(0.3, 0.16, (0, 0, 0), m=ice, verts=6)
    root = group(parts + [hexc], 'flake')
    root.rotation_euler = (math.radians(75), 0, 0)


@model
def moon():
    g = gold('moon', 0.14)
    # crescent: a thick-in-the-middle curved horn
    cu = bpy.data.curves.new('cres', 'CURVE'); cu.dimensions = '3D'
    cu.bevel_depth = 0.42; cu.bevel_resolution = 8; cu.use_fill_caps = True
    sp = cu.splines.new('BEZIER'); n = 9; sp.bezier_points.add(n - 1)
    for k, bp in enumerate(sp.bezier_points):
        a = math.radians(-130 + 260 * k / (n - 1))
        bp.co = (math.sin(a) * 1.1, 0, math.cos(a) * 1.1)
        bp.handle_left_type = bp.handle_right_type = 'AUTO'
        bp.radius = max(0.04, math.cos(math.radians(-130 + 260 * k / (n - 1)) * 0.69) ** 1.6)
    c = link(bpy.data.objects.new('cres', cu)); cu.materials.append(g)
    c.rotation_euler = (0, math.radians(-90), 0)
    st = star_mesh(g, 0.25); st.scale = (0.3, 0.3, 0.5); st.location = (0.05, 0, 0.0); st.rotation_euler = (math.pi / 2, 0, 0.3)
    gem = mat('mgem', (0.1, 0.9, 0.6), rough=0.0, trans=1.0, ior=1.6)
    sphere(0.1, (-0.95, -0.2, 0.0), m=gem)

@model
def firework():
    paper = mat('tube', (0.8, 0.05, 0.08), rough=0.4, coat=0.4)
    gstripe = gold('fs', 0.25)
    cyl(0.3, 1.6, (0, 0, 0), m=paper)
    for z in (-0.5, 0.0, 0.5):
        torus(0.3, 0.03, (0, 0, z), m=gstripe)
    cone(0.36, 0.0, 0.6, (0, 0, 1.1), m=gstripe)
    stem([(0, 0, -0.8), (0.1, 0, -1.2), (-0.05, 0, -1.6)], 0.025, mat('fuse', (0.3, 0.25, 0.2), rough=0.8))
    rnd = random.Random(7)
    cols = [(1, 0.85, 0.2), (1, 0.25, 0.35), (0.3, 0.8, 1), (0.6, 1, 0.4)]
    for i in range(40):
        a, e = rnd.uniform(0, 6.28), rnd.uniform(0.2, 1.2)
        d = rnd.uniform(1.2, 1.9)
        c = cols[i % 4]
        sphere(0.07, (math.cos(a) * math.cos(e) * d, math.sin(a) * math.cos(e) * d * 0.5, 1.6 + math.sin(e) * d * 0.6),
               seg=12, rings=6, m=mat(f'sp{i % 4}', c, emit=c, emit_str=8))


# ---------------------------------------------------------------- luxury
@model
def ring():
    g = gold('band', 0.08)
    torus(1.0, 0.13, (0, 0, 0), m=g, rot=(math.pi / 2, 0, 0), maj=128, mino=32)
    # setting: prongs around the stone on top
    cone(0.32, 0.18, 0.28, (0, 0, 1.18), m=g, verts=32)
    dia = mat('dia', (1, 1, 1), rough=0.0, trans=1.0, ior=2.42, disp=0.04)
    d = brilliant(dia)
    d.scale = (0.48, 0.48, 0.48)
    d.location = (0, 0, 1.55)
    for k in range(6):
        a = k * math.pi / 3
        stem([(0.3 * math.cos(a), 0.3 * math.sin(a), 1.25), (0.42 * math.cos(a), 0.42 * math.sin(a), 1.6)], 0.035, g)
    small = mat('smd', (1, 1, 1), rough=0.0, trans=1.0, ior=2.42)
    for k in (-1, 1):
        s = brilliant(small); s.scale = (0.14, 0.14, 0.14)
        s.location = (0.42 * k, 0, 1.08); s.rotation_euler = (0, -0.5 * k, 0)


@model
def crown():
    g = gold('crown', 0.12)
    band = cyl(1, 0.5, (0, 0, 0), m=g, verts=96)
    inner = cyl(0.86, 0.6, (0, 0, 0), verts=96)
    md = band.modifiers.new('b', 'BOOLEAN'); md.operation = 'DIFFERENCE'; md.object = inner; md.solver = 'EXACT'
    apply_all(band); bpy.data.objects.remove(inner)
    bev(band, 0.03, 3); smooth(band)
    torus(0.94, 0.07, (0, 0, -0.25), m=g); torus(0.94, 0.05, (0, 0, 0.25), m=g)
    velvet = mat('velvet', (0.45, 0.0, 0.06), rough=0.6, sheen=1.0)
    cap = sphere(0.85, (0, 0, 0.35), m=velvet); cap.scale = (1, 1, 0.7)
    ruby = mat('ruby', (0.85, 0.02, 0.08), rough=0.0, trans=1.0, ior=1.77)
    sapph = mat('sap', (0.05, 0.25, 0.95), rough=0.0, trans=1.0, ior=1.77)
    for k in range(8):
        a = k * 2 * math.pi / 8
        x, y = 0.93 * math.cos(a), 0.93 * math.sin(a)
        sp = cone(0.26, 0.0, 0.85 if k % 2 == 0 else 0.55, (x, y, 0.62 if k % 2 == 0 else 0.48), m=g, verts=32)
        sp.scale = (1, 0.45, 1); sp.rotation_euler = (0, 0, a + math.pi / 2)
        sphere(0.1, (x, y, 1.08 if k % 2 == 0 else 0.8), m=g)
        gm = sphere(0.12, (x * 1.06, y * 1.06, 0.0), m=ruby if k % 2 == 0 else sapph); gm.scale = (1, 1, 1.3)
    sphere(0.14, (0, 0, 1.0), m=g)
    cx = cube((0.08, 0.08, 0.45), (0, 0, 1.3), m=g); cube((0.3, 0.08, 0.08), (0, 0, 1.38), m=g)


@model
def car():
    paint = mat('paint', (0.72, 0.01, 0.02), rough=0.12, metal=0.5, coat=1.0)
    glass = mat('cglass', (0.02, 0.03, 0.05), rough=0.02, coat=1.0)
    tire = mat('tire', (0.015, 0.015, 0.015), rough=0.75)
    rim = mat('rim', (0.8, 0.8, 0.83), rough=0.12, metal=1.0)
    dark = mat('trim', (0.02, 0.02, 0.02), rough=0.35)
    light = mat('hl', (1, 1, 1), emit=(1, 0.95, 0.85), emit_str=15)
    tail = mat('tl', (1, 0.1, 0.1), emit=(1, 0.02, 0.02), emit_str=10)

    def slab(profile, width, m, name):
        """side profile (x, z) extruded across the car and rounded."""
        me = bpy.data.meshes.new(name); bm = bmesh.new()
        f = bm.faces.new([bm.verts.new((x, -width / 2, z)) for x, z in profile])
        ext = bmesh.ops.extrude_face_region(bm, geom=[f])
        bmesh.ops.translate(bm, verts=[v for v in ext['geom'] if isinstance(v, bmesh.types.BMVert)], vec=(0, width, 0))
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me); bm.free()
        o = link(bpy.data.objects.new(name, me)); give(o, m)
        bv = o.modifiers.new('b', 'BEVEL'); bv.width = 0.18; bv.segments = 5; bv.limit_method = 'ANGLE'
        subsurf(o, 2); smooth(o)
        return o

    # low wedge body: nose on the right (+x)
    body = slab([(-2.25, 0.25), (2.25, 0.22), (2.3, 0.45), (1.9, 0.62), (0.9, 0.78), (-1.6, 0.9), (-2.2, 0.88), (-2.3, 0.6)], 1.95, paint, 'body')
    cab = slab([(-1.3, 0.85), (1.0, 0.8), (0.35, 1.3), (-0.8, 1.32), (-1.45, 0.95)], 1.55, glass, 'cabin')
    roof = slab([(-0.75, 1.28), (0.3, 1.27), (0.15, 1.36), (-0.65, 1.37)], 1.45, paint, 'roof')
    # wheel arches cut darker, wheels with 5-spoke rims
    for x in (1.35, -1.35):
        for s in (-1, 1):
            t = cyl(0.46, 0.34, (x, 0.88 * s, 0.42), m=tire, rot=(math.pi / 2, 0, 0)); bev(t, 0.1)
            cyl(0.33, 0.36, (x, 0.89 * s, 0.42), m=dark, rot=(math.pi / 2, 0, 0))
            for k in range(5):
                a = k * 2 * math.pi / 5
                sp = cube((0.06, 0.05, 0.6), (0, 0, 0), m=rim, bevel=0.02)
                sp.rotation_euler = (0, a, 0)
                sp.location = (x, 0.99 * s, 0.42)
            cyl(0.31, 0.03, (x, 1.0 * s, 0.42), m=rim, rot=(math.pi / 2, 0, 0))
            cyl(0.08, 0.06, (x, 1.02 * s, 0.42), m=rim, rot=(math.pi / 2, 0, 0))
            cyl(0.22, 0.02, (x + 0.05, 0.96 * s, 0.42), m=mat('cal', (0.9, 0.75, 0.05), rough=0.3), rot=(math.pi / 2, 0, 0))  # brake caliper glimpse
    for s in (-1, 1):
        hl = cube((0.3, 0.34, 0.06), (0, 0, 0), m=light, bevel=0.025); hl.rotation_euler = (0, math.radians(-18), 0); hl.location = (2.0, 0.6 * s, 0.47)
        cube((0.05, 0.55, 0.06), (-2.29, 0.55 * s, 0.72), m=tail, bevel=0.02)
        cube((0.5, 0.05, 0.14), (0.6, 0.98 * s, 0.55), m=dark, bevel=0.03)   # side intake
        mir = sphere(0.09, (0.75, 0.88 * s, 1.0), m=paint); mir.scale = (1.4, 0.8, 0.7)
    cube((0.5, 1.8, 0.05), (-2.05, 0, 1.12), m=dark, bevel=0.02)   # wing
    for s in (-1, 1):
        cube((0.06, 0.06, 0.25), (-2.0, 0.5 * s, 0.98), m=dark)
    cube((0.08, 1.3, 0.14), (2.27, 0, 0.3), m=dark, bevel=0.03)

def _plate(outline, thick, m, name, bend=0.0):
    """flat shape from an outline (x, y), given some thickness, rounded and bent down towards +y."""
    me = bpy.data.meshes.new(name); bm = bmesh.new()
    f = bm.faces.new([bm.verts.new((x, y, -thick / 2)) for x, y in outline])
    ext = bmesh.ops.extrude_face_region(bm, geom=[f])
    bmesh.ops.translate(bm, verts=[v for v in ext['geom'] if isinstance(v, bmesh.types.BMVert)], vec=(0, 0, thick))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me); bm.free()
    o = link(bpy.data.objects.new(name, me)); give(o, m)
    sd = o.modifiers.new('sd', 'SUBSURF'); sd.levels = 2; sd.render_levels = 2
    apply_all(o)
    if bend:
        for v in o.data.vertices:
            v.co.z -= bend * abs(v.co.y) ** 2
    smooth(o)
    return o


WING = [(0.42, 0.0), (0.55, 0.6), (0.5, 1.2), (0.3, 1.8), (0.05, 2.35), (-0.12, 2.4), (-0.05, 2.15), (-0.3, 2.15), (-0.18, 1.9),
        (-0.45, 1.85), (-0.3, 1.6), (-0.55, 1.5), (-0.38, 1.25), (-0.6, 1.1), (-0.45, 0.85), (-0.6, 0.6), (-0.45, 0.3), (-0.5, 0.0)]
TAIL = [(0.0, -0.25), (-0.9, -0.55), (-1.05, -0.3), (-1.2, -0.12), (-1.1, 0.0), (-1.2, 0.12), (-1.05, 0.3), (-0.9, 0.55), (0.0, 0.25)]


def _bird(feather, accent, phoenix=False):
    """A bird with spread wings: wing roots are empties named wingp* so animations can flap them."""
    body = sphere(0.62, (0, 0, 0), m=feather); body.scale = (1.35, 0.72, 0.68)
    neck = sphere(0.4, (0.78, 0, 0.22), m=feather); neck.scale = (1, 0.8, 0.9)
    head = sphere(0.34, (1.15, 0, 0.45), m=feather); head.scale = (1.15, 0.88, 0.88)
    beak = cone(0.12, 0.0, 0.42, (1.52, 0, 0.38), m=accent, rot=(0, math.radians(105), 0))
    beak.scale = (1, 0.8, 1)
    eye = mat('beye', (0.02, 0.02, 0.02), rough=0.05, coat=1)
    for s in (-1, 1):
        sphere(0.055, (1.32, 0.24 * s, 0.55), m=eye)
    for s in (-1, 1):
        w = bpy.data.objects.new('wingp', None); link(w)
        w.location = (0.1, 0.25 * s, 0.15)
        wing = _plate([(x, y * s) for x, y in (WING if s > 0 else list(reversed(WING)))], 0.08, feather, 'wing', bend=0.04)
        wing.parent = w
        tip = _plate([(x * 0.7 - 0.05, y * s * 0.9 + 0.35 * s) for x, y in (WING[3:15] if s > 0 else list(reversed(WING[3:15])))], 0.05, accent, 'tip', bend=0.05)
        tip.location = (0, 0, 0.05); tip.parent = w
    ln = 1.0 if not phoenix else 1.9
    tail = _plate([(x * ln - 0.7, y * (1.2 if phoenix else 1)) for x, y in TAIL], 0.05, accent, 'tail')
    tail.location = (0, 0, -0.05); tail.rotation_euler = (0, math.radians(-6), 0)
    if phoenix:
        for i in range(3):
            st = stem([(-1.2, 0.15 * (i - 1), -0.05), (-2.4, 0.5 * (i - 1), -0.35), (-3.3, 0.8 * (i - 1), 0.1)], 0.05, accent)
        crest = mat('crest', (1, 0.85, 0.2), emit=(1, 0.7, 0.1), emit_str=8)
        for i in range(3):
            c = sphere(0.5, (0, 0, 0), m=crest); c.scale = (0.45, 0.05, 0.07)
            c.location = (0.95 - 0.08 * i, 0, 0.82 + 0.06 * i); c.rotation_euler = (0, math.radians(-30 - 18 * i), 0)

@model
def falcon():
    g = gold('falcon', 0.18)
    dark = gold('falcon2', 0.3)
    dark.node_tree.nodes['Principled BSDF'].inputs['Base Color'].default_value = (0.55, 0.32, 0.08, 1)
    _bird(g, dark)


@model
def yacht():
    white = mat('hull', (0.96, 0.96, 0.97), rough=0.15, coat=0.8)
    navy = mat('navy', (0.04, 0.08, 0.2), rough=0.2, coat=0.8)
    glass = mat('yglass', (0.03, 0.06, 0.1), rough=0.02, coat=1.0)
    teak = mat('teak', (0.5, 0.3, 0.15), rough=0.5)
    hull = cube((4.6, 1.5, 0.8), (0, 0, 0.4), m=white, bevel=0.15)
    for v in hull.data.vertices:
        if v.co.x > 0:
            v.co.y *= max(0.05, 1 - (v.co.x / 2.3) ** 2)   # pointed bow
        if v.co.z < 0:
            v.co.y *= 0.7
            v.co.x *= 0.9
    band = cube((4.4, 1.52, 0.18), (0, 0, 0.12), m=navy)
    for v in band.data.vertices:
        if v.co.x > 0:
            v.co.y *= max(0.05, 1 - (v.co.x / 2.2) ** 2)
    cube((3.6, 1.3, 0.05), (-0.3, 0, 0.82), m=teak)
    d1 = cube((2.6, 1.1, 0.45), (-0.5, 0, 1.08), m=white, bevel=0.12)
    cube((2.5, 1.12, 0.16), (-0.5, 0, 1.1), m=glass, bevel=0.05)
    d2 = cube((1.6, 0.9, 0.38), (-0.7, 0, 1.5), m=white, bevel=0.12)
    cube((1.5, 0.92, 0.12), (-0.65, 0, 1.52), m=glass, bevel=0.04)
    cube((0.8, 0.7, 0.08), (-0.8, 0, 1.75), m=navy, bevel=0.03)
    cyl(0.04, 0.7, (-0.9, 0, 2.1), m=white)
    cube((0.5, 0.05, 0.05), (-0.9, 0, 2.35), m=white)


@model
def jet():
    white = mat('jw', (0.95, 0.95, 0.96), rough=0.2, coat=0.6, metal=0.2)
    gold_m = gold('jg', 0.18)
    glass = mat('jglass', (0.03, 0.05, 0.08), rough=0.02, coat=1.0)
    fus = revolve([(0.0, -2.6), (0.18, -2.5), (0.42, -2.0), (0.5, -1.0), (0.5, 1.5), (0.42, 2.1), (0.22, 2.5), (0.0, 2.6)], m=white)
    fus.rotation_euler = (0, math.pi / 2, 0)
    cube((0.12, 0.85, 0.12), (2.25, 0, 0.28), m=glass, bevel=0.05)   # cockpit
    for i in range(6):
        sphere(0.07, (1.4 - i * 0.5, -0.49, 0.12), m=glass).scale = (1.2, 0.3, 0.9)
        sphere(0.07, (1.4 - i * 0.5, 0.49, 0.12), m=glass).scale = (1.2, 0.3, 0.9)
    for s in (-1, 1):
        w = cube((1.3, 2.4, 0.08), (0.0, 1.5 * s, -0.15), m=white, bevel=0.03)
        for v in w.data.vertices:
            if v.co.y * s > 0:
                v.co.x -= 0.55            # swept back
                v.co.x *= 0.55
        cube((0.08, 0.06, 0.3), (-0.55, 2.7 * s, 0.0), m=gold_m)   # winglet
        e = cyl(0.2, 0.9, (-1.2, 0.75 * s, 0.38), m=white, rot=(0, math.pi / 2, 0)); bev(e, 0.05)
        cyl(0.21, 0.08, (-0.8, 0.75 * s, 0.38), m=gold_m, rot=(0, math.pi / 2, 0))
        h = cube((0.6, 0.9, 0.06), (-2.25, 0.45 * s, 0.35), m=white, bevel=0.02)
    fin = cube((0.9, 0.07, 1.0), (-2.2, 0, 0.75), m=white, bevel=0.03)
    for v in fin.data.vertices:
        if v.co.z > 0:
            v.co.x -= 0.35
    cube((1.0, 0.03, 0.06), (0.0, -0.505, -0.05), m=gold_m)
    cube((1.0, 0.03, 0.06), (0.0, 0.505, -0.05), m=gold_m)


# ---------------------------------------------------------------- exclusive
@model
def palace():
    marble = mat('marble', (0.95, 0.93, 0.9), rough=0.25, coat=0.3, sss=0.1)
    color_tex(marble, (0.85, 0.83, 0.8), (1.0, 0.99, 0.97), scale=4, kind='noise', lo=0.45, hi=0.6)
    g = gold('pg', 0.15)
    arch = mat('arch', (0.08, 0.06, 0.12), rough=0.3, emit=(1, 0.7, 0.3), emit_str=0.6)
    cube((4.6, 3.0, 0.3), (0, 0, 0.15), m=marble, bevel=0.03)
    cube((3.0, 2.2, 1.6), (0, 0, 1.1), m=marble, bevel=0.04)
    for x in (-0.9, 0, 0.9):
        a = cube((0.5, 0.05, 0.9), (x, -1.1, 0.95), m=arch, bevel=0.02)
        sphere(0.25, (x, -1.12, 1.4), m=arch).scale = (1, 0.1, 1)
    # central onion dome
    dome = revolve([(0.0, 1.9), (0.95, 1.9), (1.15, 2.4), (1.05, 2.9), (0.6, 3.35), (0.2, 3.7), (0.0, 3.85)], m=marble)
    cyl(0.95, 0.25, (0, 0, 1.95), m=marble)
    cone(0.06, 0.0, 0.6, (0, 0, 4.1), m=g)
    sphere(0.1, (0, 0, 3.85), m=g)
    for sx in (-1, 1):
        for sy in (-1, 1):
            x, y = 2.05 * sx, 1.3 * sy
            cyl(0.18, 3.0, (x, y, 1.65), m=marble, verts=24)
            for z in (1.2, 2.2, 3.0):
                cyl(0.24, 0.08, (x, y, z), m=marble, verts=24)
            revolve([(0.0, 3.15), (0.24, 3.15), (0.28, 3.35), (0.0, 3.65)], m=marble, loc=(x, y, 0))
            cone(0.03, 0.0, 0.3, (x, y, 3.8), m=g)
        sd = revolve([(0.0, 2.0), (0.42, 2.0), (0.5, 2.25), (0.3, 2.55), (0.0, 2.7)], m=marble, loc=(1.0 * sx, 0, 0))
        cone(0.03, 0.0, 0.25, (1.0 * sx, 0, 2.82), m=g)
    torus(0.98, 0.04, (0, 0, 2.06), m=g)


@model
def dragon():
    jade = mat('jade', (0.06, 0.5, 0.26), rough=0.12, sss=0.6, coat=0.9)
    bump(jade, 40, 0.35, kind='voronoi')
    g = gold('dg', 0.2)
    pts = []
    n = 12
    for i in range(n):
        t = i / (n - 1)
        rr = 1.5 - 0.55 * t
        pts.append((math.cos(t * math.pi * 2.6) * rr, math.sin(t * math.pi * 2.6) * rr, -0.9 + 2.8 * t + 0.25 * math.sin(t * 18)))
    cu = bpy.data.curves.new('body', 'CURVE'); cu.dimensions = '3D'
    cu.bevel_depth = 0.42; cu.bevel_resolution = 8; cu.use_fill_caps = True
    sp = cu.splines.new('BEZIER'); sp.bezier_points.add(n - 1)
    for i, (bp, p) in enumerate(zip(sp.bezier_points, pts)):
        bp.co = p; bp.handle_left_type = bp.handle_right_type = 'AUTO'
        bp.radius = 0.25 + 0.85 * (i / (n - 1)) ** 0.7
    body = link(bpy.data.objects.new('body', cu)); cu.materials.append(jade)
    belly = mat('belly', (0.85, 0.75, 0.35), rough=0.3, metal=0.4)
    for i in range(1, n - 1):
        p = Vector(pts[i]); r = 0.42 * (0.25 + 0.85 * (i / (n - 1)) ** 0.7)
        sp_ = cone(0.1 + 0.08 * i / n, 0.0, 0.45, (p.x, p.y, p.z + r + 0.12), m=g)
        sp_.rotation_euler = (0, -0.3, math.atan2(p.y, p.x))
    hx, hy, hz = pts[-1]
    head = sphere(0.55, (hx + 0.25, hy, hz + 0.25), m=jade); head.scale = (1.45, 0.95, 0.85)
    snout = sphere(0.36, (hx + 0.95, hy, hz + 0.1), m=jade); snout.scale = (1.35, 0.85, 0.65)
    jaw = sphere(0.3, (hx + 0.8, hy, hz - 0.18), m=belly); jaw.scale = (1.4, 0.75, 0.4)
    eye = mat('deye', (1, 0.8, 0.1), emit=(1, 0.6, 0.0), emit_str=8)
    for s in (-1, 1):
        sphere(0.09, (hx + 0.7, hy + 0.36 * s, hz + 0.42), m=eye)
        h = cone(0.09, 0.0, 0.9, (hx - 0.15, hy + 0.26 * s, hz + 0.8), m=g); h.rotation_euler = (0.45 * s, -0.75, 0)
        stem([(hx + 1.2, hy + 0.2 * s, hz), (hx + 1.6, hy + 0.65 * s, hz - 0.25), (hx + 1.85, hy + 0.9 * s, hz + 0.25)], 0.03, g)
    for i in (3, 7):   # claws
        p = Vector(pts[i])
        for s in (-1, 1):
            c = cone(0.07, 0.0, 0.35, (p.x, p.y + 0.4 * s, p.z - 0.35), m=g); c.rotation_euler = (math.pi, 0, 0)
    pearl = mat('pearl', (1, 1, 0.95), rough=0.12, coat=1, emit=(1, 0.95, 0.8), emit_str=2)
    sphere(0.32, (hx + 1.6, hy - 0.8, hz + 0.9), m=pearl)

@model
def phoenix():
    flame = mat('flame', (0.9, 0.12, 0.01), rough=0.35, sss=0.3, emit=(1.0, 0.18, 0.0), emit_str=1.2)
    ember = mat('ember', (1.0, 0.55, 0.02), rough=0.3, metal=0.3, emit=(1.0, 0.45, 0.0), emit_str=2.0)
    _bird(flame, ember, phoenix=True)


# ---------------------------------------------------------------- render: icons
ICON_VIEW = {
    'rose': (-10, 12), 'coffee': (-15, 20), 'kiss': (-18, 8), 'perfume': (-20, 15), 'teddy': (-15, 10),
    'snowflake': (0, 5), 'moon': (-15, 5), 'firework': (-10, 8), 'ring': (-15, 18), 'crown': (-10, 16),
    'car': (-38, 14), 'falcon': (-25, 58), 'yacht': (-35, 18), 'jet': (-30, 22), 'palace': (-25, 12),
    'dragon': (-25, 18), 'phoenix': (-25, 58),
}


def icon(name):
    reset(320)
    B[name]()
    if name in ('falcon', 'phoenix'):
        for o in bpy.context.scene.objects:
            if o.name.startswith('wingp'):
                o.rotation_euler = (math.radians(12) * (1 if o.location.y > 0 else -1), 0, 0)
    yaw, elev = ICON_VIEW.get(name, (-15, 15))
    render(f'gift_{name}', yaw=math.radians(yaw), elev=math.radians(elev))


# ---------------------------------------------------------------- render: animations
def keyframe(o, f, loc=None, rot=None, scale=None):
    if loc is not None:
        o.location = loc; o.keyframe_insert('location', frame=f)
    if rot is not None:
        o.rotation_euler = rot; o.keyframe_insert('rotation_euler', frame=f)
    if scale is not None:
        o.scale = scale if isinstance(scale, tuple) else (scale, scale, scale); o.keyframe_insert('scale', frame=f)


def smooth_keys(o):
    # Blender 5 keys are Bezier by default; older versions expose fcurves directly
    if o.animation_data and o.animation_data.action and hasattr(o.animation_data.action, 'fcurves'):
        for fc in o.animation_data.action.fcurves:
            for kp in fc.keyframe_points:
                kp.interpolation = 'BEZIER'
                kp.easing = 'AUTO'


def flap(frames, speed=6, amp=40):
    for o in bpy.context.scene.objects:
        if o.name.startswith('wingp'):
            s = 1 if o.location.y > 0 else -1
            for f in range(1, frames + 1, 2):
                a = math.radians(amp) * math.sin(2 * math.pi * f / speed)
                keyframe(o, f, rot=(-s * (a + math.radians(10)), 0, 0))


MOTION = {}


def motion(fn):
    MOTION[fn.__name__] = fn
    return fn


@motion
def m_turn(root, n):   # rise in, then a full turn
    keyframe(root, 1, loc=(0, 0, -1.2), rot=(0, 0, math.radians(-60)), scale=0.2)
    keyframe(root, 12, loc=(0, 0, 0.1), scale=1.08)
    keyframe(root, 18, loc=(0, 0, 0), scale=1.0)
    keyframe(root, n, rot=(0, 0, math.radians(300)))


@motion
def m_drive(root, n):   # car drives in from the left and turns to face the viewer
    keyframe(root, 1, loc=(-9, 2, 0), rot=(0, 0, math.radians(15)))
    keyframe(root, 18, loc=(0, 0, 0), rot=(0, 0, math.radians(-20)))
    keyframe(root, 30, rot=(0, 0, math.radians(-40)))
    keyframe(root, n, loc=(0.3, -0.3, 0), rot=(0, 0, math.radians(-160)))


@motion
def m_fly(root, n):    # flies from far away towards the viewer, banking
    keyframe(root, 1, loc=(6, 12, 3), rot=(math.radians(25), 0, math.radians(-120)), scale=0.5)
    keyframe(root, 20, loc=(0, 0, 0), rot=(math.radians(-10), 0, math.radians(-100)), scale=1.0)
    keyframe(root, n, loc=(-1, -2, 0.6), rot=(math.radians(10), 0, math.radians(-70)), scale=1.1)


@motion
def m_sail(root, n):
    for f in range(1, n + 1, 3):
        t = f / n
        keyframe(root, f, loc=(0, 0, 0.12 * math.sin(t * 6.3 * 2)), rot=(math.radians(3) * math.sin(t * 12), math.radians(2) * math.cos(t * 9), math.radians(-150 + 120 * t)))
    keyframe(root, 1, scale=0.3)
    keyframe(root, 12, scale=1.0)


@motion
def m_bird(root, n):
    keyframe(root, 1, loc=(4, 6, -2), rot=(0, 0, math.radians(-120)), scale=0.4)
    keyframe(root, 18, loc=(0, 0, 0), rot=(0, math.radians(-10), math.radians(-75)), scale=1.0)
    keyframe(root, n, loc=(0, 0, 0.5), rot=(0, math.radians(-15), math.radians(-40)), scale=1.05)
    flap(n)


@motion
def m_palace(root, n):
    keyframe(root, 1, loc=(0, 0, -6), rot=(0, 0, math.radians(-40)), scale=0.85)
    keyframe(root, 20, loc=(0, 0, 0), scale=1.0)
    keyframe(root, n, rot=(0, 0, math.radians(40)))


@motion
def m_dragon(root, n):
    keyframe(root, 1, loc=(0, 0, -5), rot=(0, 0, math.radians(-90)), scale=0.6)
    keyframe(root, 16, loc=(0, 0, 0), scale=1.0)
    keyframe(root, n, rot=(0, 0, math.radians(200)))


ANIM = {
    'crown': 'm_turn', 'ring': 'm_turn', 'car': 'm_drive', 'jet': 'm_fly', 'yacht': 'm_sail',
    'falcon': 'm_bird', 'phoenix': 'm_bird', 'palace': 'm_palace', 'dragon': 'm_dragon',
}


def anim(name, frames=48, size=448):
    reset(size, samples=int(os.environ.get('ASAMPLES', '20')))
    sc = bpy.context.scene
    B[name]()
    root = wrap('root')
    sc.frame_start, sc.frame_end = 1, frames
    MOTION[ANIM[name]](root, frames)
    for o in bpy.context.scene.objects:
        smooth_keys(o)
    # camera fixed on the resting pose (frame ~20), wide enough for the action
    sc.frame_set(20)
    yaw, elev = ICON_VIEW.get(name, (-15, 15))
    yaw, elev = math.radians(yaw), math.radians(elev)
    lo, hi, pts = scene_bounds()
    c = (lo + hi) / 2
    rad = (hi - lo).length / 2
    camd = bpy.data.cameras.new('cam'); cam = link(bpy.data.objects.new('cam', camd)); sc.camera = cam
    camd.lens = 50
    d = Vector((math.sin(yaw) * math.cos(elev), -math.cos(yaw) * math.cos(elev), math.sin(elev)))
    dist = rad * 1.25 / math.tan(math.atan(18 / camd.lens))
    cam.location = c + d * dist
    cam.rotation_euler = (-d).to_track_quat('-Z', 'Y').to_euler()
    lights(-d, scale=max(1.0, rad / 1.2))
    os.makedirs(os.path.join(OUT, name), exist_ok=True)
    sc.render.filepath = os.path.join(OUT, name, 'f')
    sc.render.use_motion_blur = True
    sc.render.motion_blur_shutter = 0.4
    bpy.ops.render.render(animation=True)
    print('animated', name)


if __name__ == '__main__':
    args = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else sys.argv[1:]
    mode, names = (args[0], args[1:]) if args else ('icons', [])
    if mode == 'icons':
        for n in names or list(B):
            icon(n)
    else:
        for n in names or list(ANIM):
            anim(n)
