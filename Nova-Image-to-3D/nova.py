import argparse
import os
from pathlib import Path

import numpy as np
import torch
import trimesh
from PIL import Image, ImageOps

def mask_background(image, model_path):
    import onnxruntime as ort

    options = ort.SessionOptions()
    options.intra_op_num_threads = 4
    session = ort.InferenceSession(
        str(model_path), sess_options=options, providers=["CPUExecutionProvider"]
    )
    resized = image.convert("RGB").resize((320, 320), Image.Resampling.LANCZOS)
    pixels = np.asarray(resized, dtype=np.float32)
    pixels /= max(pixels.max(), 1e-6)
    pixels = (pixels - np.array([0.485, 0.456, 0.406], np.float32)) / np.array(
        [0.229, 0.224, 0.225], np.float32
    )
    prediction = session.run(
        None, {session.get_inputs()[0].name: pixels.transpose(2, 0, 1)[None]}
    )[0][0, 0]
    prediction -= prediction.min()
    prediction /= max(prediction.max(), 1e-6)
    mask = Image.fromarray((prediction * 255).astype(np.uint8))
    image.putalpha(mask.resize(image.size, Image.Resampling.LANCZOS))


def main():
    parser = argparse.ArgumentParser(description="Generate a textured GLB from one image.")
    parser.add_argument("image", type=Path)
    parser.add_argument("output", type=Path)
    parser.add_argument("--cpu", action="store_true")
    parser.add_argument("--mesh-resolution", type=int, default=128)
    parser.add_argument("--texture-resolution", type=int, default=1024)
    parser.add_argument("--geometry-only", action="store_true", help="Skip texture baking for a GLB that will be reglazed.")
    args = parser.parse_args()
    if args.output.suffix.lower() != ".glb":
        parser.error("Use a .glb output filename.")

    runtime = Path(__file__).resolve().parent / ".runtime"
    weights = runtime / "weights"
    required = ("model.ckpt", "config.yaml", "dino.json", "u2netp.onnx")
    if any(not (weights / filename).is_file() for filename in required):
        parser.error("Run setup.ps1 to prepare the model files first.")
    os.environ["NOVA_WEIGHTS_DIR"] = weights.as_posix()
    os.environ.setdefault("HF_HOME", str(runtime / "hf-cache"))
    os.environ["HF_HUB_OFFLINE"] = "1"

    from tsr.system import TSR
    from tsr.utils import resize_foreground

    torch.set_num_threads(min(6, os.cpu_count() or 1))
    device = "cuda:0" if not args.cpu and torch.cuda.is_available() else "cpu"
    print(f"Loading TripoSR on {device}", flush=True)
    model = TSR.from_pretrained(str(weights), "config.yaml", "model.ckpt").eval().to(device)
    model.renderer.set_chunk_size(4096)

    with Image.open(args.image) as source:
        image = ImageOps.exif_transpose(source).convert("RGBA")
    if image.getchannel("A").getextrema() == (255, 255):
        mask_background(image, weights / "u2netp.onnx")
    if image.getchannel("A").getbbox() is None:
        raise ValueError("No foreground found in the input image.")
    image = resize_foreground(image, 0.85)
    background = Image.new("RGBA", image.size, (128, 128, 128, 255))
    background.alpha_composite(image)

    print("Reconstructing geometry", flush=True)
    with torch.no_grad(), torch.autocast("cuda", enabled=device.startswith("cuda")):
        scene_codes = model([background.convert("RGB")], device=device).float()
    mesh, = model.extract_mesh(scene_codes, False, resolution=args.mesh_resolution)

    args.output.parent.mkdir(parents=True, exist_ok=True)
    if args.geometry_only:
        mesh.export(args.output, include_normals=True)
        print(f"Saved {args.output.resolve()}", flush=True)
        return

    from tsr.bake_texture import bake_texture

    print("Baking UV texture", flush=True)
    model.decoder.cpu()
    baked = bake_texture(mesh, model, scene_codes[0].cpu(), args.texture_resolution)
    pixels = (baked["colors"][..., :3].clip(0, 1) * 255).astype(np.uint8)
    texture = Image.fromarray(pixels).transpose(Image.Transpose.FLIP_TOP_BOTTOM)
    material = trimesh.visual.material.PBRMaterial(
        baseColorTexture=texture, metallicFactor=0.0, roughnessFactor=1.0
    )
    mapping = baked["vmapping"]
    textured = trimesh.Trimesh(
        vertices=mesh.vertices[mapping],
        faces=baked["indices"],
        vertex_normals=mesh.vertex_normals[mapping],
        visual=trimesh.visual.texture.TextureVisuals(uv=baked["uvs"], material=material),
        process=False,
    )
    textured.export(args.output)
    print(f"Saved {args.output.resolve()}", flush=True)


if __name__ == "__main__":
    main()
