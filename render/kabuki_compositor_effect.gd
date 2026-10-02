@tool
extends CompositorEffect
class_name KabukiCompositorEffect

const CONTEXT := &"kabuki_compositor"
const SCRATCH := &"scratch"

const COPY_SHADER := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) readonly uniform image2D source_image;
layout(rgba16f, set = 0, binding = 1) writeonly uniform image2D dest_image;
layout(push_constant, std430) uniform Params {
	vec2 raster_size;
	vec2 pad;
} params;
void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(params.raster_size);
	if (p.x >= size.x || p.y >= size.y) return;
	imageStore(dest_image, p, imageLoad(source_image, p));
}
"""

const PROCESS_SHADER := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;
layout(rgba16f, set = 0, binding = 0) readonly uniform image2D source_image;
layout(rgba16f, set = 0, binding = 1) writeonly uniform image2D dest_image;

layout(push_constant, std430) uniform Params {
	vec2 raster_size;
	float blur;
	float glow_strength;
	float glow_threshold;
	float glow_radius;
	float exposure;
	float saturation;
	float contrast;
	float temperature;
	float tint;
	float vignette;
	float aberration;
	float monochrome;
	float pad0;
	float pad1;
} params;

ivec2 clamp_coord(ivec2 p, ivec2 size) {
	return clamp(p, ivec2(0), size - ivec2(1));
}

vec3 sample_rgb(ivec2 p, ivec2 size) {
	return imageLoad(source_image, clamp_coord(p, size)).rgb;
}

float luma(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 bright(vec3 c) {
	float m = smoothstep(params.glow_threshold, params.glow_threshold + 0.08, luma(c));
	return c * m;
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(params.raster_size);
	if (p.x >= size.x || p.y >= size.y) return;

	vec3 center = sample_rgb(p, size);
	vec3 color = center;

	if (params.blur > 0.001) {
		int r = max(1, int(round(params.blur)));
		ivec2 dx = ivec2(r, 0);
		ivec2 dy = ivec2(0, r);
		ivec2 d1 = ivec2(r, r);
		ivec2 d2 = ivec2(r, -r);
		vec3 b = center * 0.24;
		b += sample_rgb(p + dx, size) * 0.12;
		b += sample_rgb(p - dx, size) * 0.12;
		b += sample_rgb(p + dy, size) * 0.12;
		b += sample_rgb(p - dy, size) * 0.12;
		b += sample_rgb(p + d1, size) * 0.07;
		b += sample_rgb(p - d1, size) * 0.07;
		b += sample_rgb(p + d2, size) * 0.07;
		b += sample_rgb(p - d2, size) * 0.07;
		color = mix(center, b, clamp(params.blur / 8.0, 0.0, 1.0));
	}

	if (params.aberration > 0.001) {
		vec2 uv = (vec2(p) + vec2(0.5)) / vec2(size);
		vec2 radial = uv - vec2(0.5);
		ivec2 shift = ivec2(round(radial * params.aberration * 24.0));
		color.r = sample_rgb(p + shift, size).r;
		color.b = sample_rgb(p - shift, size).b;
	}

	color *= exp2(params.exposure);
	float y = luma(color);
	color = mix(vec3(y), color, params.saturation);
	color = (color - vec3(0.5)) * params.contrast + vec3(0.5);
	color.r += params.temperature * 0.15;
	color.b -= params.temperature * 0.15;
	color.g += params.tint * 0.10;
	color.r -= params.tint * 0.04;
	color.b -= params.tint * 0.04;

	float gray = luma(color);
	color = mix(color, vec3(gray), params.monochrome);

	if (params.glow_strength > 0.001) {
		int r = max(1, int(round(params.glow_radius)));
		ivec2 dx = ivec2(r, 0);
		ivec2 dy = ivec2(0, r);
		ivec2 d1 = ivec2(r, r);
		ivec2 d2 = ivec2(r, -r);
		vec3 bloom = bright(sample_rgb(p, size));
		bloom += bright(sample_rgb(p + dx, size));
		bloom += bright(sample_rgb(p - dx, size));
		bloom += bright(sample_rgb(p + dy, size));
		bloom += bright(sample_rgb(p - dy, size));
		bloom += bright(sample_rgb(p + d1, size));
		bloom += bright(sample_rgb(p - d1, size));
		bloom += bright(sample_rgb(p + d2, size));
		bloom += bright(sample_rgb(p - d2, size));
		color += bloom * (params.glow_strength / 9.0);
	}

	if (params.vignette > 0.001) {
		vec2 uv = (vec2(p) + vec2(0.5)) / vec2(size);
		vec2 q = (uv - vec2(0.5)) * vec2(1.0, 0.82);
		float v = smoothstep(0.30, 0.72, length(q));
		color *= 1.0 - v * params.vignette;
	}

	imageStore(dest_image, p, vec4(max(color, vec3(0.0)), 1.0));
}
"""

