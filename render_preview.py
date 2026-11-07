"""Background Blender entry point for the NOVA desktop app."""

import json
from pathlib import Path
import sys

import bpy

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
from nova_pottery import GLAZES, SHAPES, register


def render(request_path, image_path):
    if bpy.app.version < (5, 2, 0):
        raise RuntimeError("NOVA requires Blender 5.2 or newer.")
    request = json.loads(Path(request_path).read_text(encoding="utf-8-sig"))
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

    # Firing and application inputs travel with the setup for a future
    # predictor. The preview uses the selected Blender material preset.
    scene.render.resolution_percentage = 60
    scene.cycles.samples = 20
    scene.render.filepath = str(Path(image_path).resolve())
    if 'FINISHED' not in bpy.ops.render.render(write_still=True):
        raise RuntimeError("Blender could not finish the preview.")


if __name__ == "__main__":
    render(*sys.argv[sys.argv.index("--") + 1:])
