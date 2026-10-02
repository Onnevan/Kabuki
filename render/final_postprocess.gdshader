shader_type canvas_item;

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

float luminance_of(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

vec3 bright_part(vec3 c) {
	float y = luminance_of(c);
	float mask = smoothstep(glow_threshold, glow_threshold + 0.08, y);
	return c * mask;
}

void fragment() {
	vec2 uv = clamp(UV, vec2(0.0), vec2(1.0));
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec3 center = texture(TEXTURE, uv).rgb;
	vec3 color = center;

	if (blur > 0.001) {
		vec2 d = px * blur;
		vec3 b = center * 0.24;
		b += texture(TEXTURE, clamp(uv + vec2( d.x, 0.0), vec2(0.0), vec2(1.0))).rgb * 0.12;
		b += texture(TEXTURE, clamp(uv + vec2(-d.x, 0.0), vec2(0.0), vec2(1.0))).rgb * 0.12;
		b += texture(TEXTURE, clamp(uv + vec2(0.0,  d.y), vec2(0.0), vec2(1.0))).rgb * 0.12;
		b += texture(TEXTURE, clamp(uv + vec2(0.0, -d.y), vec2(0.0), vec2(1.0))).rgb * 0.12;
		b += texture(TEXTURE, clamp(uv + vec2( d.x,  d.y), vec2(0.0), vec2(1.0))).rgb * 0.07;
		b += texture(TEXTURE, clamp(uv + vec2(-d.x,  d.y), vec2(0.0), vec2(1.0))).rgb * 0.07;
		b += texture(TEXTURE, clamp(uv + vec2( d.x, -d.y), vec2(0.0), vec2(1.0))).rgb * 0.07;
		b += texture(TEXTURE, clamp(uv + vec2(-d.x, -d.y), vec2(0.0), vec2(1.0))).rgb * 0.07;
		color = mix(center, b, clamp(blur / 8.0, 0.0, 1.0));
	}

	if (chromatic_aberration > 0.001) {
		vec2 radial = uv - vec2(0.5);
		vec2 shift = radial * chromatic_aberration * 0.02;
		color.r = texture(TEXTURE, clamp(uv + shift, vec2(0.0), vec2(1.0))).r;
		color.b = texture(TEXTURE, clamp(uv - shift, vec2(0.0), vec2(1.0))).b;
	}

	color *= exp2(exposure);

	float y = luminance_of(color);
	color = mix(vec3(y), color, saturation);
	color = (color - vec3(0.5)) * contrast + vec3(0.5);

	color.r += temperature * 0.15;
	color.b -= temperature * 0.15;
	color.g += color_tint * 0.10;
	color.r -= color_tint * 0.04;
	color.b -= color_tint * 0.04;

	float gray = luminance_of(color);
	color = mix(color, vec3(gray), monochrome);

	if (glow_strength > 0.001) {
		vec2 g = px * glow_radius;
		vec3 bloom = bright_part(center);
		bloom += bright_part(texture(TEXTURE, clamp(uv + vec2( g.x, 0.0), vec2(0.0), vec2(1.0))).rgb);
		bloom += bright_part(texture(TEXTURE, clamp(uv + vec2(-g.x, 0.0), vec2(0.0), vec2(1.0))).rgb);
		bloom += bright_part(texture(TEXTURE, clamp(uv + vec2(0.0,  g.y), vec2(0.0), vec2(1.0))).rgb);
		bloom += bright_part(texture(TEXTURE, clamp(uv + vec2(0.0, -g.y), vec2(0.0), vec2(1.0))).rgb);
		bloom += bright_part(texture(TEXTURE, clamp(uv + vec2( g.x,  g.y), vec2(0.0), vec2(1.0))).rgb);
		bloom += bright_part(texture(TEXTURE, clamp(uv + vec2(-g.x,  g.y), vec2(0.0), vec2(1.0))).rgb);
		bloom += bright_part(texture(TEXTURE, clamp(uv + vec2( g.x, -g.y), vec2(0.0), vec2(1.0))).rgb);
		bloom += bright_part(texture(TEXTURE, clamp(uv + vec2(-g.x, -g.y), vec2(0.0), vec2(1.0))).rgb);
		color += bloom * (glow_strength / 9.0);
	}

	if (vignette > 0.001) {
		vec2 q = (uv - vec2(0.5)) * vec2(1.0, 0.82);
		float v = smoothstep(0.30, 0.72, length(q));
		color *= 1.0 - v * vignette;
	}

	COLOR = vec4(max(color, vec3(0.0)), 1.0);
}
