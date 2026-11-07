"""Background Blender entry point for the NOVA desktop app."""

import json
from math import radians
from pathlib import Path
from struct import pack
import sys

import bpy
from mathutils import Euler
import numpy as np

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from nova_pottery import GLAZES, SHAPES, fit_model, register


def load_model(request):
    if bpy.app.version < (5, 2, 0):
        raise RuntimeError("NOVA requires Blender 5.2 or newer.")
    model = request["model"]
    glaze = request["glaze_id"]
    if glaze not in GLAZES or request["inputs"]["layers"] != [{"glaze_id": glaze, "order": 1}]:
        raise ValueError("Choose one glaze preset for layer 1.")

    register()
    bpy.ops.nova_pottery.open_studio()
    scene = bpy.context.scene
    settings = scene.nova_pottery
    settings.glaze = glaze

    if model["kind"] == "glb":
        result = bpy.ops.nova_pottery.import_glb(filepath=model["path"])
    elif model["kind"] == "preset" and model["id"] in SHAPES:
        settings.shape = model["id"]
        result = bpy.ops.nova_pottery.use_shape()
    else:
        raise ValueError("Choose a built-in model or a GLB file.")
    if 'FINISHED' not in result:
        raise RuntimeError("Blender could not load the selected model.")
    return scene


def export_orientation_mesh(scene, path):
    objects = list(scene.nova_pottery.model_collection.objects)
    depsgraph = bpy.context.evaluated_depsgraph_get()
    triangle_count = 0
    for obj in objects:
        mesh = obj.evaluated_get(depsgraph).data
        mesh.calc_loop_triangles()
        triangle_count += len(mesh.loop_triangles)
    if triangle_count > 28000:
        for obj in objects:
            decimate = obj.modifiers.new("Orientation preview", 'DECIMATE')
            decimate.ratio = 28000 / triangle_count
        bpy.context.view_layer.update()
        depsgraph = bpy.context.evaluated_depsgraph_get()

    vertices = []
    triangles = []
    offset = 0
    for obj in objects:
        evaluated = obj.evaluated_get(depsgraph)
        mesh = evaluated.data
        mesh.calc_loop_triangles()
        points = np.empty(len(mesh.vertices) * 3, dtype=np.float32)
        mesh.vertices.foreach_get("co", points)
        matrix = np.asarray(evaluated.matrix_world)
        points = points.reshape(-1, 3) @ matrix[:3, :3].T + matrix[:3, 3]
        vertices.append(points)
        indices = np.empty(len(mesh.loop_triangles) * 3, dtype=np.int32)
        mesh.loop_triangles.foreach_get("vertices", indices)
        triangles.append(indices + offset)
        offset += len(points)

    points = np.concatenate(vertices)
    points -= (points.min(axis=0) + points.max(axis=0)) * .5
    # Convert Blender Z-up to WPF Y-up without reversing triangle winding.
    points = points[:, [0, 2, 1]]
    points[:, 2] *= -1
    indices = np.concatenate(triangles)
    with Path(path).open("wb") as stream:
        stream.write(pack("<II", len(points), len(indices)))
        stream.write(points.astype("<f4").tobytes())
        stream.write(indices.astype("<i4").tobytes())


def render(request_path, output_path, mode="render"):
    request = json.loads(Path(request_path).read_text(encoding="utf-8-sig"))
    scene = load_model(request)
    if mode == "mesh":
        export_orientation_mesh(scene, output_path)
        return

    angles = request["model"].get("rotation_xyz_degrees", (0, 0, 0))
    if any(angles):
        objects = list(scene.nova_pottery.model_collection.objects)
        rotation = Euler(tuple(map(radians, angles)), 'XYZ').to_matrix()
        fit = fit_model(objects, rotation)
        for obj in objects:
            obj.matrix_world = fit

    # Firing and application inputs travel with the setup for a future
    # predictor. The preview uses the selected Blender material preset.
    scene.render.resolution_percentage = 60
    scene.cycles.samples = 20
    scene.render.filepath = str(Path(output_path).resolve())
    if 'FINISHED' not in bpy.ops.render.render(write_still=True):
        raise RuntimeError("Blender could not finish the preview.")


if __name__ == "__main__":
    render(*sys.argv[sys.argv.index("--") + 1:])
