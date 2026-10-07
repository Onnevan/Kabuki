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
uniform float noise_amount : hint_range(0.0, 1.0) = 0.0;
uniform float noise_seed = 0.0;
uniform float noise_colored : hint_range(0.0, 1.0) = 0.0;

uniform float rounded_mask_enabled : hint_range(0.0, 1.0) = 0.0;
uniform vec2 rounded_control_size = vec2(800.0, 600.0);
uniform float rounded_corner_radius = 16.0;

float luminance_of(vec3 c) {
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float grain_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33 + noise_seed);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 grain_rgb(vec2 pixel) {
	float n1 = grain_hash(pixel) - 0.5;
	if (noise_colored < 0.5) {
		return vec3(n1);
	}
	float n2 = grain_hash(pixel + vec2(17.23, 9.71)) - 0.5;
	float n3 = grain_hash(pixel + vec2(41.11, 27.59)) - 0.5;
	return vec3(n1, n2, n3);
}

vec3 bright_part(vec3 c) {
	float y = luminance_of(c);
	float mask = smoothstep(glow_threshold, glow_threshold + 0.08, y);
	return c * mask;
}

vec3 sample_compositor_source(vec2 uv) {
	vec2 safe_uv = clamp(uv, vec2(0.0), vec2(1.0));
	vec3 sampled = texture(TEXTURE, safe_uv).rgb;
	if (chromatic_aberration > 0.001) {
		vec2 radial = safe_uv - vec2(0.5);
		vec2 shift = radial * chromatic_aberration * 0.02;
		sampled.r = texture(TEXTURE, clamp(safe_uv + shift, vec2(0.0), vec2(1.0))).r;
		sampled.b = texture(TEXTURE, clamp(safe_uv - shift, vec2(0.0), vec2(1.0))).b;
	}
	return sampled;
}

