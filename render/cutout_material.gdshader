shader_type spatial;
render_mode unshaded, cull_disabled, depth_draw_opaque, blend_mix;
uniform sampler2D source_texture : source_color, filter_linear_mipmap;
uniform float opacity : hint_range(0.0,1.0) = 1.0;
uniform float exposure : hint_range(-3.0,3.0) = 0.0;
uniform float saturation : hint_range(0.0,2.0) = 1.0;
uniform float blur : hint_range(0.0,8.0) = 0.0;
uniform float glow : hint_range(0.0,3.0) = 0.0;
uniform float selected : hint_range(0.0,1.0) = 0.0;
uniform float render_quality : hint_range(0.0,1.0) = 0.0;
void fragment(){
	vec2 texel = 1.0 / vec2(textureSize(source_texture,0));
	vec2 px = texel * blur * render_quality;
	vec4 c = texture(source_texture,UV)*0.4;
	c += texture(source_texture,UV+vec2(px.x,0.0))*0.15;
	c += texture(source_texture,UV-vec2(px.x,0.0))*0.15;
	c += texture(source_texture,UV+vec2(0.0,px.y))*0.15;
	c += texture(source_texture,UV-vec2(0.0,px.y))*0.15;
	c.rgb *= exp2(exposure * render_quality);
	float l=dot(c.rgb,vec3(0.2126,0.7152,0.0722));
	c.rgb=mix(vec3(l),c.rgb,mix(1.0,saturation,render_quality));
	c.rgb=mix(c.rgb,c.rgb+vec3(0.08,0.16,0.22),selected*0.35);
	ALBEDO=c.rgb; ALPHA=c.a*opacity; EMISSION=c.rgb*glow*render_quality;
}
