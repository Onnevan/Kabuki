# KABUKI UI/UX Design System

**Version:** 0.2  
**Status:** Canonical design direction

## 1. Product experience

KABUKI is an iPad-first creative animation application: a 2D/3D drawing and animation space, not a reduced desktop DCC.

The interface must feel **modern, calm, tactile, visual and inviting**. Direct manipulation comes first. Apple Pencil/touch must not depend on an outliner, tiny handles or modifier keys.

Primary rule: **show intent, hide machinery**.

Use language such as Draw, Pose, Animate, Gradient, Color, Focus and IK. Bind, Skin, Weights, Transform3D, vertex data and similar implementation concepts must not become required normal workflow.

## 2. Canonical visual reference

The approved KABUKI mockup establishes the target:
- charcoal/navy shell;
- large uninterrupted central canvas;
- restrained blue accent;
- floating rounded tool surfaces;
- compact vertical tool rail;
- left content/layer browser;
- right contextual inspector;
- substantial bottom timeline;
- clear hierarchy, generous spacing and little visual noise.

Do not copy pixels blindly. Preserve its hierarchy, density, proportions and interaction philosophy.

## 3. Layout

```
┌─────────────────────────────────────────────────────────────┐
│ KABUKI   SCENE  ANIMATE  DRAWING  RIGGING  COMPOSITOR     │
├──────────┬──────────────────────────────────────┬───────────┤
│ Content  │                                      │ Context   │
│ /Layers  │              VIEWPORT                │ Inspector │
│          │                                      │           │
│          │  floating tool rail + context HUD    │           │
├──────────┴──────────────────────────────────────┴───────────┤
│                         TIMELINE                            │
└─────────────────────────────────────────────────────────────┘
```

The viewport is always dominant.

### Top bar
Only global/workspace concepts: identity, workspaces, Undo/Redo, project, Save, Export, Preview, settings. Never active-tool parameter dumping.

### Left panel — what exists
Objects, canvases, layers, characters, assets or hierarchy. It is organizational, not the primary manipulation interface.

### Right panel — what can I change
Contextual tool/selection inspector. Prefer collapsible cards.

### Bottom — time
Playback, time, channels, keys, F-curves and animation controls.

## 4. Visual language

Use four surface levels: app background, structural panel, floating/card surface, active/accent surface. Prefer luminance and spacing to borders.

**Shape:** cards 10–14 px radius; buttons/chips 8–10 px. Avoid grids of identical hard rectangles.

**Spacing:** 8 px base rhythm; 4 px tightly related, 8 px within groups, 12–16 px inside cards, 16–24 px major padding.

**Color:** blue only for active/selected/primary/playhead. Warning colors only when meaningful. Channel colors subdued unless selected.

**Typography:** 12–13 px meta, 13–15 px controls, 16–18 px titles. Avoid unnecessary all-caps.

## 5. Reusable components

Build reusable components rather than workspace-specific ad-hoc controls:
- ToolButton
- ToolRail
- SegmentedControl
- ContextHUD
- InspectorCard
- PropertyRow
- AnimatablePropertyRow
- ColorChip
- ValueSlider
- TimelineChannelRow
- FloatingPanel

Theme tokens define surfaces, accent, text levels, radii, spacing and standard heights.

### Tool rail
Primary tools are icon-first in a stable vertical rail beside the viewport. Parameters change elsewhere.

### Context HUD
Floating horizontal surface for the 2–6 parameters needed continuously during direct manipulation.

Example:
```
Lasso Fill   [Solid | Gradient]   A ■  B ■   ↗ -45°
```

Never accumulate every possible parameter into one HBox.

### Inspector cards
For deeper contextual settings:
```
TOOL
  Lasso Fill
  [Solid] [Gradient]

  Color A  ■
  Color B  ■
  Angle    ━━━━━  -45°
  Feather  ━━━━━   0 px

LAYER >
TRANSFORM >
COMPOSITING >
```

Prefer slider + visible value for exploratory values. Spin boxes are precision controls, not the default representation of everything.

Use segmented controls for 2–4 mutually exclusive modes; switches for persistent binary state.

## 6. Drawing workspace

Drawing must feel like a drawing app first.

### Stable tool rail
Recommended order: Select, Brush, Pencil, Eraser, Smudge, Fill/Lasso, Rectangle, Ellipse, Spatial/3D Stroke, Text (future), Pan, Zoom. Related tools may use flyouts.

### Brush
Context HUD:
```
Brush   Size ━━━   Opacity ━━━   Color ■   Preset [Ink]
```
Hardness and advanced brush behavior move to inspector unless continuously needed.

### Lasso Fill
Solid:
```
Lasso Fill   [Solid | Gradient]   Color ■   Feather 0
```

Gradient:
```
Lasso Fill   [Solid | Gradient]   A ■  B ■   gradient preview
```

Primary gradient interaction is direct:
1. draw/close lasso;
2. drag across selected region;
3. drag start/end handles to set direction/span;
4. A/B colors correspond visibly to endpoints.

