shader_type canvas_item;
render_mode unshaded, blend_disabled;

uniform sampler2D source_texture : filter_linear;
uniform vec2 source_pixel_size = vec2(0.001, 0.001);

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

vec3 sample_base(vec2 uv) {
	if (blur <= 0.001) {
		return texture(source_texture, uv).rgb;
	}
	vec2 px = source_pixel_size * blur;
	vec3 c = texture(source_texture, uv).rgb * 0.227027;
	c += texture(screen_texture, uv + vec2(px.x, 0.0)).rgb * 0.1945946;
	c += texture(screen_texture, uv - vec2(px.x, 0.0)).rgb * 0.1945946;
	c += texture(screen_texture, uv + vec2(0.0, px.y)).rgb * 0.1945946;
	c += texture(screen_texture, uv - vec2(0.0, px.y)).rgb * 0.1945946;
	return c;
}

vec3 extract_bright(vec2 uv) {
	vec3 c = texture(source_texture, uv).rgb;
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float mask = smoothstep(glow_threshold, glow_threshold + 0.08, luma);
	return c * mask;
}

void fragment() {
	vec2 uv = UV;
	vec3 color;

	if (chromatic_aberration > 0.0001) {
		vec2 dir = uv - vec2(0.5);
		vec2 shift = dir * chromatic_aberration * 0.018;
		float r = sample_base(uv + shift).r;
		float g = sample_base(uv).g;
		float b = sample_base(uv - shift).b;
		color = vec3(r,g,b);
	} else {
		color = sample_base(uv);
	}

	color *= exp2(exposure);

	float luma = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(vec3(luma), color, saturation);
	color = (color - 0.5) * contrast + 0.5;

	color.r += temperature * 0.12;
	color.b -= temperature * 0.12;
	color.g += color_tint * 0.08;
	color.r -= color_tint * 0.035;
	color.b -= color_tint * 0.035;

	float bw = dot(color, vec3(0.2126, 0.7152, 0.0722));
	color = mix(color, vec3(bw), monochrome);

	if (glow_strength > 0.001) {
		vec2 px = source_pixel_size * glow_radius;
		vec3 bloom = vec3(0.0);
		float weight_sum = 0.0;
		for (int x = -3; x <= 3; x++) {
			for (int y = -3; y <= 3; y++) {
				vec2 q = vec2(float(x), float(y));
				float d2 = dot(q,q);
				float w = exp(-d2 * 0.22);
				bloom += extract_bright(uv + q * px * 0.6) * w;
				weight_sum += w;
			}
		}
		color += bloom / max(weight_sum, 0.0001) * glow_strength;
	}

	if (vignette > 0.001) {
		vec2 p = (uv - vec2(0.5)) * vec2(1.0, 0.82);
		float d = length(p);
		float v = smoothstep(0.32, 0.78, d);
		color *= 1.0 - v * vignette;
	}

	COLOR = vec4(color, 1.0);
}
