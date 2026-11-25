"""Shared Blender helpers for rendering Adda game assets."""
import bpy, bmesh, math, os, random
from mathutils import Vector, Matrix, Euler

OUT = os.environ.get('OUT', '/home/claude/r3d/out')
SAMPLES = int(os.environ.get('SAMPLES', '64'))
FONT = None
for f in ('/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf',
          '/usr/share/fonts/opentype/inter/InterDisplay-Bold.otf'):
    if os.path.exists(f):
        FONT = f
        break


def reset(size=256, samples=None):
    bpy.ops.wm.read_factory_settings(use_empty=True)
    sc = bpy.context.scene
    sc.render.engine = 'CYCLES'
    sc.cycles.device = 'CPU'
    sc.cycles.samples = samples or SAMPLES
    sc.cycles.use_denoising = True
    sc.cycles.max_bounces = 12
    sc.cycles.transmission_bounces = 12
    sc.cycles.glossy_bounces = 6
    sc.render.film_transparent = True
    sc.render.resolution_x = sc.render.resolution_y = size
    sc.render.image_settings.file_format = 'PNG'
    sc.render.image_settings.color_mode = 'RGBA'
    sc.view_settings.view_transform = 'AgX'
    sc.view_settings.look = 'AgX - Punchy'
    w = bpy.data.worlds.new('w')
    sc.world = w
    w.use_nodes = True
    nt = w.node_tree
    bg = nt.nodes['Background']
    # soft studio gradient: brighter from above
    tc = nt.nodes.new('ShaderNodeTexCoord')
    sep = nt.nodes.new('ShaderNodeSeparateXYZ')
    ramp = nt.nodes.new('ShaderNodeValToRGB')
    ramp.color_ramp.elements[0].position = 0.35
    ramp.color_ramp.elements[0].color = (0.08, 0.07, 0.07, 1)
    ramp.color_ramp.elements[1].position = 0.75
    ramp.color_ramp.elements[1].color = (0.9, 0.88, 0.85, 1)
    mapr = nt.nodes.new('ShaderNodeMapRange')
    mapr.inputs['From Min'].default_value = -1
    nt.links.new(tc.outputs['Generated'], sep.inputs[0])
    nt.links.new(sep.outputs['Z'], mapr.inputs[0])
    nt.links.new(mapr.outputs[0], ramp.inputs[0])
    nt.links.new(ramp.outputs[0], bg.inputs[0])
    bg.inputs[1].default_value = 0.7
    return sc


def mat(name, color=(1, 1, 1), rough=0.4, metal=0.0, coat=0.0, trans=0.0, ior=1.45,
        emit=None, emit_str=0.0, sheen=0.0, sss=0.0, alpha=1.0, disp=0.0):
    m = bpy.data.materials.new(name)
    m.use_nodes = True
    p = m.node_tree.nodes['Principled BSDF']
    p.inputs['Base Color'].default_value = (*color, 1)
    p.inputs['Roughness'].default_value = rough
    p.inputs['Metallic'].default_value = metal
    p.inputs['Coat Weight'].default_value = coat
    p.inputs['Transmission Weight'].default_value = trans
    p.inputs['IOR'].default_value = ior
    p.inputs['Sheen Weight'].default_value = sheen
    p.inputs['Subsurface Weight'].default_value = sss
    if sss:
        p.inputs['Subsurface Radius'].default_value = (1.0, 0.4, 0.2)
        p.inputs['Subsurface Scale'].default_value = 0.08
    if alpha < 1:
        p.inputs['Alpha'].default_value = alpha
    if emit:
        p.inputs['Emission Color'].default_value = (*emit, 1)
        p.inputs['Emission Strength'].default_value = emit_str
    if disp and 'Dispersion' in p.inputs:
        p.inputs['Dispersion'].default_value = disp
    return m


