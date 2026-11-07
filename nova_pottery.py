bl_info = {
    "name": "NOVA Pottery Studio",
    "author": "NOVA",
    "version": (1, 0, 0),
    "blender": (5, 2, 0),
    "location": "3D Viewport > Sidebar > Pottery",
    "description": "Preview pottery shapes and GLB meshes with ceramic glazes",
    "category": "3D View",
}

from math import cos, sin, tau
from pathlib import Path

import bpy
import numpy as np
from bpy_extras.io_utils import ImportHelper
from mathutils import Matrix, Vector


# Each cross section runs from the underside, over the lip, and back down
# the interior. The first and last points close the surface at the axis.
SHAPES = {
    "BOWL": ("Serving Bowl", (
        (0, 0), (.33, 0), (.41, .015), (.43, .075), (.57, .13),
        (.76, .24), (.95, .44), (1.08, .70), (1.09, .77),
        (1.06, .80), (1.02, .78), (1.00, .71), (.90, .49),
        (.73, .30), (.52, .19), (.29, .15), (0, .15),
    )),
    "VASE": ("Bud Vase", (
        (0, 0), (.34, 0), (.44, .02), (.49, .08), (.60, .24),
        (.68, .49), (.66, .74), (.56, .98), (.39, 1.20),
        (.27, 1.43), (.26, 1.64), (.30, 1.77), (.31, 1.82),
        (.28, 1.85), (.23, 1.83), (.22, 1.78), (.19, 1.64),
        (.20, 1.41), (.32, 1.17), (.50, .94), (.59, .72),
        (.61, .49), (.53, .28), (.39, .14), (.21, .12), (0, .12),
    )),
    "CUP": ("Tea Cup", (
        (0, 0), (.36, 0), (.43, .02), (.46, .10), (.57, .15),
        (.63, .31), (.67, .58), (.70, .85), (.69, .92),
        (.65, .94), (.61, .92), (.61, .85), (.59, .60),
        (.55, .34), (.49, .22), (.34, .16), (0, .16),
    )),
}

# Colors are in Blender's scene-linear space.
GLAZES = {
    "CELADON": ("Jade Celadon", "Glossy green with soft color variation",
                (.070, .20, .13), (.19, .36, .25), .23, .36),
    "COBALT": ("Cobalt Blue", "Deep glossy blue with tonal variation",
               (.009, .024, .11), (.048, .15, .37), .19, .40),
    "OATMEAL": ("Speckled Oatmeal", "Warm satin glaze with iron speckles",
                (.40, .27, .15), (.78, .64, .45), .37, .16),
}

IMPORT_DATA = (
    "objects", "collections", "meshes", "materials", "images", "textures",
    "node_groups", "armatures", "cameras", "lights", "actions", "shape_keys",
    "pointclouds", "scenes",
)