var rd: RenderingDevice
var copy_shader := RID()
var copy_pipeline := RID()
var process_shader := RID()
var process_pipeline := RID()
var params_mutex := Mutex.new()
var params := {
	"blur": 0.0,
	"glow_strength": 0.0,
	"glow_threshold": 0.7,
	"glow_radius": 3.0,
	"exposure": 0.0,
	"saturation": 1.0,
	"contrast": 1.0,
	"temperature": 0.0,
	"color_tint": 0.0,
	"vignette": 0.0,
	"chromatic_aberration": 0.0,
	"monochrome": 0.0
}

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	access_resolved_color = true
	access_resolved_depth = true
	rd = RenderingServer.get_rendering_device()

func set_parameters(values: Dictionary) -> void:
	params_mutex.lock()
	for key in values:
		if params.has(key):
			params[key] = float(values[key])
	params_mutex.unlock()

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and rd:
		if copy_shader.is_valid(): rd.free_rid(copy_shader)
		if process_shader.is_valid(): rd.free_rid(process_shader)

func _compile_compute(source: String) -> RID:
	var shader_source := RDShaderSource.new()
	shader_source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	shader_source.source_compute = source
	var spirv := rd.shader_compile_spirv_from_source(shader_source)
	if spirv.compile_error_compute != "":
		push_error("Kabuki compositor shader: " + spirv.compile_error_compute)
		return RID()
	return rd.shader_create_from_spirv(spirv)

func _ensure_pipelines() -> bool:
	if rd == null: return false
	if not copy_shader.is_valid():
		copy_shader = _compile_compute(COPY_SHADER)
		if not copy_shader.is_valid(): return false
		copy_pipeline = rd.compute_pipeline_create(copy_shader)
	if not process_shader.is_valid():
		process_shader = _compile_compute(PROCESS_SHADER)
		if not process_shader.is_valid(): return false
		process_pipeline = rd.compute_pipeline_create(process_shader)
	return copy_pipeline.is_valid() and process_pipeline.is_valid()

func _uniform_set(shader_rid: RID, source: RID, dest: RID) -> RID:
	var src := RDUniform.new()
	src.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	src.binding = 0
	src.add_id(source)
	var dst := RDUniform.new()
	dst.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
	dst.binding = 1
	dst.add_id(dest)
	return UniformSetCacheRD.get_cache(shader_rid, 0, [src, dst])

func _params_push(size: Vector2i) -> PackedByteArray:
	params_mutex.lock()
	var p := params.duplicate()
	params_mutex.unlock()
	var values := PackedFloat32Array([
		float(size.x), float(size.y),
		float(p["blur"]),
		float(p["glow_strength"]),
		float(p["glow_threshold"]),
		float(p["glow_radius"]),
		float(p["exposure"]),
		float(p["saturation"]),
		float(p["contrast"]),
		float(p["temperature"]),
		float(p["color_tint"]),
		float(p["vignette"]),
		float(p["chromatic_aberration"]),
		float(p["monochrome"]),
		0.0, 0.0
	])
	return values.to_byte_array()

func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if not enabled or callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	if not _ensure_pipelines():
		return
	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return

	# Reserve a full-resolution intermediate. The resolved depth/Z buffer is also
	# requested above and is now available for depth-aware effects such as DOF.
	buffers.create_texture(
		CONTEXT,
		SCRATCH,
		RenderingDevice.DATA_FORMAT_R16G16B16A16_SFLOAT,
		RenderingDevice.TEXTURE_USAGE_STORAGE_BIT,
		RenderingDevice.TEXTURE_SAMPLES_1,
		size,
		buffers.get_view_count(),
		1,
		false,
		false
	)

	var copy_push := PackedFloat32Array([float(size.x), float(size.y), 0.0, 0.0]).to_byte_array()
	var process_push := _params_push(size)
	var gx := (size.x - 1) / 8 + 1
	var gy := (size.y - 1) / 8 + 1

	for view in range(buffers.get_view_count()):
		var color_image := buffers.get_color_layer(view)
		var scratch_image := buffers.get_texture_slice(CONTEXT, SCRATCH, view, 0, 1, 1)
		if not color_image.is_valid() or not scratch_image.is_valid():
			continue
		var copy_set := _uniform_set(copy_shader, color_image, scratch_image)
		var process_set := _uniform_set(process_shader, scratch_image, color_image)
		var list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list, copy_pipeline)
		rd.compute_list_bind_uniform_set(list, copy_set, 0)
		rd.compute_list_set_push_constant(list, copy_push, copy_push.size())
		rd.compute_list_dispatch(list, gx, gy, 1)
		rd.compute_list_add_barrier(list)
		rd.compute_list_bind_compute_pipeline(list, process_pipeline)
		rd.compute_list_bind_uniform_set(list, process_set, 0)
		rd.compute_list_set_push_constant(list, process_push, process_push.size())
		rd.compute_list_dispatch(list, gx, gy, 1)
		rd.compute_list_end()
