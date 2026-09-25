# Kabuki — architecture v0.1

Principle: the project data model is authoritative; Godot Nodes are runtime views.

## Modules
- `core/`: stable object/component/project data model.
- `animation/`: generic property channels and future behaviors.
- `render/`: Godot runtime representation, alpha meshing, shaders.
- `paint/`: future 2D/frame, free-space 3D and surface paint. `Stroke3DData` already exists as a core-ready primitive.
- `editor/`: touch/Pencil-oriented UI and tools.

## Object model
Every object has a technical type and a semantic role. Roles are UX/component presets, not hard classes.
Examples: `ImageMesh + Prop`, `Drawing + Character`, `Stroke3D + Effect`, `ImportedMesh + Environment`.

Reserved components: transform, render, animation, hierarchy, paint, effects, deform, character. Future audio/camera/light components fit the same pattern.

## Character hierarchy
`parent_id` is already persistent. Character Group will add pivots, controls, poses and draw-order while remaining a normal hierarchy of MotionObjects.

## Paint engine target
One brush sampling model, three placement modes: Frame2D, Space3D, Surface3D. Surface strokes will store triangle + barycentric binding so they can follow later deformation. Texture paint remains separate from volumetric Stroke3D.

## Prototype vertical slice
PNG -> alpha sampling -> Delaunay triangulation -> ImageMesh -> transform -> generic animation channels -> effects shader -> camera -> playback.

The current Delaunay mesher is intentionally simple: it samples opaque pixels and alpha boundaries, triangulates all samples, then rejects triangles whose centroids fall in transparent pixels. It is sufficient to validate the data/render pipeline; contour quality and constrained triangulation are later milestones.