def glaze_material(key, custom_color_srgb="#C84B32"):
    if key == "CUSTOM":
        if not isinstance(custom_color_srgb, str) or len(custom_color_srgb) != 7 or custom_color_srgb[0] != "#":
            raise ValueError("Custom glaze color must use #RRGGBB format.")
        try:
            channels = [int(custom_color_srgb[index:index + 2], 16) / 255 for index in (1, 3, 5)]
        except ValueError as error:
            raise ValueError("Custom glaze color must use #RRGGBB format.") from error
        linear = [channel / 12.92 if channel <= .04045 else ((channel + .055) / 1.055) ** 2.4 for channel in channels]
        dark = tuple(channel * .58 for channel in linear)
        light = tuple(linear)
        roughness, coat = .23, .36
        label = f"Custom Glaze {custom_color_srgb.upper()}"
        cache_key = f"CUSTOM:{custom_color_srgb.upper()}"
    else:
        label, _, dark, light, roughness, coat = GLAZES[key]
        cache_key = key

    # Blender's ID collection lookup is name-indexed; use it before scanning
    # every material datablock on each glaze change.
    material = bpy.data.materials.get(label)
    if material and material.get("nova_glaze") == cache_key:
        return material

    for material in bpy.data.materials:
        if material.get("nova_glaze") == cache_key:
            return material

    material = bpy.data.materials.new(label)
    material["nova_glaze"] = cache_key
    material.diffuse_color = (*light, 1)
    nodes = material.node_tree.nodes
    link = material.node_tree.links.new
    shader = nodes.get("Principled BSDF")
    shader.location = (480, 100)
    nodes.get("Material Output").location = (790, 100)
    shader.inputs["Roughness"].default_value = roughness
    shader.inputs["Coat Weight"].default_value = coat
    shader.inputs["Coat Roughness"].default_value = .18

    coords = nodes.new("ShaderNodeNewGeometry")
    coords.location = (-780, 100)
    tone = nodes.new("ShaderNodeTexNoise")
    tone.label = "Glaze color variation"
    tone.location = (-540, 280)
    tone.inputs["Scale"].default_value = 6
    link(coords.outputs["Position"], tone.inputs["Vector"])
    palette = nodes.new("ShaderNodeValToRGB")
    palette.location = (-280, 280)
    palette.color_ramp.elements[0].position = .20
    palette.color_ramp.elements[0].color = (*dark, 1)
    palette.color_ramp.elements[1].position = .80
    palette.color_ramp.elements[1].color = (*light, 1)
    link(tone.outputs["Fac"], palette.inputs["Fac"])
    color = palette.outputs["Color"]

    grain = nodes.new("ShaderNodeTexNoise")
    grain.label = "Fired glaze surface"
    grain.location = (-540, -80)
    grain.inputs["Scale"].default_value = 175
    grain.inputs["Detail"].default_value = 1
    link(coords.outputs["Position"], grain.inputs["Vector"])
    bump = nodes.new("ShaderNodeBump")
    bump.location = (230, -180)
    bump.inputs["Strength"].default_value = .15
    bump.inputs["Distance"].default_value = .005
    link(grain.outputs["Fac"], bump.inputs["Height"])
    link(bump.outputs["Normal"], shader.inputs["Normal"])

    if key == "OATMEAL":
        flecks = nodes.new("ShaderNodeValToRGB")
        flecks.label = "Iron speckle mask"
        flecks.location = (-280, -30)
        flecks.color_ramp.elements[0].position = .69
        flecks.color_ramp.elements[1].position = .75
        link(grain.outputs["Fac"], flecks.inputs["Fac"])
        mix = nodes.new("ShaderNodeMixRGB")
        mix.location = (0, 200)
        mix.inputs[2].default_value = (.055, .029, .016, 1)
        link(flecks.outputs["Color"], mix.inputs[0])
        link(color, mix.inputs[1])
        color = mix.outputs[0]

    link(color, shader.inputs["Base Color"])
    return material


def apply_glaze(mesh, material):
    mesh.materials.clear()
    mesh.materials.append(material)


def update_glaze(settings, _context):
    if settings.model_collection and settings.model_collection.objects:
        material = glaze_material(settings.glaze, settings.custom_color_srgb)
        for obj in settings.model_collection.objects:
            apply_glaze(obj.data, material)


def mesh_object(name, vertices, faces):
    mesh = bpy.data.meshes.new(name)
    mesh.from_pydata(vertices, [], faces)
    mesh.update()
    return bpy.data.objects.new(name, mesh)


def pottery_shape(key):
    name, profile = SHAPES[key]
    steps = 96
    vertices = [(0, 0, profile[0][1])]
    for radius, height in profile[1:-1]:
        vertices.extend((radius * cos(tau * i / steps),
                         radius * sin(tau * i / steps), height)
                        for i in range(steps))
    top = len(vertices)
    vertices.append((0, 0, profile[-1][1]))
    faces = []
    for i in range(steps):
        next_i = (i + 1) % steps
        faces.append((0, 1 + next_i, 1 + i))
        for start in range(1, top - steps, steps):
            faces.append((start + i, start + next_i,
                          start + steps + next_i, start + steps + i))
        faces.append((top - steps + i, top - steps + next_i, top))
    obj = mesh_object(name, vertices, faces)
    obj.data.polygons.foreach_set("use_smooth", [True] * len(faces))
    smooth = obj.modifiers.new("Wheel-thrown curves", 'SUBSURF')
    smooth.levels = 2
    smooth.render_levels = 2
    return obj


def remove_model(objects):
    meshes = {obj.data for obj in objects}
    for obj in objects:
        bpy.data.objects.remove(obj, do_unlink=True)
    for mesh in meshes:
        if mesh.users == 0:
            bpy.data.meshes.remove(mesh)


