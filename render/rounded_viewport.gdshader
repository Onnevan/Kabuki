shader_type canvas_item;

uniform vec2 control_size = vec2(800.0, 600.0);
uniform float corner_radius = 16.0;

void fragment() {
	vec4 color = texture(TEXTURE, UV);
	vec2 px = UV * control_size;
	vec2 half_size = control_size * 0.5;
	vec2 p = abs(px - half_size) - (half_size - vec2(corner_radius));
	float distance_to_corner = length(max(p, vec2(0.0))) + min(max(p.x, p.y), 0.0) - corner_radius;
	float aa = max(fwidth(distance_to_corner), 0.75);
	float mask = 1.0 - smoothstep(-aa, aa, distance_to_corner);
	COLOR = vec4(color.rgb, color.a * mask);
}
