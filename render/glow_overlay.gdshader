shader_type canvas_item;
render_mode unshaded;

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

vec3 src(vec2 uv) {
	return texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
}

vec3 blurred(vec2 uv, float amount) {
	if (amount <= 0.001) {
		return src(uv);
	}
	vec2 p = TEXTURE_PIXEL_SIZE * amount;
	vec3 c = src(uv) * 0.24;
	c += src(uv + vec2( p.x, 0.0)) * 0.12;
	c += src(uv + vec2(-p.x, 0.0)) * 0.12;
	c += src(uv + vec2(0.0,  p.y)) * 0.12;
	c += src(uv + vec2(0.0, -p.y)) * 0.12;
	c += src(uv + vec2( p.x,  p.y)) * 0.07;
	c += src(uv + vec2(-p.x,  p.y)) * 0.07;
	c += src(uv + vec2( p.x, -p.y)) * 0.07;
	c += src(uv + vec2(-p.x, -p.y)) * 0.07;
	return c;
}

vec3 bright(vec3 c) {
	float l = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float m = smoothstep(glow_threshold, glow_threshold + 0.08, l);
	return c * m;
}

void fragment() {
	vec2 uv = UV;
	vec3 color;

	if (chromatic_aberration > 0.001) {
		vec2 d = uv - vec2(0.5);
		vec2 s = d * chromatic_aberration * 0.02;
		color = vec3(
			blurred(uv + s, blur).r,
			blurred(uv, blur).g,
			blurred(uv - s, blur).b
		);
	} else {
		color = blurred(uv, blur);
	}

	color *= exp2(exposure);

	float lum = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(lum), color, saturation);
	color = (color - vec3(0.5)) * contrast + vec3(0.5);

	color.r += temperature * 0.15;
	color.b -= temperature * 0.15;
	color.g += color_tint * 0.10;
	color.r -= color_tint * 0.04;
	color.b -= color_tint * 0.04;

	float bw = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(color, vec3(bw), monochrome);

	if (glow_strength > 0.001) {
		vec2 g = TEXTURE_PIXEL_SIZE * glow_radius;
		vec3 bloom = bright(src(uv + vec2( g.x, 0.0)));
		bloom += bright(src(uv + vec2(-g.x, 0.0)));
		bloom += bright(src(uv + vec2(0.0,  g.y)));
		bloom += bright(src(uv + vec2(0.0, -g.y)));
		bloom += bright(src(uv + vec2( g.x,  g.y)));
		bloom += bright(src(uv + vec2(-g.x,  g.y)));
		bloom += bright(src(uv + vec2( g.x, -g.y)));
		bloom += bright(src(uv + vec2(-g.x, -g.y)));
		color += bloom * (0.125 * glow_strength);
	}

	if (vignette > 0.001) {
		vec2 p = (uv - vec2(0.5)) * vec2(1.0, 0.82);
		float v = smoothstep(0.30, 0.72, length(p));
		color *= 1.0 - v * vignette;
	}

	COLOR = vec4(clamp(color, vec3(0.0), vec3(8.0)), 1.0);
}