def read_glb(context, filepath):
    if Path(filepath).suffix.lower() != ".glb" or not Path(filepath).is_file():
        raise ValueError("Choose an existing .glb file.")

    # Import into a temporary scene so source cameras, lights, animations,
    # and collections cannot change the studio or the user's other scenes.
    before = {kind: set(getattr(bpy.data, kind)) for kind in IMPORT_DATA}
    scratch = bpy.data.scenes.new("NOVA GLB Import")
    imported_data = set()
    objects = []
    try:
        with context.temp_override(scene=scratch, view_layer=scratch.view_layers[0]):
            try:
                result = bpy.ops.import_scene.gltf(filepath=filepath)
            finally:
                for kind, existing in before.items():
                    imported_data.update(set(getattr(bpy.data, kind)) - existing)
            if 'FINISHED' not in result:
                raise ValueError("Blender could not import this GLB.")
            depsgraph = context.evaluated_depsgraph_get()
            for source in scratch.objects:
                if source.type != 'MESH' or not source.data.polygons:
                    continue
                evaluated = source.evaluated_get(depsgraph)
                mesh = bpy.data.meshes.new_from_object(evaluated, depsgraph=depsgraph)
                obj = bpy.data.objects.new(source.name, mesh)
                objects.append(obj)
                transform = evaluated.matrix_world
                mesh.transform(transform)
                if transform.is_negative:
                    mesh.flip_normals()
                mesh.materials.clear()
        if not objects:
            raise ValueError("The GLB contains no renderable mesh faces.")
        return objects
    except Exception:
        remove_model(objects)
        raise
    finally:
        bpy.data.batch_remove(imported_data)


def fit_model(objects, rotation=None):
    minimum = np.full(3, np.inf)
    maximum = np.full(3, -np.inf)
    axes = np.asarray(rotation) if rotation is not None else None
    for obj in objects:
        coordinates = np.empty(len(obj.data.vertices) * 3, dtype=np.float32)
        obj.data.vertices.foreach_get("co", coordinates)
        vertices = coordinates.reshape(-1, 3)
        if axes is not None:
            vertices = vertices @ axes.T
        minimum = np.minimum(minimum, vertices.min(axis=0))
        maximum = np.maximum(maximum, vertices.max(axis=0))
    size = maximum - minimum
    extent = max(size[0] / 2.25, size[1] / 2.25, size[2] / 2.05)
    if not np.isfinite(size).all() or not np.isfinite(minimum).all() or extent <= 0:
        raise ValueError("The model has invalid or zero-sized geometry.")
    scale = 1 / extent
    center = (minimum + maximum) / 2
    center[2] = minimum[2]
    fit = Matrix.Translation(Vector(-center * scale)) @ Matrix.Scale(scale, 4)
    return fit if rotation is None else fit @ rotation.to_4x4()


def replace_model(settings, objects, label):
    collection = settings.model_collection
    previous = list(collection.objects)
    try:
        # The importer bakes transforms into the vertices, so all parts can
        # be fitted together without changing their relative placement.
        fit = fit_model(objects)
        material = glaze_material(settings.glaze, settings.custom_color_srgb)
        for obj in objects:
            obj.matrix_world = fit
            apply_glaze(obj.data, material)
            collection.objects.link(obj)
    except Exception:
        remove_model(objects)
        raise

    remove_model(previous)
    settings.model_label = label


def aim(obj, target):
    obj.rotation_euler = (Vector(target) - obj.location).to_track_quat('-Z', 'Y').to_euler()


def create_studio():
    scene = bpy.data.scenes.new("NOVA Pottery Studio")
    settings = scene.nova_pottery
    collection = bpy.data.collections.new("Pottery Model")
    scene.collection.children.link(collection)
    settings.model_collection = collection

    floor = mesh_object("Studio Backdrop", [(-100, -100, 0), (100, -100, 0),
                                           (100, 100, 0), (-100, 100, 0)],
                        [(0, 1, 2, 3)])
    scene.collection.objects.link(floor)
    material = bpy.data.materials.new("Warm Gray Backdrop")
    material.diffuse_color = (.24, .22, .20, 1)
    shader = material.node_tree.nodes.get("Principled BSDF")
    shader.inputs["Base Color"].default_value = material.diffuse_color
    shader.inputs["Roughness"].default_value = .82
    floor.data.materials.append(material)

    scene.world = bpy.data.worlds.new("Studio Ambient")
    background = scene.world.node_tree.nodes.get("Background")
    background.inputs["Color"].default_value = (.48, .52, .60, 1)
    background.inputs["Strength"].default_value = .24

    for name, position, watts, size, color in (
        ("Key Softbox", (-3.8, -4.4, 5.4), 850, 3.4, (1, .88, .76)),
        ("Fill Softbox", (3.9, -1.8, 3.1), 340, 3.0, (.78, .88, 1)),
        ("Rim Softbox", (1.3, 3.1, 4.5), 780, 2.5, (1, .94, .86)),
    ):
        data = bpy.data.lights.new(name, 'AREA')
        data.energy = watts
        data.shape = 'DISK'
        data.size = size
        data.color = color
        light = bpy.data.objects.new(name, data)
        scene.collection.objects.link(light)
        light.location = position
        aim(light, (0, 0, .8))

    camera = bpy.data.objects.new("Studio Camera", bpy.data.cameras.new("Studio Camera"))
    scene.collection.objects.link(camera)
    camera.location = (3.7, -6.5, 3.55)
    camera.data.lens = 65
    aim(camera, (0, 0, .85))
    scene.camera = camera

    scene.render.engine = 'CYCLES'
    scene.cycles.samples = 48
    scene.cycles.use_denoising = True
    scene.render.resolution_x = scene.render.resolution_y = 1100
    scene.render.resolution_percentage = 100
    scene.render.image_settings.file_format = 'PNG'
    scene.view_settings.view_transform = 'AgX'
    replace_model(settings, [pottery_shape(settings.shape)], SHAPES[settings.shape][0])
    return scene


