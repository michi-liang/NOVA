# NOVA Pottery Studio

NOVA is a Windows desktop app for previewing pottery with Blender. Choose a built-in shape, import a GLB, or generate one from a photo. Apply a ceramic glaze preset and render it in the same studio.

## Open the desktop app

1. Install Blender 5.2 or newer. Double-click `Start NOVA.cmd`. NOVA looks for Blender in standard install locations. For a custom install, use **Additional Options → Locate Blender**, or set the `NOVA_BLENDER` environment variable to the full path of `blender.exe`.
2. Choose a built-in model or use the import icon to select a `.glb` or generate one from a photo. Select Jade Celadon, Cobalt Blue, Speckled Oatmeal, or choose **Custom color** and pick a shade from the color wheel. The swatch and 3D preview update as you change the color or glaze opacity. At **Clear**, the preview shows the clay underneath. If known, enter the nominal glaze thickness in millimeters and peak firing temperature in Celsius.
3. Open the **Additional Options** tab to enter kiln atmosphere, cone, heating and cooling information, peak hold, clay body, a thickness map path, or firing geometry notes. The setup always contains one glaze layer.
4. Click **Orient Model** to open a live 3D view. Drag to turn and tilt the piece, or use the Turn, Tilt, and Roll sliders. Click **Render Preview** to apply that orientation in the studio. **Reset** restores the original orientation.
5. Click **Save PNG** to export the last preview. **Export Setup** writes the current inputs and model orientation to a versioned JSON file for use by a future prediction component. Leave unknown values blank to export them as `null`.

Blender runs in the background with the same camera, softboxes, and backdrop for every preview. Thickness, firing, and other advanced values are recorded in the setup JSON. **Render Preview** applies the selected color and opacity to the Blender material.

## NOVA assistant

The assistant appears to the right of the preview. Click **API key…** and save an OpenRouter API key to enable pottery help and natural-language setting changes. NOVA encrypts the saved key for the current Windows account; chat messages and the current model, glaze, and firing settings are sent to OpenRouter for a response. API requests may use your OpenRouter balance. The assistant updates supported fields in the app, and you can click **Render Preview** to see the change.

## Generate a model from a photo

1. Install 64-bit Python for Windows with `python` available on your PATH. In NOVA, open **Additional Options → Set Up Photo Generator**. Setup needs internet access and several GB of disk space for the model and Python dependencies. Generation runs locally after setup.
2. Click the import icon, pick a PNG or JPEG, and choose where to save the generated `.glb`. NOVA selects the completed model automatically.
3. Orient the model if needed, choose a glaze, and click **Render Preview**.

NOVA skips photo texture baking by default because the studio applies a new glaze. Under **Additional Options**, enable **Bake photo texture into GLB (slower)** to include the photo texture, or enable **Draft photo mesh** to generate a lower-detail mesh faster. The standard mesh uses a 128³ sampling grid and the draft uses 96³.

The photo generator comes from the repository's `larp-laep-larp-shahor` branch. It uses TripoSR to reconstruct a model from a single image. See [Nova Image to 3D](Nova-Image-to-3D/README.md) for runtime details and upstream attribution.

## Vase finite element analysis

The **FEA** tab runs the local stress analysis from the `fea-gpt` branch on a vase GLB. Browse for a GLB or use the imported Studio GLB, click **Set Up FEA Engine** once, review the solver inputs under **Additional Options → FEA Settings**, and click **Run FEA**. Results are written to the selected folder; NOVA reports maximum von Mises stress and displacement, and can open the stress-colored GLB or results folder.

The FEA setup downloads a dedicated Python 3.11+ environment and NumPy, SciPy, Trimesh, and meshio. The first setup needs internet access. Geometry, material, and load settings are editable in the app or in `examples/settings.txt` for command-line runs. Lengths are meters after model scaling, forces newtons, stresses pascals, and wall thickness is an explicit assumption.

This solver uses homogeneous isotropic linear elasticity, small displacements, gravity, a clamped base, and a voxel tetrahedral mesh. It does not model fracture, contact, buckling, or nonlinear ceramic behavior. Values in `examples/settings.txt` are illustrative; computed stress and displacement are not a guarantee of safe firing or structural strength.

For command-line use after setup, run `python -m vase_stress.cli run --model vase.glb --settings examples/settings.txt --output outputs/run-001` from the project root.

## Combined glaze predictor

On `combined_model`, open **Combined → Set Up Combined Predictor** and select the supplied `Combined_Glaze_Predictor` folder containing `model.json` and `textures`. Setup needs Python 3.10 or newer on PATH and installs NumPy and Pillow into a dedicated environment. The model and photos are copied into the ignored `.combined-glaze` folder.

Choose the top glaze, base glaze, and firing cone, then click **Predict Color and Swatch**. The appearance service predicts the base color and contrast. The local retrieval model uses those values and the cone to find a similar texture photo and create the swatch. **Apply Color to Studio** uses the predicted color as the custom glaze for a Blender render. The photo swatch stays in the Combined tab.

For live calls, enter the service owner's private token under **Combined → Live API access**. NOVA keeps it for the current session only. You can also set `AI_TEXTURE_TOKEN` before launching NOVA. If the service's tunnel moves, set `GLAZE_API_URL` to the new HTTPS endpoint. **Run Sample** uses the saved prediction included in the bundle, and **Load Prediction JSON** accepts another saved appearance-service response. Both run the local retrieval model without credentials. The swatch is a color-adjusted photo match, so its pattern is illustrative.

## Use directly in Blender

1. In Blender 5.2, open **Edit → Preferences → Add-ons**. Use the menu in the upper-right corner and choose **Install from Disk**. Select `nova_pottery.py`, then enable **NOVA Pottery Studio** if prompted.
2. In the 3D Viewport, press **N** to open the sidebar. Select **Pottery → Open Pottery Studio**.
3. Pick **Serving Bowl**, **Bud Vase**, or **Tea Cup** and click **Use Shape**. For your own pottery mesh, click **Import GLB** and select a `.glb` file.
4. Pick **Jade Celadon**, **Cobalt Blue**, or **Speckled Oatmeal** from the **Glaze** menu. The glaze covers the whole piece.
5. Click **Render Studio** to render in Cycles. Use **Image → Save As** in the render window to export a PNG, or save the Blender project to keep the studio and current piece.

The add-on creates a separate Blender scene. A shape change or import replaces the current piece in that scene. Imported meshes keep their proportions and relative placement. NOVA fits them to the studio, places them on the backdrop, and applies the selected glaze in place of source materials. Use a GLB with the pottery already upright for an upright render. The camera, three softboxes, and warm gray backdrop stay fixed when the piece or glaze changes.
