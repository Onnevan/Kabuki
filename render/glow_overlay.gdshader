shader_type canvas_item;
render_mode unshaded, blend_add;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear_mipmap;
uniform float strength : hint_range(0.0,3.0) = 0.0;
uniform float threshold : hint_range(0.0,2.0) = 0.7;
uniform float radius : hint_range(0.5,12.0) = 3.0;

vec3 bright(vec2 uv){
	vec3 c=textureLod(screen_texture,uv,0.0).rgb;
	float l=max(c.r,max(c.g,c.b));
	return c*smoothstep(threshold,threshold+0.2,l);
}
void fragment(){
	vec2 uv=SCREEN_UV;
	vec2 p=SCREEN_PIXEL_SIZE*radius;
	vec3 b=bright(uv)*0.16;
	b+=bright(uv+vec2(p.x,0.0))*0.12;
	b+=bright(uv-vec2(p.x,0.0))*0.12;
	b+=bright(uv+vec2(0.0,p.y))*0.12;
	b+=bright(uv-vec2(0.0,p.y))*0.12;
	b+=bright(uv+vec2(p.x,p.y))*0.09;
	b+=bright(uv+vec2(-p.x,p.y))*0.09;
	b+=bright(uv+vec2(p.x,-p.y))*0.09;
	b+=bright(uv-vec2(p.x,p.y))*0.09;
	COLOR=vec4(b*strength,1.0);
}