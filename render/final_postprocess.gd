class_name FinalPostProcess
extends TextureRect

var effect_material: ShaderMaterial
var source_texture: Texture2D
var filter_values: Dictionary = {}
var effect_order: Array[String] = [
	"lens_aberration",
	"blur",
	"glow",
	"color",
	"vignette",
	"monochrome",
	"noise"
]
var rounded_mask_enabled := false
var rounded_control_size := Vector2(800.0,600.0)
var rounded_corner_radius := 16.0

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	stretch_mode = TextureRect.STRETCH_SCALE
	effect_material = ShaderMaterial.new()
	material = effect_material
	_rebuild_effect_shader()

func set_source_texture(source: Texture2D) -> void:
	source_texture = source
	texture = source
	queue_redraw()

func set_filters(values: Dictionary) -> void:
	filter_values = values.duplicate(true)
	_apply_uniforms()
	queue_redraw()

func set_effect_order(order: Array) -> void:
	var cleaned: Array[String] = []
	for value in order:
		var key := String(value)
		if ["lens_aberration","blur","glow","color","vignette","monochrome","noise"].has(key) and not cleaned.has(key):
			cleaned.append(key)
	for fallback in ["lens_aberration","blur","glow","color","vignette","monochrome","noise"]:
		if not cleaned.has(fallback):
			cleaned.append(fallback)
	if cleaned == effect_order and effect_material != null and effect_material.shader != null:
		return
	effect_order = cleaned
	_rebuild_effect_shader()

func get_effect_order() -> Array[String]:
	return effect_order.duplicate()

func set_viewport_mask(enabled: bool, control_size: Vector2, radius: float = 16.0) -> void:
	rounded_mask_enabled = enabled
	rounded_control_size = control_size
	rounded_corner_radius = radius
	_apply_uniforms()
	queue_redraw()

func _shader_header() -> String:
	return """shader_type canvas_item;

uniform float blur = 0.0;
uniform float glow_strength = 0.0;
uniform float glow_threshold = 0.7;
uniform float glow_radius = 3.0;
uniform float exposure = 0.0;
uniform float saturation = 1.0;
uniform float contrast = 1.0;
uniform float temperature = 0.0;
uniform float color_tint = 0.0;
uniform float vignette = 0.0;
uniform float chromatic_aberration = 0.0;
uniform float monochrome = 0.0;
uniform float noise_amount = 0.0;
uniform float noise_seed = 0.0;
uniform float noise_colored = 0.0;

uniform float rounded_mask_enabled = 0.0;
uniform vec2 rounded_control_size = vec2(800.0,600.0);
uniform float rounded_corner_radius = 16.0;

float luminance_of(vec3 c) {
	return dot(c,vec3(0.2126,0.7152,0.0722));
}

float grain_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx)*0.1031);
	p3 += dot(p3,p3.yzx+33.33+noise_seed);
	return fract((p3.x+p3.y)*p3.z);
}

vec3 grain_rgb(vec2 pixel) {
	float n1 = grain_hash(pixel)-0.5;
	if (noise_colored < 0.5) return vec3(n1);
	float n2 = grain_hash(pixel+vec2(17.23,9.71))-0.5;
	float n3 = grain_hash(pixel+vec2(41.11,27.59))-0.5;
	return vec3(n1,n2,n3);
}

vec3 fx0(vec2 uv) {
	return texture(TEXTURE,clamp(uv,vec2(0.0),vec2(1.0))).rgb;
}

"""

