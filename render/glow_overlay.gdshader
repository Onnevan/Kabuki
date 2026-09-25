shader_type canvas_item;
render_mode unshaded, blend_add;

uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float strength : hint_range(0.0, 3.0) = 0.0;
uniform float threshold : hint_range(0.0, 2.0) = 0.7;
uniform float radius : hint_range(0.5, 24.0) = 3.0;

vec3 extract_bright(vec2 uv) {
	vec3 c = texture(screen_texture, uv).rgb;
	float luma = dot(c, vec3(0.2126, 0.7152, 0.0722));
	float knee = 0.08;
	float mask = smoothstep(threshold, threshold + knee, luma);
	return c * mask;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec2 px = SCREEN_PIXEL_SIZE * radius;
	vec3 bloom = vec3(0.0);
	float weight_sum = 0.0;

	for (int x = -4; x <= 4; x++) {
		for (int y = -4; y <= 4; y++) {
			vec2 q = vec2(float(x), float(y));
			float d2 = dot(q, q);
			float w = exp(-d2 * 0.18);
			bloom += extract_bright(uv + q * px * 0.55) * w;
			weight_sum += w;
		}
	}
	bloom /= max(weight_sum, 0.0001);
	COLOR = vec4(bloom * strength, 0.0);
}
