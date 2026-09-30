# KABUKI Milestone 01 — Interactive Foundation

Frozen reference point: 2026-09-30
Branch at freeze: `v0.2-interaction`
Reference commit before milestone marker: `bd7a80cc801c3cc4c21bbb64012764d4ccfcd64e`

## Scope

First coherent KABUKI prototype milestone: editor shell; Scene, Drawing, Rigging, Animation and Compositor workspaces; reference canvases; bitmap/spatial drawing foundations; tessellated artwork; camera workflow; save/load foundation; timeline/key editing; skeleton creation; skinning; direct bone manipulation; animated bone transforms with interpolation; and the first major UI/UX redesign.

The UI direction is the approved dark, tactile, iPad-first creative-tool language: dominant viewport, floating content-sized tool surfaces, contextual controls, rounded cards, reduced DCC terminology, and no intentionally empty toolbars.

## Stability rules

- Preserve correct drawing orientation and current alpha-mesh UV convention.
- Preserve Skeleton3D pose initialization from rest transforms.
- Preserve armature-space skinning/weight calculation and the current working bone deformation/animation path.
- Visible controls must perform real actions; do not restore dummy UI.
- Floating toolbars hide when empty and hug visible content.
- Treat this milestone as the regression reference for subsequent development.

## Next phase

Complete the UI overhaul and dummy-control audit, then continue animation, rigging/IK and drawing workflows.
