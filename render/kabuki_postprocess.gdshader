shader_type spatial;
render_mode unshaded, fog_disabled, depth_draw_never, cull_disabled, shadows_disabled;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform sampler2D depth_texture : hint_depth_texture, repeat_disable, filter_nearest;

uniform float blur : hint_range(0.0, 12.0) = 0.0;
uniform float glow_strength : hint_range(0.0, 3.0) = 0.0;
uniform float glow_threshold : hint_range(0.0, 2.0) = 0.7;
uniform float glow_radius : hint_range(0.5, 24.0) = 3.0;

uniform float exposure : hint_range(-4.0, 4.0) = 0.0;
uniform float saturation : hint_range(0.0, 2.0) = 1.0;
uniform float contrast : hint_range(0.0, 2.0) = 1.0;
uniform float temperature : hint_range(-1.0, 1.0) = 0.0;
uniform float color_tint : hint_range(-1.0, 1.0) = 0.0;

uniform float vignette : hint_range(0.0, 1.0) = 0.0;
uniform float chromatic_aberration : hint_range(0.0, 1.0) = 0.0;
uniform float monochrome : hint_range(0.0, 1.0) = 0.0;

void vertex() {
	// Fullscreen quad in clip space, independent of camera transform/projection.
	POSITION = vec4(VERTEX.xy, 1.0, 1.0);
}

vec3 src(vec2 uv) {
	return textureLod(screen_texture, clamp(uv, vec2(0.0), vec2(1.0)), 0.0).rgb;
}

float lum(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 bright(vec3 c) {
	float m = smoothstep(glow_threshold, glow_threshold + 0.08, lum(c));
	return c * m;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = 1.0 / vec2(textureSize(screen_texture, 0));
	vec3 center = src(uv);
	vec3 color = center;

	if (blur > 0.001) {
		vec2 d = px * blur;
		vec3 b = center * 0.24;
		b += src(uv + vec2( d.x, 0.0)) * 0.12;
		b += src(uv + vec2(-d.x, 0.0)) * 0.12;
		b += src(uv + vec2(0.0,  d.y)) * 0.12;
		b += src(uv + vec2(0.0, -d.y)) * 0.12;
		b += src(uv + vec2( d.x,  d.y)) * 0.07;
		b += src(uv + vec2(-d.x,  d.y)) * 0.07;
		b += src(uv + vec2( d.x, -d.y)) * 0.07;
		b += src(uv + vec2(-d.x, -d.y)) * 0.07;
		color = mix(center, b, clamp(blur / 8.0, 0.0, 1.0));
	}

	if (chromatic_aberration > 0.001) {
		vec2 radial = uv - vec2(0.5);
		vec2 shift = radial * chromatic_aberration * 0.02;
		color.r = src(uv + shift).r;
		color.b = src(uv - shift).b;
	}

	color *= exp2(exposure);
	float y = lum(color);
	color = mix(vec3(y), color, saturation);
	color = (color - vec3(0.5)) * contrast + vec3(0.5);

	color.r += temperature * 0.15;
	color.b -= temperature * 0.15;
	color.g += color_tint * 0.10;
	color.r -= color_tint * 0.04;
	color.b -= color_tint * 0.04;

	float gray = lum(color);
	color = mix(color, vec3(gray), monochrome);

	if (glow_strength > 0.001) {
		vec2 g = px * glow_radius;
		vec3 bloom = bright(src(uv));
		bloom += bright(src(uv + vec2( g.x, 0.0)));
		bloom += bright(src(uv + vec2(-g.x, 0.0)));
		bloom += bright(src(uv + vec2(0.0,  g.y)));
		bloom += bright(src(uv + vec2(0.0, -g.y)));
		bloom += bright(src(uv + vec2( g.x,  g.y)));
		bloom += bright(src(uv + vec2(-g.x,  g.y)));
		bloom += bright(src(uv + vec2( g.x, -g.y)));
		bloom += bright(src(uv + vec2(-g.x, -g.y)));
		color += bloom * (glow_strength / 9.0);
	}

	if (vignette > 0.001) {
		vec2 q = (uv - vec2(0.5)) * vec2(1.0, 0.82);
		float v = smoothstep(0.30, 0.72, length(q));
		color *= 1.0 - v * vignette;
	}

	ALBEDO = max(color, vec3(0.0));
	ALPHA = 1.0;
}