Angle is optional precision in inspector, not the principal workflow.

### Canvas/layers
Canvas and artwork/layers must be visually distinct. Canvas is a drawing space/reference plane, not artwork itself.

## 7. Animation workspace

Animation should feel like performing a puppet:
1. tap character/bone/control directly;
2. drag/rotate/pose;
3. Auto Key records changed animatable properties;
4. move in time;
5. create next pose.

Outliner selection and transform gizmos are secondary.

### Universal animation rule
**Every meaningful editable property should be animatable.**

Generic model:
```
object/property path → channel → keys → interpolation
```

Transforms, bone pose components, opacity, colors, effects, camera FOV/focus/aperture, IK target/influence and relevant drawing properties use this same system.

Inspector properties may expose a small diamond/key indicator.

### Bone channels
Viewport bone selection focuses:
```
Bone 02
  Position
  Rotation
  Scale
```
Expandable channels reveal F-curves. Interpolation is editable per key.

## 8. Rigging workspace

Mental model: **build the puppet**.

Normal workflow:
1. select artwork;
2. Create Skeleton;
3. click root then connected joints;
4. Esc ends current chain and permits another root;
5. Enter finishes;
6. KABUKI parents/binds/weights automatically;
7. tap/drag bones to test.

Do not require Bind or Auto Weights buttons in the normal path.

Bones have viewport selection priority over artwork.

### Weights
Weights are feedback, not an obligatory technical mode. Bone selection in Rigging may show influence on the currently deformed artwork. It must never reset pose. Weight Edit appears only when correction is needed.

### IK
Select end bone → **+ IK** → KABUKI infers sensible chain → direct viewport handle. Chain length/pole/influence live in inspector only if needed.

## 9. Scene workspace

General composition: hierarchy, placement, camera, lights, materials, object effects and master timeline. Direct viewport selection remains primary; outliner is organizational.

## 10. Compositor

Ordered **Effect Stack**, not nodes. Effects are cards, reorderable, bypassable and animatable:

```
Glow                  ◉
Threshold        ━━━━━
Radius           ━━━━━
Intensity        ━━━━━
```

Advanced settings expand only when requested.

## 11. Timeline / F-curves

Timeline may expand into a meaningful editor or collapse to transport.

Header: Play/Pause, previous/next key, current time/frame, Auto Key; Onion Skin where relevant.

Body: selected object/control, All Channels, property channels, keys, expandable F-curves.

Viewport and timeline selection stay synchronized. Never require outliner selection just to expose animation channels.

## 12. Touch / Pencil

Final iPad touch target: approximately 44 pt minimum even if icon art is smaller. Pencil may offer precision but is not required for basic operation.

Avoid workflows based on keyboard modifiers. Desktop modifiers are accelerators only.

## 13. Contextual disclosure

Before adding a control ask:
1. Is it continuously needed?
2. Is it specific to active tool/selection?
3. Is it advanced?
4. Can direct manipulation replace it?

Placement:
- continuous/immediate → Context HUD;
- contextual/detailed → right inspector;
- organizational → left panel;
- animation/time → timeline;
- advanced → collapsed inspector;
- implementation detail → do not expose.

## 14. Anti-patterns

Do not:
- add toolbar buttons merely because there is room;
- expose engine concepts as required workflow;
- show inactive-tool parameters;
- make outliner selection the normal character workflow;
- require transform gizmos for routine posing;
- mix global/tool/animation controls in one strip;
- use obscure unlabeled icons unnecessarily;
- solve complexity with more dropdowns;
- make every panel equally prominent;
- let new features gradually destroy visual hierarchy.

## 15. Responsive behavior

Wide desktop: left + viewport + right + timeline.

iPad landscape: same composition with collapsible/narrower side panels.

Reduced width: inspector becomes slide-over; left panel collapses; viewport remains primary.

Portrait is secondary and may use mutually exclusive drawers.

Never scale every control down until unusable.

## 16. Migration strategy

Do not rewrite functional systems just for the redesign.

1. Establish tokens/components.
2. Rebuild Drawing shell around existing callbacks.
3. Move tool parameters into Context HUD/Inspector.
4. Rebuild Animation/Rigging around direct manipulation.
5. Modernize timeline/channel rows.
6. Apply components to Scene/Compositor.
7. Remove obsolete prototype controls only after replacements work.

Current drawing, tessellation, skinning, bone deformation/animation, weight display, camera and save/load behavior must survive migration.

## 17. Acceptance test

A feature is integrated only if:
- viewport remains dominant;
- active tool is immediately obvious;
- irrelevant parameters are absent;
- primary action is discoverable without outliner;
- common tasks require no implementation terminology;
- controls belong to one coherent design system;
- touch targets remain practical;
- adding it did not turn a contextual surface into a permanent toolbar.

The target feeling is **creative instrument**, not **technical control panel**.