func _stage_source(effect_id: String, stage: int) -> String:
	var prev := "fx%d" % (stage-1)
	var fn := "fx%d" % stage
	match effect_id:
		"lens_aberration":
			return """vec3 %s(vec2 uv) {
	vec2 safe_uv = clamp(uv,vec2(0.0),vec2(1.0));
	vec2 radial = safe_uv-vec2(0.5);
	vec2 shift = radial*chromatic_aberration*0.02;
	vec3 c = %s(safe_uv);
	c.r = %s(safe_uv+shift).r;
	c.b = %s(safe_uv-shift).b;
	return c;
}

""" % [fn,prev,prev,prev]
		"blur":
			# Isotropic 13-tap Gaussian-like kernel. Because every tap calls the
			# previous stack stage, effects above Blur are blurred too.
			return """vec3 %s(vec2 uv) {
	vec2 px = TEXTURE_PIXEL_SIZE*max(0.25,blur*0.55);
	vec3 c = %s(uv)*0.20;
	c += %s(uv+vec2( px.x,0.0))*0.10;
	c += %s(uv+vec2(-px.x,0.0))*0.10;
	c += %s(uv+vec2(0.0, px.y))*0.10;
	c += %s(uv+vec2(0.0,-px.y))*0.10;
	c += %s(uv+vec2( px.x, px.y))*0.075;
	c += %s(uv+vec2(-px.x, px.y))*0.075;
	c += %s(uv+vec2( px.x,-px.y))*0.075;
	c += %s(uv+vec2(-px.x,-px.y))*0.075;
	c += %s(uv+vec2(2.0*px.x,0.0))*0.025;
	c += %s(uv+vec2(-2.0*px.x,0.0))*0.025;
	c += %s(uv+vec2(0.0,2.0*px.y))*0.025;
	c += %s(uv+vec2(0.0,-2.0*px.y))*0.025;
	return c;
}

""" % [fn,prev,prev,prev,prev,prev,prev,prev,prev,prev,prev,prev,prev,prev]
		"glow":
			return """vec3 %s(vec2 uv) {
	vec2 g = TEXTURE_PIXEL_SIZE*max(0.5,glow_radius);
	vec3 base = %s(uv);
	vec3 bloom = vec3(0.0);
	vec3 s0 = base;
	vec3 s1 = %s(uv+vec2( g.x,0.0));
	vec3 s2 = %s(uv+vec2(-g.x,0.0));
	vec3 s3 = %s(uv+vec2(0.0, g.y));
	vec3 s4 = %s(uv+vec2(0.0,-g.y));
	vec3 s5 = %s(uv+vec2( g.x, g.y));
	vec3 s6 = %s(uv+vec2(-g.x, g.y));
	vec3 s7 = %s(uv+vec2( g.x,-g.y));
	vec3 s8 = %s(uv+vec2(-g.x,-g.y));
	bloom += s0*smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s0));
	bloom += s1*smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s1));
	bloom += s2*smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s2));
	bloom += s3*smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s3));
	bloom += s4*smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s4));
	bloom += s5*smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s5));
	bloom += s6*smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s6));
	bloom += s7*smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s7));
	bloom += s8*smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s8));
	return base+bloom*(glow_strength/9.0);
}

""" % [fn,prev,prev,prev,prev,prev,prev,prev,prev,prev]
		"color":
			return """vec3 %s(vec2 uv) {
	vec3 c = %s(uv);
	c *= exp2(exposure);
	float y = luminance_of(c);
	c = mix(vec3(y),c,saturation);
	c = (c-vec3(0.5))*contrast+vec3(0.5);
	c.r += temperature*0.15;
	c.b -= temperature*0.15;
	c.g += color_tint*0.10;
	c.r -= color_tint*0.04;
	c.b -= color_tint*0.04;
	return c;
}

""" % [fn,prev]
		"vignette":
			return """vec3 %s(vec2 uv) {
	vec3 c = %s(uv);
	vec2 q = (uv-vec2(0.5))*vec2(1.0,0.82);
	float v = smoothstep(0.30,0.72,length(q));
	return c*(1.0-v*vignette);
}

""" % [fn,prev]
		"monochrome":
			return """vec3 %s(vec2 uv) {
	vec3 c = %s(uv);
	float gray = luminance_of(c);
	return mix(c,vec3(gray),monochrome);
}

""" % [fn,prev]
		"noise":
			return """vec3 %s(vec2 uv) {
	vec3 c = %s(uv);
	vec2 pixel = floor(uv/max(TEXTURE_PIXEL_SIZE,vec2(0.000001)));
	return c+grain_rgb(pixel)*noise_amount;
}

""" % [fn,prev]
		_:
			return """vec3 %s(vec2 uv) { return %s(uv); }

""" % [fn,prev]

func _shader_footer(last_stage: int) -> String:
	return """void fragment() {
	vec2 uv = clamp(UV,vec2(0.0),vec2(1.0));
	vec3 color = fx%d(uv);
	float output_alpha = texture(TEXTURE,uv).a;
	if (rounded_mask_enabled > 0.5) {
		vec2 screen_px = UV*rounded_control_size;
		vec2 half_size = rounded_control_size*0.5;
		vec2 p = abs(screen_px-half_size)-(half_size-vec2(rounded_corner_radius));
		float corner_distance = length(max(p,vec2(0.0)))+min(max(p.x,p.y),0.0)-rounded_corner_radius;
		float aa = max(fwidth(corner_distance),0.75);
		output_alpha *= 1.0-smoothstep(-aa,aa,corner_distance);
	}
	COLOR = vec4(max(color,vec3(0.0)),output_alpha);
}
""" % last_stage

func _rebuild_effect_shader() -> void:
	if effect_material == null:
		return
	var source := _shader_header()
	var stage := 1
	for effect_id in effect_order:
		source += _stage_source(effect_id,stage)
		stage += 1
	source += _shader_footer(stage-1)
	var shader := Shader.new()
	shader.code = source
	effect_material.shader = shader
	material = effect_material
	_apply_uniforms()
	queue_redraw()

func _apply_uniforms() -> void:
	if effect_material == null or effect_material.shader == null:
		return
	for key in filter_values:
		effect_material.set_shader_parameter(StringName(key),filter_values[key])
	effect_material.set_shader_parameter("rounded_mask_enabled",1.0 if rounded_mask_enabled else 0.0)
	effect_material.set_shader_parameter("rounded_control_size",rounded_control_size)
	effect_material.set_shader_parameter("rounded_corner_radius",rounded_corner_radius)
