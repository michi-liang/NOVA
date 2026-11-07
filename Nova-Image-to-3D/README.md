# Nova Image to 3D

Generate a textured, Blender-ready GLB from a single image on Windows. This project packages TripoSR with a low-VRAM reconstruction path and CPU texture baking. It ran on an RTX 3050 Ti Laptop GPU with 4 GB VRAM.

## Set up on Windows

Use 64-bit Windows with Python and pip available through the `python` command. An NVIDIA GPU is recommended. Keep several GB free for the Python environment and model downloads. Blender is optional for generation.

Open PowerShell in this folder and run:

```powershell
powershell -NoProfile -ExecutionPolicy Bypass -File .\setup.ps1
```

Setup downloads the free dependencies and model files into `.runtime`. It needs internet access once. Generation runs locally afterward and uses neither an account nor an API key.

## Generate a model

Drag a PNG or JPG onto **Generate Nova 3D.cmd**. Look for the GLB in `generated`. The launcher overwrites a previous result with the same image name.

For control over the output path or quality, run:

```powershell
.\.runtime\env\Scripts\python.exe .\nova.py "C:\path\to\photo.png" .\generated\nova.glb
```

- Add `--cpu` if the GPU runs out of memory.
- Add `--geometry-only` to skip baking the photo texture when a new material will be applied later.
- Add `--texture-resolution 2048` for a larger texture atlas. This takes more time and memory. The tested default is 1024.
- Add `--mesh-resolution 160` for a denser geometry grid. The tested default is 128.

Use one image per run. For multiple angles, generate separate candidates and compare them. TripoSR reconstructs each view independently.

In Blender, use **File → Import → glTF 2.0** and switch the viewport to **Material Preview**. For OBJ, export from Blender with materials enabled and keep the OBJ, MTL, and texture together.

## Publish to GitHub

Commit this folder's source files, including `LICENSE`. Git ignores `.runtime`, `generated`, and downloaded weights. Teammates run setup after cloning.

The `tsr` source is adapted from [TripoSR](https://github.com/VAST-AI-Research/TripoSR/tree/107cefdc244c39106fa830359024f6a2f1c78871) under its MIT license. Setup downloads the [TripoSR weights](https://huggingface.co/stabilityai/TripoSR), [DINO configuration](https://huggingface.co/facebook/dino-vitb16), and [U²-Net foreground model](https://github.com/danielgatis/rembg/releases/tag/v0.0.0) from their upstream hosts.
