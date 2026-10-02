@tool
extends CompositorEffect
class_name KabukiCompositorEffect

const PROCESS_SHADER := """
#version 450
layout(local_size_x = 8, local_size_y = 8, local_size_z = 1) in;

layout(rgba16f, set = 0, binding = 0) uniform image2D color_image;

layout(push_constant, std430) uniform Params {
	vec2 raster_size;
	float exposure;
	float saturation;
	float contrast;
	float temperature;
	float tint;
	float vignette;
	float aberration;
	float monochrome;
	float blur;
	float glow_strength;
	float glow_threshold;
	float glow_radius;
	float pad0;
	float pad1;
} params;

float luminance(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

void main() {
	ivec2 p = ivec2(gl_GlobalInvocationID.xy);
	ivec2 size = ivec2(params.raster_size);
	if (p.x >= size.x || p.y >= size.y) {
		return;
	}

	vec4 original = imageLoad(color_image, p);
	vec3 color = original.rgb;

	color *= exp2(params.exposure);

	float y = luminance(color);
	color = mix(vec3(y), color, params.saturation);
	color = (color - vec3(0.5)) * params.contrast + vec3(0.5);

	color.r += params.temperature * 0.15;
	color.b -= params.temperature * 0.15;
	color.g += params.tint * 0.10;
	color.r -= params.tint * 0.04;
	color.b -= params.tint * 0.04;

	float gray = luminance(color);
	color = mix(color, vec3(gray), params.monochrome);

	if (params.vignette > 0.001) {
		vec2 uv = (vec2(p) + vec2(0.5)) / vec2(size);
		vec2 q = (uv - vec2(0.5)) * vec2(1.0, 0.82);
		float v = smoothstep(0.30, 0.72, length(q));
		color *= 1.0 - v * params.vignette;
	}

	imageStore(color_image, p, vec4(max(color, vec3(0.0)), original.a));
}
"""

var rd: RenderingDevice
var shader := RID()
var pipeline := RID()
var mutex := Mutex.new()
var shader_dirty := true
var callback_count := 0

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
	mutex.lock()
	for key in values:
		if params.has(key):
			params[key] = float(values[key])
	mutex.unlock()

func is_rendering_device_available() -> bool:
	return rd != null

func get_callback_count() -> int:
	return callback_count

func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and rd != null:
		if shader.is_valid():
			rd.free_rid(shader)

func _check_shader() -> bool:
	if rd == null:
		return false
	if not shader_dirty:
		return pipeline.is_valid()
	shader_dirty = false

	var shader_source := RDShaderSource.new()
	shader_source.language = RenderingDevice.SHADER_LANGUAGE_GLSL
	shader_source.source_compute = PROCESS_SHADER
	var spirv := rd.shader_compile_spirv_from_source(shader_source)
	if spirv.compile_error_compute != "":
		push_error("Kabuki compositor compute shader: " + spirv.compile_error_compute)
		return false

	shader = rd.shader_create_from_spirv(spirv)
	if not shader.is_valid():
		push_error("Kabuki compositor: unable to create compute shader")
		return false
	pipeline = rd.compute_pipeline_create(shader)
	if not pipeline.is_valid():
		push_error("Kabuki compositor: unable to create compute pipeline")
		return false
	return true

func _push_constants(size: Vector2i) -> PackedByteArray:
	mutex.lock()
	var p := params.duplicate()
	mutex.unlock()
	# 16 floats = 64 bytes, correctly aligned for push constants.
	var values := PackedFloat32Array([
		float(size.x), float(size.y),
		float(p["exposure"]),
		float(p["saturation"]),
		float(p["contrast"]),
		float(p["temperature"]),
		float(p["color_tint"]),
		float(p["vignette"]),
		float(p["chromatic_aberration"]),
		float(p["monochrome"]),
		float(p["blur"]),
		float(p["glow_strength"]),
		float(p["glow_threshold"]),
		float(p["glow_radius"]),
		0.0, 0.0
	])
	return values.to_byte_array()

func _render_callback(callback_type: int, render_data: RenderData) -> void:
	if not enabled:
		return
	if callback_type != EFFECT_CALLBACK_TYPE_POST_TRANSPARENT:
		return
	if rd == null or not _check_shader():
		return

	var buffers := render_data.get_render_scene_buffers() as RenderSceneBuffersRD
	if buffers == null:
		return
	var size := buffers.get_internal_size()
	if size.x <= 0 or size.y <= 0:
		return

	callback_count += 1
	var push := _push_constants(size)
	var gx := (size.x - 1) / 8 + 1
	var gy := (size.y - 1) / 8 + 1

	for view in range(buffers.get_view_count()):
		var color_image := buffers.get_color_layer(view)
		if not color_image.is_valid():
			continue

		var uniform := RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = 0
		uniform.add_id(color_image)
		var uniform_set := UniformSetCacheRD.get_cache(shader, 0, [uniform])

		var list := rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(list, pipeline)
		rd.compute_list_bind_uniform_set(list, uniform_set, 0)
		rd.compute_list_set_push_constant(list, push, push.size())
		rd.compute_list_dispatch(list, gx, gy, 1)
		rd.compute_list_end()