def bump(m, scale=20.0, strength=0.3, kind='noise', detail=4.0, distance=0.05):
    nt = m.node_tree
    p = nt.nodes['Principled BSDF']
    if kind == 'voronoi':
        t = nt.nodes.new('ShaderNodeTexVoronoi')
        t.inputs['Scale'].default_value = scale
        out = t.outputs['Distance']
    elif kind == 'wave':
        t = nt.nodes.new('ShaderNodeTexWave')
        t.inputs['Scale'].default_value = scale
        out = t.outputs['Fac']
    else:
        t = nt.nodes.new('ShaderNodeTexNoise')
        t.inputs['Scale'].default_value = scale
        t.inputs['Detail'].default_value = detail
        out = t.outputs['Fac']
    b = nt.nodes.new('ShaderNodeBump')
    b.inputs['Strength'].default_value = strength
    b.inputs['Distance'].default_value = distance
    nt.links.new(out, b.inputs['Height'])
    nt.links.new(b.outputs['Normal'], p.inputs['Normal'])
    return t


def color_tex(m, c1, c2, scale=5.0, kind='noise', lo=0.4, hi=0.6, coord=None, wave_dir='X',
              distortion=0.0, mirror=False):
    """Mix two colours by a procedural texture into Base Color."""
    nt = m.node_tree
    p = nt.nodes['Principled BSDF']
    if kind == 'gradz':
        tc = nt.nodes.new('ShaderNodeTexCoord')
        sep = nt.nodes.new('ShaderNodeSeparateXYZ')
        nt.links.new(tc.outputs['Generated'], sep.inputs[0])
        src = sep.outputs['X' if mirror else 'Z']
        if mirror:
            mm = nt.nodes.new('ShaderNodeMath')
            mm.operation = 'PINGPONG'
            mm.inputs[1].default_value = 0.5
            nt.links.new(src, mm.inputs[0])
            src = mm.outputs[0]
        r = nt.nodes.new('ShaderNodeValToRGB')
        r.color_ramp.elements[0].position = lo
        r.color_ramp.elements[0].color = (*c1, 1)
        r.color_ramp.elements[1].position = hi
        r.color_ramp.elements[1].color = (*c2, 1)
        nt.links.new(src, r.inputs[0])
        nt.links.new(r.outputs[0], p.inputs['Base Color'])
        return r
    if kind == 'wave':
        t = nt.nodes.new('ShaderNodeTexWave')
        t.bands_direction = wave_dir
        t.inputs['Scale'].default_value = scale
        t.inputs['Distortion'].default_value = distortion
    elif kind == 'voronoi':
        t = nt.nodes.new('ShaderNodeTexVoronoi')
        t.inputs['Scale'].default_value = scale
    else:
        t = nt.nodes.new('ShaderNodeTexNoise')
        t.inputs['Scale'].default_value = scale
        t.inputs['Detail'].default_value = 6
        t.inputs['Distortion'].default_value = distortion
    if coord:
        tc = nt.nodes.new('ShaderNodeTexCoord')
        nt.links.new(tc.outputs[coord], t.inputs['Vector'])
    r = nt.nodes.new('ShaderNodeValToRGB')
    r.color_ramp.elements[0].position = lo
    r.color_ramp.elements[0].color = (*c1, 1)
    r.color_ramp.elements[1].position = hi
    r.color_ramp.elements[1].color = (*c2, 1)
    out = t.outputs['Fac'] if kind != 'voronoi' else t.outputs['Distance']
    nt.links.new(out, r.inputs[0])
    nt.links.new(r.outputs[0], p.inputs['Base Color'])
    return r


def link(o):
    bpy.context.scene.collection.objects.link(o)
    return o


def smooth(o, auto=None):
    for poly in o.data.polygons:
        poly.use_smooth = True
    return o


def give(o, m):
    o.data.materials.append(m)
    return o


def sphere(r=1, loc=(0, 0, 0), seg=48, rings=24, m=None):
    bpy.ops.mesh.primitive_uv_sphere_add(radius=r, location=loc, segments=seg, ring_count=rings)
    o = bpy.context.object
    smooth(o)
    if m:
        give(o, m)
    return o


def ico(r=1, loc=(0, 0, 0), sub=4, m=None):
    bpy.ops.mesh.primitive_ico_sphere_add(radius=r, location=loc, subdivisions=sub)
    o = bpy.context.object
    smooth(o)
    if m:
        give(o, m)
    return o


