# NOVA Pottery Studio

NOVA is a Windows desktop app for previewing pottery with Blender. Choose a built-in shape or import a GLB, apply a ceramic glaze preset, and render it in the same studio.

## Open the desktop app

1. Install Blender 5.2 or newer. Double-click `Start NOVA.cmd`. NOVA looks for Blender in standard install locations. For a custom install, use **Advanced Options → Locate Blender**, or set the `NOVA_BLENDER` environment variable to the full path of `blender.exe`.
2. Choose a built-in model or click **Import GLB**. Select a glaze color and finish and, if known, enter the recipe, nominal glaze thickness in millimeters, and peak firing temperature in Celsius.
3. Expand **Advanced Options** to enter kiln atmosphere, cone, heating and cooling information, peak hold, clay body, a thickness map path, or firing geometry notes. The setup always contains one glaze layer.
4. Click **Render Preview** to render in the app and **Save PNG** to export the last preview. **Export Setup** writes the current inputs to a versioned JSON file for use by a future prediction component. Leave unknown values blank to export them as `null`.

Blender runs in the background with the same camera, softboxes, and backdrop for every preview. Recipe, thickness, firing, and other advanced values are recorded in the setup JSON. The rendered appearance comes from the selected preset material.

## Use directly in Blender

1. In Blender 5.2, open **Edit → Preferences → Add-ons**. Use the menu in the upper-right corner and choose **Install from Disk**. Select `nova_pottery.py`, then enable **NOVA Pottery Studio** if prompted.
2. In the 3D Viewport, press **N** to open the sidebar. Select **Pottery → Open Pottery Studio**.
3. Pick **Serving Bowl**, **Bud Vase**, or **Tea Cup** and click **Use Shape**. For your own pottery mesh, click **Import GLB** and select a `.glb` file.
4. Pick **Jade Celadon**, **Cobalt Blue**, or **Speckled Oatmeal** from the **Glaze** menu. The glaze covers the whole piece.
5. Click **Render Studio** to render in Cycles. Use **Image → Save As** in the render window to export a PNG, or save the Blender project to keep the studio and current piece.

The add-on creates a separate Blender scene. A shape change or import replaces the current piece in that scene. Imported meshes keep their proportions and relative placement. NOVA fits them to the studio, places them on the backdrop, and applies the selected glaze in place of source materials. Use a GLB with the pottery already upright for an upright render. The camera, three softboxes, and warm gray backdrop stay fixed when the piece or glaze changes.
