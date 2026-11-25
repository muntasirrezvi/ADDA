import sys, os, math, random
sys.path.insert(0, os.path.dirname(__file__))
from lib import *
from mathutils import Matrix, Vector, Euler
import bmesh

A = {}


def asset(fn):
    A[fn.__name__] = fn
    return fn


# ---------------------------------------------------------------- dice
PIPS = {
    1: [(0, 0)],
    2: [(-1, -1), (1, 1)],
    3: [(-1, -1), (0, 0), (1, 1)],
    4: [(-1, -1), (1, -1), (-1, 1), (1, 1)],
    5: [(-1, -1), (1, -1), (0, 0), (-1, 1), (1, 1)],
    6: [(-1, -1), (-1, 0), (-1, 1), (1, -1), (1, 0), (1, 1)],
}
# face value -> (normal axis, sign)
FACES = {1: ('z', 1), 6: ('z', -1), 2: ('y', -1), 5: ('y', 1), 3: ('x', 1), 4: ('x', -1)}


def make_die(red=False):
    body = mat('ivory', (0.93, 0.9, 0.84) if not red else (0.75, 0.02, 0.03), rough=0.18, coat=0.8,
               sss=0.2 if not red else 0.0, trans=0.0 if not red else 0.35, ior=1.5)
    pipm = mat('pip', (0.02, 0.02, 0.025) if not red else (0.95, 0.95, 0.95), rough=0.35, coat=0.5)
    d = cube((1.6, 1.6, 1.6), m=body)
    bev(d, 0.22, 8)
    apply_all(d)
    smooth(d)
    cutters = []
    h, s = 0.8, 0.42
    for v, (ax, sg) in FACES.items():
        for a, b in PIPS[v]:
            if ax == 'z':
                loc = (a * s, b * s, sg * h)
            elif ax == 'y':
                loc = (a * s, sg * h, b * s)
            else:
                loc = (sg * h, a * s, b * s)
            c = sphere(0.15, loc, seg=24, rings=12, m=pipm)
            cutters.append(c)
    cut = join(cutters, 'cut')
    md = d.modifiers.new('bool', 'BOOLEAN')
    md.operation = 'DIFFERENCE'
    md.object = cut
    md.solver = 'EXACT'
    md.material_mode = 'TRANSFER'
    apply_all(d)
    bpy.data.objects.remove(cut)
    return d


def face_up(v):
    ax, sg = FACES[v]
    if ax == 'z':
        return Euler((0 if sg > 0 else math.pi, 0, 0)).to_matrix()
    if ax == 'y':
        return Euler((-sg * math.pi / 2, 0, 0)).to_matrix()
    return Euler((0, -sg * math.pi / 2, 0)).to_matrix()


@asset
def dice():
    for v in range(1, 7):
        reset(256)
        d = make_die()
        m = Euler((0, 0, math.radians(18))).to_matrix() @ face_up(v)
        d.matrix_world = m.to_4x4()
        render(f'die_{v}', yaw=math.radians(10), elev=math.radians(55), floor=True)
    rnd = random.Random(7)
    for i in range(8):
        reset(256)
        d = make_die()
        a = i / 8 * 2 * math.pi
        d.rotation_euler = (a * 1.0 + 0.3, a * 2.0 + 0.7, a * 0.5)
        d.location.z = 0.35 * abs(math.sin(a * 2))
        render(f'die_roll_{i}', yaw=math.radians(10), elev=math.radians(55), pad=1.3, floor=True)


# ---------------------------------------------------------------- gems
GEMS = {
    'ruby': ((0.9, 0.02, 0.08), 1.77),
    'sapphire': ((0.05, 0.2, 0.95), 1.77),
    'emerald': ((0.03, 0.8, 0.3), 1.58),
    'amethyst': ((0.55, 0.1, 0.9), 1.54),
    'topaz': ((1.0, 0.65, 0.05), 1.62),
    'diamond': ((0.97, 0.98, 1.0), 2.42),
}


def brilliant(m, n=16):
    me = bpy.data.meshes.new('gem')
    bm = bmesh.new()
    table = [bm.verts.new((0.55 * math.cos(2 * math.pi * i / 8 + math.pi / 8),
                           0.55 * math.sin(2 * math.pi * i / 8 + math.pi / 8), 0.38)) for i in range(8)]
    crown = [bm.verts.new((0.82 * math.cos(2 * math.pi * i / 8), 0.82 * math.sin(2 * math.pi * i / 8), 0.2))
             for i in range(8)]
    gird = [bm.verts.new((math.cos(2 * math.pi * i / n), math.sin(2 * math.pi * i / n), 0.0)) for i in range(n)]
    gird2 = [bm.verts.new((math.cos(2 * math.pi * i / n), math.sin(2 * math.pi * i / n), -0.05)) for i in range(n)]
    culet = bm.verts.new((0, 0, -0.95))
    bm.faces.new(table)
    for i in range(8):
        j = (i + 1) % 8
        bm.faces.new((crown[i], table[i], crown[j])) if False else None
    # crown: table edge i spans crown[i]..crown[i+1]
    for i in range(8):
        j = (i + 1) % 8
        bm.faces.new((table[i], crown[i], crown[j]) if False else (crown[j], table[i], crown[i]))
        bm.faces.new((table[i], crown[j], table[j]) if False else (table[j], table[i], crown[j]))
    for i in range(8):
        a = crown[i]
        g0, g1, g2 = gird[2 * i], gird[2 * i + 1], gird[(2 * i + 2) % n]
        bm.faces.new((a, g0, g1))
        bm.faces.new((a, g1, g2))
        bm.faces.new((a, g2, crown[(i + 1) % 8]))
    for i in range(n):
        j = (i + 1) % n
        bm.faces.new((gird[i], gird2[i], gird2[j], gird[j]))
        bm.faces.new((gird2[i], culet, gird2[j]))
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = link(bpy.data.objects.new('gem', me))
    give(o, m)
    return o


def sparkle_env():
    # emissive cards around the gem so facets catch flashes (hidden from camera)
    em = mat('card', (1, 1, 1), emit=(1, 1, 1), emit_str=6)
    rnd = random.Random(3)
    for i in range(10):
        a = rnd.uniform(0, 2 * math.pi)
        z = rnd.uniform(0.5, 4)
        bpy.ops.mesh.primitive_plane_add(size=rnd.uniform(0.6, 1.6),
                                         location=(4 * math.cos(a), 4 * math.sin(a), z))
        p = bpy.context.object
        p.rotation_euler = (-p.location).to_track_quat('Z', 'Y').to_euler()
        give(p, em)
        p.visible_camera = False
        p['nobounds'] = True