def cyl(r=1, depth=1, loc=(0, 0, 0), verts=64, m=None, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cylinder_add(radius=r, depth=depth, location=loc, vertices=verts, rotation=rot)
    o = bpy.context.object
    if m:
        give(o, m)
    return o


def cone(r1=1, r2=0, depth=1, loc=(0, 0, 0), verts=64, m=None, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cone_add(radius1=r1, radius2=r2, depth=depth, location=loc, vertices=verts, rotation=rot)
    o = bpy.context.object
    if m:
        give(o, m)
    return o


def cube(size=(1, 1, 1), loc=(0, 0, 0), m=None, bevel=0.0, seg=4, rot=(0, 0, 0)):
    bpy.ops.mesh.primitive_cube_add(size=1, location=loc, rotation=rot)
    o = bpy.context.object
    o.scale = size
    bpy.ops.object.transform_apply(scale=True)
    if bevel:
        bev(o, bevel, seg)
        smooth(o)
    if m:
        give(o, m)
    return o


def torus(R=1, r=0.25, loc=(0, 0, 0), m=None, rot=(0, 0, 0), maj=64, mino=24):
    bpy.ops.mesh.primitive_torus_add(major_radius=R, minor_radius=r, location=loc, rotation=rot,
                                     major_segments=maj, minor_segments=mino)
    o = bpy.context.object
    smooth(o)
    if m:
        give(o, m)
    return o


def bev(o, w, seg=4):
    md = o.modifiers.new('bev', 'BEVEL')
    md.width = w
    md.segments = seg
    md.limit_method = 'ANGLE'
    return md


def subsurf(o, lv=2):
    md = o.modifiers.new('ss', 'SUBSURF')
    md.levels = lv
    md.render_levels = lv
    return md


def apply_all(o):
    bpy.context.view_layer.objects.active = o
    for md in list(o.modifiers):
        bpy.ops.object.modifier_apply(modifier=md.name)


def text(body, size=1.0, extrude=0.1, bevel=0.02, m=None, loc=(0, 0, 0), rot=(0, 0, 0)):
    cu = bpy.data.curves.new('t', 'FONT')
    cu.body = body
    if FONT:
        cu.font = bpy.data.fonts.load(FONT)
    cu.size = size
    cu.extrude = extrude
    cu.bevel_depth = bevel
    cu.bevel_resolution = 4
    cu.align_x = 'CENTER'
    cu.align_y = 'CENTER'
    o = link(bpy.data.objects.new('t', cu))
    o.location = loc
    o.rotation_euler = rot
    if m:
        cu.materials.append(m)
    bpy.ops.object.select_all(action='DESELECT')
    o.select_set(True)
    bpy.context.view_layer.objects.active = o
    bpy.ops.object.convert(target='MESH')
    o = bpy.context.object
    smooth(o)
    return o


def revolve(profile, m=None, steps=96, loc=(0, 0, 0)):
    """profile: list of (r, z). Builds a lathe mesh around Z."""
    me = bpy.data.meshes.new('rev')
    bm = bmesh.new()
    rings = []
    for i in range(steps):
        a = 2 * math.pi * i / steps
        ring = [bm.verts.new((r * math.cos(a), r * math.sin(a), z)) for r, z in profile]
        rings.append(ring)
    for i in range(steps):
        a, b = rings[i], rings[(i + 1) % steps]
        for j in range(len(profile) - 1):
            try:
                bm.faces.new((a[j], b[j], b[j + 1], a[j + 1]))
            except ValueError:
                pass
    bmesh.ops.remove_doubles(bm, verts=bm.verts, dist=1e-5)
    bmesh.ops.recalc_face_normals(bm, faces=bm.faces)
    bm.to_mesh(me)
    bm.free()
    o = link(bpy.data.objects.new('rev', me))
    o.location = loc
    smooth(o)
    if m:
        give(o, m)
    return o


def join(objs, name='obj'):
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    for o in objs:
        if o.type == 'FONT':
            bpy.context.view_layer.objects.active = o
            bpy.ops.object.convert(target='MESH')
    bpy.ops.object.select_all(action='DESELECT')
    for o in objs:
        o.select_set(True)
    bpy.context.view_layer.objects.active = objs[0]
    bpy.ops.object.join()
    o = bpy.context.object
    o.name = name
    return o


def group(objs, name='grp'):
    e = link(bpy.data.objects.new(name, None))
    for o in objs:
        o.parent = e
    return e


def scene_bounds():
    dg = bpy.context.evaluated_depsgraph_get()
    pts = []
    for o in bpy.context.scene.objects:
        if o.type in ('MESH', 'FONT', 'CURVE') and not o.get('nobounds'):
            oe = o.evaluated_get(dg)
            pts += [oe.matrix_world @ Vector(c) for c in oe.bound_box]
    lo = Vector((min(p.x for p in pts), min(p.y for p in pts), min(p.z for p in pts)))
    hi = Vector((max(p.x for p in pts), max(p.y for p in pts), max(p.z for p in pts)))
    return lo, hi, pts


def lights(dirv, key=900, fill=300, rim=700, warm=True, scale=1.0):
    sc = bpy.context.scene
    fwd = dirv.normalized()
    side = fwd.cross(Vector((0, 0, 1))).normalized() if abs(fwd.z) < 0.99 else Vector((1, 0, 0))
    spots = [
        (-fwd * 6 + side * 4 + Vector((0, 0, 5)), key, (1.0, 0.96, 0.9) if warm else (1, 1, 1), 4),
        (-fwd * 6 - side * 5 + Vector((0, 0, 1)), fill, (0.85, 0.9, 1.0), 6),
        (fwd * 6 + Vector((0, 0, 4)), rim, (1, 1, 1), 3),
    ]
    for loc, e, col, size in spots:
        l = link(bpy.data.objects.new('L', bpy.data.lights.new('L', 'AREA')))
        l.data.energy = e * scale * scale
        l.data.color = col
        l.data.size = size * scale
        l.location = loc * scale
        l.rotation_euler = (-loc).to_track_quat('-Z', 'Y').to_euler()


def shadow_floor():
    lo, hi, _ = scene_bounds()
    bpy.ops.mesh.primitive_plane_add(size=60, location=(0, 0, lo.z))
    p = bpy.context.object
    p.is_shadow_catcher = True
    p['nobounds'] = True
    return p


def render(name, view='34', pad=1.08, yaw=0.0, elev=0.62, ortho=None, floor=False, light_scale=None):
    sc = bpy.context.scene
    if floor:
        shadow_floor()
    lo, hi, pts = scene_bounds()
    c = (lo + hi) / 2
    camd = bpy.data.cameras.new('cam')
    cam = link(bpy.data.objects.new('cam', camd))
    sc.camera = cam
    if view == 'top':
        camd.type = 'ORTHO'
        camd.ortho_scale = ortho or max(hi.x - lo.x, hi.y - lo.y) * pad
        cam.location = (c.x, c.y, hi.z + 20)
        cam.rotation_euler = (0, 0, 0)
        dirv = Vector((0.3, 0.6, -1))
        rad = camd.ortho_scale / 2
    else:
        camd.lens = 60
        d = Vector((math.sin(yaw) * math.cos(elev), -math.cos(yaw) * math.cos(elev), math.sin(elev)))
        dirv = -d
        # fit: project points onto camera plane
        rot = (-d).to_track_quat('-Z', 'Y')
        inv = rot.to_matrix().inverted()
        fov = 2 * math.atan(18 / camd.lens)
        dist = 1.0
        for p in pts:
            q = inv @ (p - c)
            need = max(abs(q.x), abs(q.y)) * pad / math.tan(fov / 2) + q.z
            dist = max(dist, need)
        cam.location = c + d * dist
        cam.rotation_euler = rot.to_euler()
        rad = (hi - lo).length / 2
    lights(dirv, scale=max(1.0, rad / 1.2) if light_scale is None else light_scale)
    os.makedirs(OUT, exist_ok=True)
    sc.render.filepath = os.path.join(OUT, name + '.png')
    bpy.ops.render.render(write_still=True)
    print('rendered', name)


def bend_x(o, R):
    """Bend a mesh lying along X (profile revolved around Z then laid down) around a circle of radius R."""
    for v in o.data.vertices:
        x, y, z = v.co
        th = x / R
        v.co = ((R - z) * math.sin(th), y, R - (R - z) * math.cos(th))


def lay_x(o):
    """Rotate geometry so the object's Z axis becomes X (applied)."""
    for v in o.data.vertices:
        x, y, z = v.co
        v.co = (z, y, -x)
