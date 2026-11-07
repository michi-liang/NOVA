# NOVA Pottery Studio

NOVA is a Blender add-on for rendering pottery. Choose a built-in shape or import a GLB, apply a ceramic glaze, and render it in the same studio.

## Install and use

1. In Blender 5.2, open **Edit → Preferences → Add-ons**. Use the menu in the upper-right corner and choose **Install from Disk**. Select `nova_pottery.py`, then enable **NOVA Pottery Studio** if prompted.
2. In the 3D Viewport, press **N** to open the sidebar. Select **Pottery → Open Pottery Studio**.
3. Pick **Serving Bowl**, **Bud Vase**, or **Tea Cup** and click **Use Shape**. For your own pottery mesh, click **Import GLB** and select a `.glb` file.
4. Pick **Jade Celadon**, **Cobalt Blue**, or **Speckled Oatmeal** from the **Glaze** menu. The glaze covers the whole piece.
5. Click **Render Studio** to render in Cycles. Use **Image → Save As** in the render window to export a PNG, or save the Blender project to keep the studio and current piece.

The add-on creates a separate Blender scene. A shape change or import replaces the current piece in that scene. Imported meshes keep their proportions and relative placement. NOVA fits them to the studio, places them on the backdrop, and applies the selected glaze in place of source materials. Use a GLB with the pottery already upright for an upright render. The camera, three softboxes, and warm gray backdrop stay fixed when the piece or glaze changes.