class NOVA_PG_settings(bpy.types.PropertyGroup):
    model_collection: bpy.props.PointerProperty(type=bpy.types.Collection)
    model_label: bpy.props.StringProperty()
    shape: bpy.props.EnumProperty(
        name="Shape", items=[(key, name, "") for key, (name, _) in SHAPES.items()],
    )
    glaze: bpy.props.EnumProperty(
        name="Glaze", items=[(key, preset[0], preset[1]) for key, preset in GLAZES.items()] + [("CUSTOM", "Custom Color", "Custom sRGB glaze color")],
        update=update_glaze,
    )
    custom_color_srgb: bpy.props.StringProperty(default="#C84B32", update=update_glaze)


class NOVA_OT_open_studio(bpy.types.Operator):
    bl_idname = "nova_pottery.open_studio"
    bl_label = "Open Pottery Studio"

    def execute(self, context):
        scene = next((scene for scene in bpy.data.scenes if scene.nova_pottery.model_collection), None)
        context.window.scene = scene if scene else create_studio()
        if context.area and context.area.type == 'VIEW_3D':
            viewport = context.space_data
            viewport.region_3d.view_perspective = 'CAMERA'
            viewport.shading.color_type = 'MATERIAL'
            viewport.overlay.show_overlays = False
        return {'FINISHED'}


class StudioOperator:
    @classmethod
    def poll(cls, context):
        return context.mode == 'OBJECT' and bool(context.scene.nova_pottery.model_collection)


class NOVA_OT_use_shape(StudioOperator, bpy.types.Operator):
    bl_idname = "nova_pottery.use_shape"
    bl_label = "Use Shape"
    bl_options = {'REGISTER', 'UNDO'}

    def execute(self, context):
        settings = context.scene.nova_pottery
        replace_model(settings, [pottery_shape(settings.shape)], SHAPES[settings.shape][0])
        return {'FINISHED'}


class NOVA_OT_import_glb(StudioOperator, bpy.types.Operator, ImportHelper):
    bl_idname = "nova_pottery.import_glb"
    bl_label = "Import GLB"
    bl_options = {'REGISTER', 'UNDO'}
    filename_ext = ".glb"
    filter_glob: bpy.props.StringProperty(default="*.glb", options={'HIDDEN'})

    def execute(self, context):
        settings = context.scene.nova_pottery
        try:
            objects = read_glb(context, self.filepath)
            replace_model(settings, objects, Path(self.filepath).stem)
        except (ValueError, RuntimeError, OSError) as error:
            self.report({'ERROR'}, str(error))
            return {'CANCELLED'}
        return {'FINISHED'}


class NOVA_PT_studio(bpy.types.Panel):
    bl_label = "NOVA Pottery Studio"
    bl_space_type = 'VIEW_3D'
    bl_region_type = 'UI'
    bl_category = "Pottery"

    def draw(self, context):
        layout = self.layout
        settings = context.scene.nova_pottery
        if not settings.model_collection:
            layout.operator("nova_pottery.open_studio", icon='SCENE_DATA')
            return

        layout.label(text=settings.model_label, icon='MESH_DATA')
        row = layout.row(align=True)
        row.prop(settings, "shape", text="")
        row.operator("nova_pottery.use_shape")
        layout.operator("nova_pottery.import_glb", icon='IMPORT')
        layout.separator()
        layout.prop(settings, "glaze")
        layout.separator()
        layout.operator("render.render", text="Render Studio", icon='RENDER_STILL')


CLASSES = (NOVA_PG_settings, NOVA_OT_open_studio, NOVA_OT_use_shape,
           NOVA_OT_import_glb, NOVA_PT_studio)


def register():
    for cls in CLASSES:
        bpy.utils.register_class(cls)
    bpy.types.Scene.nova_pottery = bpy.props.PointerProperty(type=NOVA_PG_settings)


def unregister():
    del bpy.types.Scene.nova_pottery
    for cls in reversed(CLASSES):
        bpy.utils.unregister_class(cls)


if __name__ == "__main__":
    register()