@asset
def gems():
    for name, (col, ior) in GEMS.items():
        reset(256, samples=160)
        m = mat(name, col, rough=0.0, trans=1.0, ior=ior, disp=0.3 if name == 'diamond' else 0.1)
        if name == 'emerald':
            g = cube((1.5, 1.05, 0.8), m=m)
            md = bev(g, 0.22, 1)
            md.limit_method = 'NONE'
        else:
            g = brilliant(m)
        g.rotation_euler = (math.radians(35), 0, math.radians(15))
        sparkle_env()
        render(f'gem_{name}', yaw=math.radians(5), elev=math.radians(30), floor=False)


# ---------------------------------------------------------------- slot / fruit symbols
def gold(name='gold', rough=0.18):
    return mat(name, (1.0, 0.72, 0.25), rough=rough, metal=1.0)


@asset
def seven():
    reset(256)
    red = mat('red', (0.85, 0.02, 0.03), rough=0.15, coat=1.0)
    t = text('7', size=2.2, extrude=0.22, bevel=0.05, m=red, rot=(math.radians(90), 0, 0))
    edge = text('7', size=2.2, extrude=0.16, bevel=0.11, m=gold(), loc=(0, 0.06, 0), rot=(math.radians(90), 0, 0))
    render('sym_seven', yaw=math.radians(-12), elev=math.radians(14), pad=1.2)


@asset
def bar():
    reset(256)
    plate = cube((2.4, 0.3, 1.0), m=mat('blk', (0.02, 0.02, 0.03), rough=0.2, coat=1), bevel=0.12, seg=6)
    rim = cube((2.6, 0.24, 1.2), loc=(0, 0.05, 0), m=gold(), bevel=0.16, seg=6)
    t = text('BAR', size=0.78, extrude=0.06, bevel=0.02, m=gold('g2', 0.12), loc=(0, -0.17, 0),
             rot=(math.radians(90), 0, 0))
    render('sym_bar', yaw=math.radians(-12), elev=math.radians(16))


@asset
def bell():
    reset(256)
    prof = [(0.0, 1.25), (0.12, 1.22), (0.2, 1.1), (0.38, 0.98), (0.52, 0.75), (0.6, 0.45), (0.68, 0.15),
            (0.82, -0.05), (0.98, -0.2), (1.0, -0.3), (0.9, -0.33), (0.0, -0.33)]
    b = revolve(prof, gold('bg', 0.15))
    knob = sphere(0.14, (0, 0, 1.33), m=gold())
    clap = sphere(0.18, (0, 0, -0.42), m=gold('g3', 0.25))
    ring = torus(0.16, 0.05, (0, 0, 1.45), m=gold(), rot=(math.radians(90), 0, 0))
    render('sym_bell', yaw=math.radians(-15), elev=math.radians(18))


def leaf(loc, rot, size=0.5, m=None):
    l = sphere(size, loc, m=m)
    l.scale = (1, 0.42, 0.06)
    l.rotation_euler = rot
    return l


def stem(points, r=0.04, m=None):
    cu = bpy.data.curves.new('stem', 'CURVE')
    cu.dimensions = '3D'
    cu.bevel_depth = r
    cu.bevel_resolution = 4
    cu.use_fill_caps = True
    sp = cu.splines.new('BEZIER')
    sp.bezier_points.add(len(points) - 1)
    for bp, p in zip(sp.bezier_points, points):
        bp.co = p
        bp.handle_left_type = bp.handle_right_type = 'AUTO'
    o = link(bpy.data.objects.new('stem', cu))
    if m:
        cu.materials.append(m)
    return o


def leafm():
    m = mat('leaf', (0.08, 0.45, 0.06), rough=0.45, sss=0.2)
    bump(m, 60, 0.15)
    return m


def stemm():
    return mat('stem', (0.25, 0.35, 0.08), rough=0.6)


@asset
def cherry():
    reset(256)
    m = mat('cherry', (0.55, 0.0, 0.02), rough=0.12, coat=1.0, sss=0.1)
    for x in (-0.55, 0.5):
        c = sphere(0.62, (x, 0, 0), m=m)
        c.scale = (1, 1, 0.92)
    stem([(-0.5, 0, 0.5), (-0.3, 0, 1.3), (0.15, 0, 2.0)], m=stemm())
    stem([(0.48, 0, 0.5), (0.4, 0, 1.3), (0.15, 0, 2.0)], m=stemm())
    leaf((0.55, 0, 2.0), (0, math.radians(20), math.radians(10)), 0.5, leafm())
    render('sym_cherry', yaw=math.radians(-10), elev=math.radians(15))


@asset
def lemon():
    reset(256)
    m = mat('lemon', (1.0, 0.82, 0.05), rough=0.4, sss=0.1)
    bump(m, 90, 0.25)
    prof = []
    for i in range(41):
        t = i / 40
        z = -1.6 + 3.2 * t
        r = 0.85 * math.sin(math.pi * t) ** 0.5 if 0.06 < t < 0.94 else 0.85 * math.sin(math.pi * 0.06) ** 0.5 * (0.35 + 0.65 * (1 - abs(t - 0.5) * 2) / 0.12) * 0.75
        prof.append((r, z))
    l = revolve(prof, m)
    subsurf(l, 1)
    l.rotation_euler = (0, math.radians(75), math.radians(10))
    render('sym_lemon', yaw=math.radians(-10), elev=math.radians(25))


def grape_bunch(col=(0.32, 0.05, 0.45), name='sym_grape'):
    m = mat('grape', col, rough=0.25, coat=0.4, sss=0.2)
    bump(m, 8, 0.05)
    rnd = random.Random(5)
    rows = [(0.9, 6), (0.45, 5), (0.0, 4), (-0.45, 3), (-0.9, 2), (-1.3, 1)]
    for z, n in rows:
        w = n * 0.28
        for i in range(n):
            x = -w + 0.56 * i + 0.28 + rnd.uniform(-0.05, 0.05)
            for y in (-0.15, 0.2):
                sphere(0.3 + rnd.uniform(-0.03, 0.03), (x, y + rnd.uniform(-.05, .05), z), seg=24, rings=12, m=m)
    stem([(0, 0, 1.1), (0.05, 0, 1.5), (0.2, 0, 1.75)], 0.06, stemm())
    leaf((0.55, 0.1, 1.55), (math.radians(20), math.radians(-20), 0), 0.55, leafm())


@asset
def grape():
    reset(256)
    grape_bunch()
    render('sym_grape', yaw=math.radians(-10), elev=math.radians(15))


