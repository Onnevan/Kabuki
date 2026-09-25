# Kabuki — Godot prototype v0.1

A small architectural prototype for a touch-first 2D/2.5D/3D motion-graphics application.

## Run
1. Clone or download this repository.
2. In Godot 4.x Project Manager choose **Import** and select `project.godot`.
3. Open the project and press F6/F5.
4. Click **+ Import PNG** and choose a transparent PNG.
5. Nudge the object, set a Position key, move to another frame, nudge again and set another key.
6. Try Hold / Linear / Ease and animate Blur, Glow/Emission, Exposure and Saturation.

## What v0.1 proves
- Godot is only the editor/runtime; application data lives in our own model.
- Transparent PNGs become real deformation-ready triangulated geometry.
- Animation uses generic property paths rather than Godot AnimationPlayer.
- Effects are properties and therefore use the same keyframe system.
- Hierarchy, Character, Paint, Deform and Surface Binding have reserved architectural space.

## Next milestone
Direct viewport manipulation + object picking; proper scene/object list; project JSON save/load; Character Group parenting/pivots; then the first 3D Stroke renderer.