void fragment() {
	vec2 uv = clamp(UV, vec2(0.0), vec2(1.0));
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec3 center = sample_compositor_source(uv);
	vec3 color = center;

	if (blur > 0.001) {
		// 5x5 separable Gaussian kernel using Pascal weights [1 4 6 4 1].
		// The previous sparse 3x3 taps produced visibly square/diamond-shaped
		// bokeh around high-contrast strokes. This is a true Gaussian kernel.
		vec2 d = px * max(0.25, blur * 0.5);
		vec3 b = vec3(0.0);
		b += sample_compositor_source(clamp(uv + vec2(-2.0*d.x,-2.0*d.y), vec2(0.0), vec2(1.0))) * 1.0;
		b += sample_compositor_source(clamp(uv + vec2(-1.0*d.x,-2.0*d.y), vec2(0.0), vec2(1.0))) * 4.0;
		b += sample_compositor_source(clamp(uv + vec2( 0.0,     -2.0*d.y), vec2(0.0), vec2(1.0))) * 6.0;
		b += sample_compositor_source(clamp(uv + vec2( 1.0*d.x,-2.0*d.y), vec2(0.0), vec2(1.0))) * 4.0;
		b += sample_compositor_source(clamp(uv + vec2( 2.0*d.x,-2.0*d.y), vec2(0.0), vec2(1.0))) * 1.0;

		b += sample_compositor_source(clamp(uv + vec2(-2.0*d.x,-1.0*d.y), vec2(0.0), vec2(1.0))) * 4.0;
		b += sample_compositor_source(clamp(uv + vec2(-1.0*d.x,-1.0*d.y), vec2(0.0), vec2(1.0))) * 16.0;
		b += sample_compositor_source(clamp(uv + vec2( 0.0,     -1.0*d.y), vec2(0.0), vec2(1.0))) * 24.0;
		b += sample_compositor_source(clamp(uv + vec2( 1.0*d.x,-1.0*d.y), vec2(0.0), vec2(1.0))) * 16.0;
		b += sample_compositor_source(clamp(uv + vec2( 2.0*d.x,-1.0*d.y), vec2(0.0), vec2(1.0))) * 4.0;

		b += sample_compositor_source(clamp(uv + vec2(-2.0*d.x,0.0), vec2(0.0), vec2(1.0))) * 6.0;
		b += sample_compositor_source(clamp(uv + vec2(-1.0*d.x,0.0), vec2(0.0), vec2(1.0))) * 24.0;
		b += center * 36.0;
		b += sample_compositor_source(clamp(uv + vec2( 1.0*d.x,0.0), vec2(0.0), vec2(1.0))) * 24.0;
		b += sample_compositor_source(clamp(uv + vec2( 2.0*d.x,0.0), vec2(0.0), vec2(1.0))) * 6.0;

		b += sample_compositor_source(clamp(uv + vec2(-2.0*d.x, 1.0*d.y), vec2(0.0), vec2(1.0))) * 4.0;
		b += sample_compositor_source(clamp(uv + vec2(-1.0*d.x, 1.0*d.y), vec2(0.0), vec2(1.0))) * 16.0;
		b += sample_compositor_source(clamp(uv + vec2( 0.0,       1.0*d.y), vec2(0.0), vec2(1.0))) * 24.0;
		b += sample_compositor_source(clamp(uv + vec2( 1.0*d.x, 1.0*d.y), vec2(0.0), vec2(1.0))) * 16.0;
		b += sample_compositor_source(clamp(uv + vec2( 2.0*d.x, 1.0*d.y), vec2(0.0), vec2(1.0))) * 4.0;

		b += sample_compositor_source(clamp(uv + vec2(-2.0*d.x, 2.0*d.y), vec2(0.0), vec2(1.0))) * 1.0;
		b += sample_compositor_source(clamp(uv + vec2(-1.0*d.x, 2.0*d.y), vec2(0.0), vec2(1.0))) * 4.0;
		b += sample_compositor_source(clamp(uv + vec2( 0.0,       2.0*d.y), vec2(0.0), vec2(1.0))) * 6.0;
		b += sample_compositor_source(clamp(uv + vec2( 1.0*d.x, 2.0*d.y), vec2(0.0), vec2(1.0))) * 4.0;
		b += sample_compositor_source(clamp(uv + vec2( 2.0*d.x, 2.0*d.y), vec2(0.0), vec2(1.0))) * 1.0;
		color = b / 256.0;
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
		bloom += bright_part(sample_compositor_source(clamp(uv + vec2( g.x, 0.0), vec2(0.0), vec2(1.0))));
		bloom += bright_part(sample_compositor_source(clamp(uv + vec2(-g.x, 0.0), vec2(0.0), vec2(1.0))));
		bloom += bright_part(sample_compositor_source(clamp(uv + vec2(0.0,  g.y), vec2(0.0), vec2(1.0))));
		bloom += bright_part(sample_compositor_source(clamp(uv + vec2(0.0, -g.y), vec2(0.0), vec2(1.0))));
		bloom += bright_part(sample_compositor_source(clamp(uv + vec2( g.x,  g.y), vec2(0.0), vec2(1.0))));
		bloom += bright_part(sample_compositor_source(clamp(uv + vec2(-g.x,  g.y), vec2(0.0), vec2(1.0))));
		bloom += bright_part(sample_compositor_source(clamp(uv + vec2( g.x, -g.y), vec2(0.0), vec2(1.0))));
		bloom += bright_part(sample_compositor_source(clamp(uv + vec2(-g.x, -g.y), vec2(0.0), vec2(1.0))));
		color += bloom * (glow_strength / 9.0);
	}

	if (vignette > 0.001) {
		vec2 q = (uv - vec2(0.5)) * vec2(1.0, 0.82);
		float v = smoothstep(0.30, 0.72, length(q));
		color *= 1.0 - v * vignette;
	}

	if (noise_amount > 0.001) {
		vec2 pixel = floor(uv / max(px, vec2(0.000001)));
		color += grain_rgb(pixel) * noise_amount;
	}

	float output_alpha = 1.0;
	if (rounded_mask_enabled > 0.5) {
		vec2 screen_px = UV * rounded_control_size;
		vec2 half_size = rounded_control_size * 0.5;
		vec2 p = abs(screen_px - half_size) - (half_size - vec2(rounded_corner_radius));
		float corner_distance = length(max(p, vec2(0.0))) + min(max(p.x, p.y), 0.0) - rounded_corner_radius;
		float aa = max(fwidth(corner_distance), 0.75);
		output_alpha *= 1.0 - smoothstep(-aa, aa, corner_distance);
	}

	COLOR = vec4(max(color, vec3(0.0)), output_alpha);
}