def star_mesh(m, depth=0.35):
    me = bpy.data.meshes.new('star')
    bm = bmesh.new()
    top = bm.verts.new((0, 0, depth))
    bot = bm.verts.new((0, 0, -depth))
    ring = []
    for i in range(10):
        r = 1.0 if i % 2 == 0 else 0.45
        a = math.pi / 2 + i * math.pi / 5
        ring.append(bm.verts.new((r * math.cos(a), r * math.sin(a), 0)))
    for i in range(10):
        j = (i + 1) % 10
        bm.faces.new((top, ring[i], ring[j]))
        bm.faces.new((bot, ring[j], ring[i]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = link(bpy.data.objects.new('star', me))
    give(o, m)
    return o


@asset
def star():
    reset(256)
    s = star_mesh(gold('sg', 0.12))
    s.rotation_euler = (math.radians(90), 0, 0)
    bev(s, 0.03, 3)
    render('sym_star', yaw=math.radians(-15), elev=math.radians(15))


# fruits
@asset
def apple():
    reset(256)
    m = mat('apple', (0.75, 0.04, 0.04), rough=0.25, coat=0.6, sss=0.05)
    color_tex(m, (0.95, 0.65, 0.1), (0.7, 0.02, 0.03), scale=3, lo=0.18, hi=0.4)
    prof = []
    for i in range(41):
        t = i / 40
        a = math.pi * t
        r = math.sin(a) * (1.0 + 0.08 * math.sin(a * 2))
        z = -math.cos(a) * 0.95
        if t < 0.08:
            z += (0.08 - t) * 1.6  # bottom dimple
        if t > 0.9:
            z -= (t - 0.9) * 2.2  # top dimple
        prof.append((r, z))
    revolve(prof, m)
    stem([(0, 0, 0.6), (0.05, 0, 1.0), (0.18, 0, 1.25)], 0.05, mat('st', (0.3, 0.18, 0.06), rough=0.7))
    leaf((0.45, 0.0, 1.1), (0, math.radians(-25), math.radians(15)), 0.4, leafm())
    render('fruit_apple', yaw=math.radians(-10), elev=math.radians(22))


@asset
def orange():
    reset(256)
    m = mat('orange', (1.0, 0.42, 0.02), rough=0.45, sss=0.1)
    bump(m, 110, 0.35)
    o = sphere(1, m=m)
    o.scale = (1, 1, 0.94)
    leaf((0.3, 0, 1.0), (0, math.radians(-15), math.radians(25)), 0.42, leafm())
    sphere(0.08, (0, 0, 0.93), m=stemm())
    render('fruit_orange', yaw=math.radians(-10), elev=math.radians(28))


@asset
def lemon_fruit():
    lemon()
    os.replace(os.path.join(OUT, 'sym_lemon.png'), os.path.join(OUT, 'fruit_lemon.png'))


@asset
def grape_fruit():
    reset(256)
    grape_bunch((0.25, 0.55, 0.08))
    render('fruit_grape', yaw=math.radians(-10), elev=math.radians(15))


@asset
def cherry_fruit():
    cherry()
    os.replace(os.path.join(OUT, 'sym_cherry.png'), os.path.join(OUT, 'fruit_cherry.png'))


@asset
def strawberry():
    reset(256)
    m = mat('straw', (0.8, 0.02, 0.05), rough=0.25, coat=0.5, sss=0.1)
    bump(m, 18, 0.5, kind='voronoi')
    prof = []
    for i in range(41):
        t = i / 40
        z = -1.2 + 2.0 * t
        r = 0.9 * math.sin(math.pi * 0.5 * t ** 0.6) if t < 0.92 else 0.9 * math.sqrt(max(0.0, (1 - t) / 0.08))
        prof.append((r, z))
    revolve(prof, m)
    lm = leafm()
    for k in range(6):
        a = k * math.pi / 3
        leaf((0.38 * math.cos(a), 0.38 * math.sin(a), 0.82), (0, math.radians(10), a), 0.42, lm)
    stem([(0, 0, 0.8), (0, 0.05, 1.2)], 0.06, stemm())
    render('fruit_strawberry', yaw=math.radians(-10), elev=math.radians(35))


@asset
def watermelon():
    reset(256)
    m = mat('wm', (0.1, 0.35, 0.05), rough=0.25, coat=0.5)
    color_tex(m, (0.05, 0.2, 0.03), (0.35, 0.6, 0.15), scale=3.5, kind='wave', lo=0.45, hi=0.55,
              coord='Object', wave_dir='X', distortion=6)
    o = sphere(1, m=m)
    o.scale = (1.3, 1, 1)
    o.rotation_euler = (0, 0, math.radians(20))
    render('fruit_watermelon', yaw=math.radians(-10), elev=math.radians(25))


@asset
def banana():
    reset(256)
    m = mat('banana', (1.0, 0.82, 0.1), rough=0.45, sss=0.1)
    color_tex(m, (0.35, 0.22, 0.04), (1.0, 0.84, 0.12), kind='gradz', lo=0.03, hi=0.13, mirror=True)
    prof = []
    for i in range(41):
        t = i / 40
        z = -1.8 + 3.6 * t
        r = 0.36 * math.sin(math.pi * t) ** 0.55
        prof.append((max(r, 0.05) if 0 < i < 40 else 0.0, z))
    b = revolve(prof, m, steps=6)
    subsurf(b, 2)
    apply_all(b)
    lay_x(b)
    bend_x(b, 2.6)
    smooth(b)
    b.rotation_euler = (0, math.radians(15), 0)
    render('fruit_banana', yaw=math.radians(-10), elev=math.radians(25))


# ---------------------------------------------------------------- greedy foods
@asset
def tomato():
    reset(256)
    m = mat('tom', (0.85, 0.06, 0.02), rough=0.15, coat=0.8, sss=0.15)
    t = sphere(1, m=m)
    for v in t.data.vertices:
        a = math.atan2(v.co.y, v.co.x)
        k = 1 + 0.05 * math.cos(5 * a) * max(0, v.co.z)
        v.co.x *= k
        v.co.y *= k
    t.scale = (1, 1, 0.8)
    lm = mat('cal', (0.1, 0.4, 0.05), rough=0.5)
    for k in range(5):
        a = k * 2 * math.pi / 5
        leaf((0.32 * math.cos(a), 0.32 * math.sin(a), 0.8), (0, math.radians(-12), a), 0.36, lm)
    stem([(0, 0, 0.75), (0.05, 0, 1.05)], 0.06, lm)
    render('food_tomato', yaw=math.radians(-10), elev=math.radians(35))


@asset
def corn():
    reset(256)
    m = mat('corn', (1.0, 0.75, 0.1), rough=0.3, coat=0.4, sss=0.1)
    color_tex(m, (0.85, 0.55, 0.02), (1.0, 0.85, 0.25), scale=26, kind='voronoi', lo=0.1, hi=0.5)
    bump(m, 26, 0.9, kind='voronoi')
    c = sphere(1, m=m)
    c.scale = (0.45, 0.45, 1.3)
    hm = mat('husk', (0.45, 0.6, 0.15), rough=0.6, sss=0.2)
    for k, a in enumerate((0.3, 2.4, 4.4)):
        l = sphere(1, (0.25 * math.cos(a), 0.25 * math.sin(a), -0.45), m=hm)
        l.scale = (0.38, 0.1, 1.05)
        l.rotation_euler = (0, math.radians(18), a)
    c.rotation_euler = (0, math.radians(35), 0)
    for o in list(bpy.context.scene.objects):
        if o != c and o.type == 'MESH':
            o.parent = c
    render('food_corn', yaw=math.radians(-10), elev=math.radians(25))


@asset
def carrot():
    reset(256)
    m = mat('carrot', (1.0, 0.33, 0.02), rough=0.45, sss=0.1)
    bump(m, 6, 0.4, kind='wave')
    prof = [(0.0, -1.6), (0.05, -1.5), (0.15, -1.1), (0.3, -0.5), (0.42, 0.2), (0.48, 0.75), (0.42, 0.95),
            (0.2, 1.02), (0.0, 1.03)]
    c = revolve(prof, m)
    subsurf(c, 2)
    lm = leafm()
    stems = []
    for k in range(5):
        a = k * 2 * math.pi / 5
        stems.append(stem([(0, 0, 0.95), (0.25 * math.cos(a), 0.25 * math.sin(a), 1.5),
                           (0.45 * math.cos(a), 0.45 * math.sin(a), 2.0)], 0.035, lm))
        leaf((0.5 * math.cos(a), 0.5 * math.sin(a), 2.05), (0, math.radians(-50), a), 0.3, lm)
    root = group([o for o in bpy.context.scene.objects], 'root')
    root.rotation_euler = (0, math.radians(-40), 0)
    render('food_carrot', yaw=math.radians(-10), elev=math.radians(25))


@asset
def lettuce():
    reset(256)
    m = mat('lettuce', (0.35, 0.7, 0.1), rough=0.5, sss=0.3)
    color_tex(m, (0.75, 0.9, 0.45), (0.2, 0.55, 0.05), scale=2, coord='Object', lo=0.3, hi=0.7)
    bump(m, 30, 0.4)
    rnd = random.Random(2)
    for layer in range(4):
        n = 5 + layer
        for k in range(n):
            a = k * 2 * math.pi / n + layer * 0.4
            r = 0.15 + layer * 0.22
            l = ico(0.75 - layer * 0.08, (r * math.cos(a), r * math.sin(a), 0.1 - layer * 0.08), sub=4, m=m)
            l.scale = (1, 0.55, 0.9)
            l.rotation_euler = (math.radians(70 - layer * 12), 0, a + math.pi / 2)
            md = l.modifiers.new('d', 'DISPLACE')
            tx = bpy.data.textures.new('n', 'CLOUDS')
            tx.noise_scale = 0.25
            md.texture = tx
            md.strength = 0.18
    render('food_lettuce', yaw=math.radians(-10), elev=math.radians(35))


@asset
def fish():
    reset(256)
    m = mat('fish', (0.6, 0.65, 0.7), rough=0.18, metal=0.6, coat=0.6)
    color_tex(m, (0.85, 0.88, 0.9), (0.12, 0.3, 0.45), kind='gradz', lo=0.45, hi=0.75)
    bump(m, 40, 0.15, kind='voronoi')
    b = sphere(1, m=m)
    b.scale = (1.5, 0.42, 0.7)
    tail = cone(0.7, 0.0, 0.9, (-1.75, 0, 0), m=mat('fin', (0.4, 0.5, 0.6), rough=0.3, metal=0.4),
                rot=(0, math.radians(-90), 0))
    tail.scale = (1, 0.12, 1)
    fin = cone(0.45, 0, 0.6, (0, 0, 0.6), m=tail.data.materials[0], rot=(0, math.radians(-25), 0))
    fin.scale = (1, 0.08, 1)
    eye = sphere(0.13, (1.05, -0.28, 0.2), m=mat('eye', (0.01, 0.01, 0.01), rough=0.05, coat=1))
    sphere(0.17, (1.05, -0.25, 0.2), m=mat('eyew', (0.95, 0.9, 0.7), rough=0.2))
    render('food_fish', yaw=math.radians(-5), elev=math.radians(20))


@asset
def shrimp():
    reset(256)
    m = mat('shrimp', (1.0, 0.45, 0.25), rough=0.2, coat=0.8, sss=0.4)
    color_tex(m, (0.98, 0.36, 0.12), (1.0, 0.82, 0.68), scale=2.4, kind='wave', coord='Object', wave_dir='X',
              lo=0.6, hi=0.85)
    prof = []
    for i in range(41):
        t = i / 40
        z = -1.6 + 3.2 * t
        r = 0.12 + 0.38 * math.sin(math.pi * 0.5 * min(1, t * 1.3))
        if t > 0.9:
            r *= math.sqrt(max(0.0, (1 - t) / 0.1))
        prof.append((r, z))
    b = revolve(prof, m)
    lay_x(b)
    bend_x(b, 0.62)
    end = b.matrix_world @ b.data.vertices[1].co
    for k in (-1, 1):
        f = sphere(0.35, end, m=m)
        f.scale = (1, 0.45, 0.12)
        f.rotation_euler = (0, 0, math.radians(30 * k))
    root = group([o for o in bpy.context.scene.objects], 'root')
    root.rotation_euler = (math.radians(90), 0, 0)
    render('food_shrimp', yaw=math.radians(-5), elev=math.radians(25))


@asset
def steak():
    reset(256)
    m = mat('steak', (0.45, 0.06, 0.03), rough=0.55, coat=0.3)
    color_tex(m, (0.35, 0.05, 0.02), (0.85, 0.55, 0.4), scale=6, lo=0.62, hi=0.72, distortion=2.5)
    bump(m, 12, 0.35)
    s = cyl(1, 0.42, m=m, verts=48)
    for v in s.data.vertices:
        a = math.atan2(v.co.y, v.co.x)
        k = 1 + 0.15 * math.sin(2 * a) + 0.08 * math.cos(3 * a)
        v.co.x *= 1.35 * k
        v.co.y *= 0.95 * k
    bev(s, 0.15, 5)
    smooth(s)
    fat = cyl(1, 0.4, m=mat('fat', (0.95, 0.88, 0.75), rough=0.5, sss=0.3), verts=48, loc=(0, 0, -0.01))
    for v in fat.data.vertices:
        a = math.atan2(v.co.y, v.co.x)
        k = 1 + 0.15 * math.sin(2 * a) + 0.08 * math.cos(3 * a)
        v.co.x *= 1.42 * k
        v.co.y *= 1.02 * k
    bev(fat, 0.15, 5)
    smooth(fat)
    bone = cube((0.15, 1.6, 0.4), (0.1, 0, 0.0), m=mat('bone', (0.95, 0.9, 0.8), rough=0.5), bevel=0.06)
    # grill marks
    gm = mat('grill', (0.08, 0.03, 0.02), rough=0.7)
    for k in range(-2, 3):
        g = cube((1.5 - abs(k) * 0.3, 0.06, 0.02), (k * 0.45, 0, 0.22), m=gm, rot=(0, 0, math.radians(35)))
    render('food_steak', yaw=math.radians(-5), elev=math.radians(45))


@asset
def chicken():
    reset(256)
    m = mat('chick', (0.75, 0.38, 0.1), rough=0.3, coat=0.7, sss=0.2)
    color_tex(m, (0.5, 0.2, 0.05), (0.95, 0.6, 0.2), scale=5, lo=0.35, hi=0.65)
    bump(m, 25, 0.3)
    prof = [(0.0, -1.0), (0.55, -0.9), (0.85, -0.55), (0.9, -0.1), (0.75, 0.3), (0.45, 0.7), (0.22, 1.0),
            (0.16, 1.2), (0.0, 1.21)]
    d = revolve(prof, m)
    subsurf(d, 2)
    bm_ = mat('bone', (0.96, 0.92, 0.82), rough=0.4)
    cyl(0.12, 0.9, (0, 0, 1.5), m=bm_)
    for k in (-1, 1):
        sphere(0.17, (0.12 * k, 0, 1.95), m=bm_)
    root = group([o for o in bpy.context.scene.objects], 'root')
    root.rotation_euler = (0, math.radians(-55), 0)
    render('food_chicken', yaw=math.radians(-5), elev=math.radians(25))


# ---------------------------------------------------------------- coins, chips
@asset
def coin():
    reset(256)
    g = gold('coin', 0.22)
    c = cyl(1, 0.18, m=g, verts=96)
    bev(c, 0.05, 4)
    smooth(c)
    rim = torus(0.88, 0.04, (0, 0, 0.09), m=g)
    t = text('A', size=1.0, extrude=0.03, bevel=0.01, m=g, loc=(0, 0, 0.09))
    root = group([c, rim, t])
    root.rotation_euler = (math.radians(60), 0, math.radians(10))
    render('coin', yaw=math.radians(-10), elev=math.radians(25))


CHIPS = {'10k': (1.0, 0.5, 0.03), '50k': (0.9, 0.08, 0.08), '100k': (0.05, 0.35, 0.9),
         '500k': (0.08, 0.6, 0.2), '1m': (0.05, 0.05, 0.06), '5m': (0.55, 0.1, 0.8)}


@asset
def chips():
    for name, col in CHIPS.items():
        reset(256)
        m = mat('chip', col, rough=0.35, coat=0.6)
        # white edge inserts via wave texture around object coords
        nt = m.node_tree
        p = nt.nodes['Principled BSDF']
        tc = nt.nodes.new('ShaderNodeTexCoord')
        sep = nt.nodes.new('ShaderNodeSeparateXYZ')
        at = nt.nodes.new('ShaderNodeMath')
        at.operation = 'ARCTAN2'
        nt.links.new(tc.outputs['Object'], sep.inputs[0])
        nt.links.new(sep.outputs['Y'], at.inputs[0])
        nt.links.new(sep.outputs['X'], at.inputs[1])
        mul = nt.nodes.new('ShaderNodeMath')
        mul.operation = 'MULTIPLY'
        mul.inputs[1].default_value = 6 / math.pi * 0.5 * 2
        nt.links.new(at.outputs[0], mul.inputs[0])
        fr = nt.nodes.new('ShaderNodeMath')
        fr.operation = 'FRACT'
        nt.links.new(mul.outputs[0], fr.inputs[0])
        # radial distance to keep the face centre plain
        ln = nt.nodes.new('ShaderNodeVectorMath')
        ln.operation = 'LENGTH'
        nt.links.new(tc.outputs['Object'], ln.inputs[0])
        g1 = nt.nodes.new('ShaderNodeMath')
        g1.operation = 'GREATER_THAN'
        g1.inputs[1].default_value = 0.72
        nt.links.new(ln.outputs['Value'], g1.inputs[0])
        g2 = nt.nodes.new('ShaderNodeMath')
        g2.operation = 'LESS_THAN'
        g2.inputs[1].default_value = 0.35
        nt.links.new(fr.outputs[0], g2.inputs[0])
        both = nt.nodes.new('ShaderNodeMath')
        both.operation = 'MULTIPLY'
        nt.links.new(g1.outputs[0], both.inputs[0])
        nt.links.new(g2.outputs[0], both.inputs[1])
        mix = nt.nodes.new('ShaderNodeMix')
        mix.data_type = 'RGBA'
        mix.inputs['A'].default_value = (*col, 1)
        mix.inputs['B'].default_value = (0.97, 0.97, 0.95, 1)
        nt.links.new(both.outputs[0], mix.inputs['Factor'])
        nt.links.new(mix.outputs['Result'], p.inputs['Base Color'])
        c = cyl(1, 0.2, m=m, verts=96)
        bev(c, 0.05, 4)
        smooth(c)
        inner = cyl(0.62, 0.21, m=mat('in', (0.97, 0.96, 0.92), rough=0.3, coat=0.5), verts=96)
        ring = torus(0.62, 0.02, (0, 0, 0.105), m=gold())
        ring2 = torus(0.62, 0.02, (0, 0, -0.105), m=gold())
        root = group([c, inner, ring, ring2])
        root.rotation_euler = (math.radians(12), 0, 0)
        render(f'chip_{name}', yaw=0, elev=math.radians(62))


# ---------------------------------------------------------------- wheel
WHEEL_COLS = [(0.85, 0.05, 0.1), (0.05, 0.05, 0.08), (0.95, 0.6, 0.05), (0.08, 0.2, 0.8),
              (0.85, 0.05, 0.1), (0.05, 0.5, 0.2), (0.95, 0.6, 0.05), (0.45, 0.05, 0.6)]


@asset
def wheel():
    reset(900, samples=64)
    n = 16
    root_objs = []
    for i in range(n):
        m = mat(f's{i}', WHEEL_COLS[i % 8], rough=0.3, coat=0.8)
        me = bpy.data.meshes.new('seg')
        bm = bmesh.new()
        a0 = math.pi / 2 - (i + 0.5) * 2 * math.pi / n
        a1 = a0 + 2 * math.pi / n
        top_c = bm.verts.new((0, 0, 0.1))
        bot_c = bm.verts.new((0, 0, 0))
        tops, bots = [], []
        for k in range(9):
            a = a0 + (a1 - a0) * k / 8
            tops.append(bm.verts.new((4 * math.cos(a), 4 * math.sin(a), 0.1)))
            bots.append(bm.verts.new((4 * math.cos(a), 4 * math.sin(a), 0)))
        for k in range(8):
            bm.faces.new((top_c, tops[k], tops[k + 1]))
            bm.faces.new((bot_c, bots[k + 1], bots[k]))
            bm.faces.new((tops[k], bots[k], bots[k + 1], tops[k + 1]))
        bm.to_mesh(me)
        bm.free()
        o = link(bpy.data.objects.new('seg', me))
        give(o, m)
        # gold divider
        a = a0
        cube((4, 0.06, 0.06), (2 * math.cos(a), 2 * math.sin(a), 0.13), m=gold(), rot=(0, 0, a), bevel=0.02)
    rim = torus(4.15, 0.28, (0, 0, 0.1), m=gold('rim', 0.15), maj=128)
    bulb = mat('bulb', (1, 0.95, 0.7), emit=(1, 0.85, 0.5), emit_str=6, rough=0.1)
    for k in range(32):
        a = k * 2 * math.pi / 32
        sphere(0.11, (4.15 * math.cos(a), 4.15 * math.sin(a), 0.42), seg=16, rings=8, m=bulb)
    hub = sphere(0.65, (0, 0, 0.1), m=gold('hub', 0.1))
    hub.scale = (1, 1, 0.45)
    render('wheel', view='top', ortho=9.2)


@asset
def pointer():
    reset(256)
    m = mat('ptr', (0.85, 0.02, 0.05), rough=0.15, coat=1)
    me = bpy.data.meshes.new('p')
    bm = bmesh.new()
    pts = [(0, -1.2), (0.6, 0.3), (0.45, 0.75), (0, 1.0), (-0.45, 0.75), (-0.6, 0.3)]
    top = [bm.verts.new((x, y, 0.2)) for x, y in pts]
    bot = [bm.verts.new((x, y, -0.2)) for x, y in pts]
    bm.faces.new(top)
    bm.faces.new(list(reversed(bot)))
    for i in range(len(pts)):
        j = (i + 1) % len(pts)
        bm.faces.new((top[i], bot[i], bot[j], top[j]))
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = link(bpy.data.objects.new('ptr', me))
    give(o, m)
    bev(o, 0.08, 4)
    smooth(o)
    torus(0.55, 0.08, (0, 0.45, 0.2), m=gold())
    sphere(0.2, (0, 0.45, 0.25), m=gold())
    render('wheel_pointer', view='top', ortho=2.6)


# ---------------------------------------------------------------- rocket
@asset
def rocket():
    reset(320)
    white = mat('w', (0.92, 0.92, 0.95), rough=0.2, coat=0.6, metal=0.2)
    red = mat('r', (0.85, 0.05, 0.08), rough=0.15, coat=1)
    prof = [(0.0, -1.5), (0.45, -1.5), (0.55, -1.2), (0.6, -0.3), (0.58, 0.4), (0.5, 0.9), (0.0, 1.0)]
    revolve(prof, white)
    nose = [(0.5, 0.88), (0.42, 1.2), (0.28, 1.55), (0.12, 1.8), (0.0, 1.88)]
    revolve(nose, red)
    for k in range(3):
        a = k * 2 * math.pi / 3
        f = cube((0.08, 0.6, 0.8), (0.75 * math.cos(a), 0.75 * math.sin(a), -1.15), m=red, bevel=0.03,
                 rot=(0, 0, a + math.pi / 2))
        f.rotation_euler = (math.radians(-10), 0, a + math.pi / 2)
    win = mat('win', (0.2, 0.6, 1.0), rough=0.02, coat=1, metal=0.3)
    s = sphere(0.24, (0, -0.48, 0.3), m=win)
    s.scale = (1, 0.4, 1)
    torus(0.26, 0.05, (0, -0.55, 0.3), m=gold(), rot=(math.radians(90), 0, 0))
    noz = cone(0.38, 0.25, 0.3, (0, 0, -1.65), m=mat('n', (0.3, 0.3, 0.32), metal=1, rough=0.3))
    root = group([o for o in bpy.context.scene.objects], 'root')
    root.rotation_euler = (0, math.radians(45), 0)
    render('rocket', yaw=0, elev=math.radians(8))


@asset
def flame():
    reset(256)
    m = bpy.data.materials.new('fl')
    m.use_nodes = True
    nt = m.node_tree
    nt.nodes.remove(nt.nodes['Principled BSDF'])
    em = nt.nodes.new('ShaderNodeEmission')
    em.inputs['Color'].default_value = (1, 0.45, 0.08, 1)
    em.inputs['Strength'].default_value = 12
    nt.links.new(em.outputs[0], nt.nodes['Material Output'].inputs[0])
    c = cone(0.5, 0, 2.2, m=m, rot=(math.radians(180), 0, 0))
    subsurf(c, 2)
    smooth(c)
    m2 = mat('core', (1, 1, 0.8), emit=(1, 0.95, 0.7), emit_str=25)
    c2 = cone(0.25, 0, 1.2, (0, 0, 0.4), m=m2, rot=(math.radians(180), 0, 0))
    render('flame', yaw=0, elev=0.05)


# ---------------------------------------------------------------- party pieces
@asset
def bottle():
    reset(600, samples=96)
    g = mat('bottle', (0.05, 0.6, 0.15), rough=0.03, trans=1.0, ior=1.5)
    prof = [(0.0, -2.0), (0.62, -2.0), (0.68, -1.9), (0.7, 0.4), (0.62, 0.8), (0.35, 1.3), (0.24, 1.6),
            (0.24, 2.3), (0.29, 2.35), (0.29, 2.5), (0.2, 2.55), (0.2, 2.5)]
    b = revolve(prof, g)
    sol = b.modifiers.new('s', 'SOLIDIFY')
    sol.thickness = 0.05
    lab = cyl(0.715, 1.3, (0, 0, -0.7), m=mat('lab', (0.95, 0.85, 0.55), rough=0.6), verts=96)
    gm = gold()
    cap = cyl(0.31, 0.2, (0, 0, 2.45), m=gm, verts=48)
    root = group([b, lab, cap])
    root.rotation_euler = (0, math.radians(90), 0)
    floor = bpy.ops.mesh.primitive_plane_add(size=40, location=(0, 0, -0.72))
    p = bpy.context.object
    p.is_shadow_catcher = True
    p['nobounds'] = True
    render('bottle', view='top', ortho=5.6)


@asset
def luckybag():
    reset(320)
    m = mat('velvet', (0.75, 0.02, 0.06), rough=0.55, sheen=1.0)
    bump(m, 40, 0.15)
    prof = []
    for i in range(41):
        t = i / 40
        z = -1.0 + 2.4 * t
        if t < 0.6:
            r = math.sin(math.pi * (0.08 + t / 0.6 * 0.92)) * 1.05 if t > 0.0 else 0
            r = 1.05 * math.sin(math.pi * 0.5 * min(1, t / 0.18)) if t < 0.18 else 1.05 - (t - 0.18) * 1.6
        elif t < 0.72:
            r = 0.38 - (t - 0.6) * 1.2
        else:
            r = 0.25 + (t - 0.72) * 1.8
        prof.append((max(0.0, r), z))
    prof[-1] = (prof[-1][0], prof[-1][1])
    b = revolve(prof, m)
    sol = b.modifiers.new('s', 'SOLIDIFY')
    sol.thickness = 0.04
    subsurf(b, 1)
    for v in b.data.vertices:
        if v.co.z > 0.5:
            a = math.atan2(v.co.y, v.co.x)
            k = 1 + 0.18 * math.sin(9 * a) * (v.co.z - 0.5)
            v.co.x *= k
            v.co.y *= k
    rope = torus(0.3, 0.07, (0, 0, 0.47), m=gold('rope', 0.3))
    t = text('福', size=0.6) if False else None
    medal = cyl(0.38, 0.06, (0, -0.95, -0.1), m=gold('md', 0.15), rot=(math.radians(90), 0, 0))
    bev(medal, 0.02)
    tx = text('$', size=0.5, extrude=0.03, bevel=0.01, m=mat('rd', (0.7, 0.02, 0.05), rough=0.2, coat=1),
              loc=(0, -0.99, -0.1), rot=(math.radians(90), 0, 0))
    render('luckybag', yaw=math.radians(-12), elev=math.radians(18), floor=True)


LUDO = {'red': (0.85, 0.04, 0.06), 'green': (0.05, 0.6, 0.15), 'yellow': (0.98, 0.75, 0.02),
        'blue': (0.05, 0.3, 0.9)}


@asset
def pawns():
    for name, col in LUDO.items():
        reset(256)
        m = mat(name, col, rough=0.12, coat=1.0)
        prof = [(0.0, 0.0), (0.7, 0.0), (0.72, 0.08), (0.68, 0.18), (0.45, 0.3), (0.3, 0.6), (0.24, 1.0),
                (0.32, 1.1), (0.22, 1.18), (0.0, 1.18)]
        revolve(prof, m)
        sphere(0.36, (0, 0, 1.42), m=m)
        render(f'pawn_{name}', yaw=math.radians(-10), elev=math.radians(35), floor=True)


# 15x15 classic board. red top-left, green top-right, yellow bottom-right, blue bottom-left.
def ludo_cells():
    """Return dict (col,row)->colour key for coloured path cells; row 0 is top."""
    col = {}
    # home columns
    for i in range(1, 6):
        col[(i, 7)] = 'red'
        col[(7, i)] = 'green'
        col[(14 - i, 7)] = 'yellow'
        col[(7, 14 - i)] = 'blue'
    # start squares
    col[(1, 6)] = 'red'
    col[(8, 1)] = 'green'
    col[(13, 8)] = 'yellow'
    col[(6, 13)] = 'blue'
    return col


@asset
def ludo_board():
    reset(1024, samples=48)
    wood = mat('wood', (0.45, 0.25, 0.1), rough=0.35, coat=0.6)
    color_tex(wood, (0.35, 0.18, 0.06), (0.6, 0.35, 0.15), scale=3, kind='wave', coord='Object',
              wave_dir='X', distortion=8, lo=0.3, hi=0.7)
    base = cube((16, 16, 0.5), (0, 0, -0.3), m=wood, bevel=0.15)
    white = mat('white', (0.95, 0.94, 0.9), rough=0.35, coat=0.4)
    mats = {k: mat(k, c, rough=0.3, coat=0.6) for k, c in LUDO.items()}
    colored = ludo_cells()
    def cell_xy(c, r):
        return (c - 7, 7 - r)
    # yards
    yards = {'red': (0, 0), 'green': (9, 0), 'yellow': (9, 9), 'blue': (0, 9)}
    for k, (c0, r0) in yards.items():
        x, y = cell_xy(c0 + 2.5, r0 + 2.5)
        cube((5.85, 5.85, 0.2), (x, y, 0), m=mats[k], bevel=0.08)
        cube((3.9, 3.9, 0.06), (x, y, 0.13), m=white, bevel=0.05)
        for dx, dy in ((-0.9, -0.9), (0.9, -0.9), (-0.9, 0.9), (0.9, 0.9)):
            c = cyl(0.55, 0.06, (x + dx, y + dy, 0.17), m=mats[k], verts=48)
            bev(c, 0.02)
    # track cells
    for c in range(15):
        for r in range(15):
            inyard = (c < 6 or c > 8) and (r < 6 or r > 8)
            centre = 6 <= c <= 8 and 6 <= r <= 8
            if inyard or centre:
                continue
            x, y = cell_xy(c, r)
            k = colored.get((c, r))
            cube((0.92, 0.92, 0.18), (x, y, 0), m=mats[k] if k else white, bevel=0.06, seg=3)
    # safe stars
    stm = gold('st', 0.2)
    for (c, r) in ((2, 8), (6, 2), (12, 6), (8, 12)):
        x, y = cell_xy(c, r)
        s = star_mesh(stm, 0.05)
        s.scale = (0.33, 0.33, 1)
        s.location = (x, y, 0.12)
    # centre triangles
    tri = {'red': [(-1.5, 1.5), (-1.5, -1.5)], 'green': [(-1.5, 1.5), (1.5, 1.5)],
           'yellow': [(1.5, 1.5), (1.5, -1.5)], 'blue': [(1.5, -1.5), (-1.5, -1.5)]}
    for k, ((x1, y1), (x2, y2)) in tri.items():
        me = bpy.data.meshes.new('tri')
        bm = bmesh.new()
        vs = [bm.verts.new((0, 0, 0.35)), bm.verts.new((x1, y1, 0.09)), bm.verts.new((x2, y2, 0.09))]
        bm.faces.new(vs)
        bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
        bm.to_mesh(me)
        bm.free()
        o = link(bpy.data.objects.new('tri', me))
        give(o, mats[k])
        if o.data.polygons[0].normal.z < 0:
            o.data.flip_normals()
    render('ludo_board', view='top', ortho=16.0)


@asset
def xo():
    reset(256)
    m = mat('x', (0.95, 0.15, 0.25), rough=0.12, coat=1, sss=0.1)
    for a in (45, -45):
        cube((2.2, 0.5, 0.45), m=m, bevel=0.2, seg=6, rot=(0, 0, math.radians(a)))
    render('piece_x', view='34', yaw=0, elev=math.radians(70), floor=True)
    reset(256)
    m = mat('o', (0.1, 0.6, 1.0), rough=0.12, coat=1, sss=0.1)
    o = torus(0.75, 0.24, m=m)
    o.scale = (1, 1, 0.95)
    render('piece_o', view='34', yaw=0, elev=math.radians(70), floor=True)


@asset
def tttboard():
    reset(640, samples=48)
    wood = mat('wood', (0.3, 0.15, 0.06), rough=0.3, coat=0.7)
    color_tex(wood, (0.22, 0.1, 0.04), (0.45, 0.24, 0.1), scale=2.5, kind='wave', coord='Object',
              wave_dir='X', distortion=7, lo=0.3, hi=0.7)
    cube((6.4, 6.4, 0.4), (0, 0, -0.2), m=wood, bevel=0.2, seg=6)
    gm = gold('g', 0.2)
    for k in (-1, 1):
        cube((0.12, 6.0, 0.08), (k * 1.0, 0, 0.03), m=gm, bevel=0.03)
        cube((6.0, 0.12, 0.08), (0, k * 1.0, 0.03), m=gm, bevel=0.03)
    render('ttt_board', view='top', ortho=6.6)


@asset
def rps():
    reset(256)
    m = mat('rock', (0.45, 0.43, 0.4), rough=0.8)
    color_tex(m, (0.3, 0.28, 0.26), (0.62, 0.6, 0.56), scale=6, lo=0.35, hi=0.7)
    bump(m, 8, 0.8)
    r = ico(1, sub=5, m=m)
    md = r.modifiers.new('d', 'DISPLACE')
    tx = bpy.data.textures.new('n', 'CLOUDS')
    tx.noise_scale = 0.8
    md.texture = tx
    md.strength = 0.35
    r.scale = (1.2, 1, 0.8)
    render('rps_rock', yaw=math.radians(-10), elev=math.radians(30), floor=True)

    reset(256)
    pm = mat('paper', (0.97, 0.97, 0.94), rough=0.7, sss=0.2)
    lines = color_tex(pm, (0.55, 0.7, 0.95), (0.97, 0.97, 0.94), scale=9, kind='wave', coord='Object',
                      wave_dir='Y', lo=0.0, hi=0.12)
    bpy.ops.mesh.primitive_grid_add(x_subdivisions=30, y_subdivisions=40, size=2)
    p = bpy.context.object
    p.scale = (1.0, 1.35, 1)
    bpy.ops.object.transform_apply(scale=True)
    for v in p.data.vertices:
        v.co.z = 0.12 * math.sin(v.co.x * 2.2) + 0.25 * max(0, v.co.y - 0.8) ** 2
    sol = p.modifiers.new('s', 'SOLIDIFY')
    sol.thickness = 0.015
    smooth(p)
    give(p, pm)
    p.rotation_euler = (math.radians(15), 0, math.radians(-15))
    render('rps_paper', yaw=math.radians(-10), elev=math.radians(45), floor=True)

    reset(256)
    steel = mat('steel', (0.85, 0.86, 0.9), rough=0.12, metal=1)
    handle = mat('h', (0.9, 0.1, 0.15), rough=0.25, coat=1)
    parts = []
    for k, ang in ((1, 14), (-1, -14)):
        blade = cube((2.4, 0.26, 0.05), (1.1, 0, 0.03 * k), m=steel, bevel=0.03)
        for v in blade.data.vertices:
            if v.co.x > 0:
                v.co.y *= max(0.15, 1 - v.co.x / 1.6)
        ring = torus(0.45, 0.12, (-0.65, 0, 0.03 * k), m=handle)
        ring.scale = (1.25, 1, 1)
        g = group([blade, ring])
        g.rotation_euler = (0, 0, math.radians(ang))
        g.location = (0, -0.0, 0)
        # offset rings to opposite sides
        ring.location.y = -0.35 * k
    sphere(0.1, (0, 0, 0.08), m=steel)
    render('rps_scissors', view='34', yaw=0, elev=math.radians(70), floor=True)


@asset
def vs():
    reset(320)
    red = mat('r', (0.9, 0.05, 0.1), rough=0.15, coat=1)
    blue = mat('b', (0.05, 0.35, 1.0), rough=0.15, coat=1)
    text('V', size=2.2, extrude=0.25, bevel=0.06, m=red, loc=(-0.65, 0, 0), rot=(math.radians(90), 0, 0))
    text('S', size=2.2, extrude=0.25, bevel=0.06, m=blue, loc=(0.75, 0, -0.1), rot=(math.radians(90), 0, 0))
    text('V', size=2.2, extrude=0.18, bevel=0.12, m=gold(), loc=(-0.65, 0.06, 0), rot=(math.radians(90), 0, 0))
    text('S', size=2.2, extrude=0.18, bevel=0.12, m=gold(), loc=(0.75, 0.06, -0.1), rot=(math.radians(90), 0, 0))
    render('vs', yaw=math.radians(-12), elev=math.radians(14))


@asset
def treasure():
    """Lucky-bag coins pile for the reveal."""
    reset(320)
    g = gold('c', 0.22)
    rnd = random.Random(4)
    for i in range(26):
        c = cyl(0.5, 0.08, (rnd.uniform(-1, 1), rnd.uniform(-0.7, 0.7), 0), m=g, verts=48)
        c.location.z = 0.6 - (abs(c.location.x) + abs(c.location.y)) * 0.35 + rnd.uniform(0, 0.1)
        c.rotation_euler = (rnd.uniform(-0.5, 0.5), rnd.uniform(-0.5, 0.5), 0)
        bev(c, 0.02)
    render('coins_pile', yaw=math.radians(-10), elev=math.radians(35), floor=True)


@asset
def bomb():
    reset(256)
    m = mat('bomb', (0.02, 0.02, 0.025), rough=0.2, coat=0.8)
    sphere(1, m=m)
    cap = cyl(0.32, 0.3, (0, 0, 1.0), m=mat('cap', (0.3, 0.3, 0.32), metal=1, rough=0.3))
    stem([(0, 0, 1.1), (0.15, 0, 1.45), (0.45, 0, 1.6)], 0.05, mat('fuse', (0.6, 0.5, 0.3), rough=0.8))
    spark = mat('spark', (1, 0.8, 0.3), emit=(1, 0.6, 0.15), emit_str=30)
    sphere(0.12, (0.47, 0, 1.62), m=spark)
    rnd = random.Random(2)
    for i in range(10):
        a = rnd.uniform(0, 6.28)
        e = rnd.uniform(-0.8, 1.2)
        c = cyl(0.012, 0.35, (0.47 + 0.2 * math.cos(a) * math.cos(e), 0.2 * math.sin(a) * math.cos(e), 1.62 + 0.2 * math.sin(e)), m=spark)
        c.rotation_euler = (rnd.uniform(0, 3), rnd.uniform(0, 3), 0)
    render('bomb', yaw=math.radians(-15), elev=math.radians(20))


if __name__ == '__main__':
    names = sys.argv[sys.argv.index('--') + 1:] if '--' in sys.argv else list(A)
    for n in names:
        A[n]()
