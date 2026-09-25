shader_type canvas_item;
uniform sampler2D screen_texture : hint_screen_texture, filter_linear;
uniform float strength : hint_range(0.0,3.0) = 0.0;
uniform float threshold : hint_range(0.0,2.0) = 0.7;
uniform float radius : hint_range(0.5,8.0) = 3.0;
void fragment(){
	vec2 uv=SCREEN_UV;
	vec2 px=SCREEN_PIXEL_SIZE*radius;
	vec3 bloom=vec3(0.0);
	float weight=0.0;
	for(int x=-3;x<=3;x++){
		for(int y=-3;y<=3;y++){
			vec2 o=vec2(float(x),float(y))*px;
			vec3 s=texture(screen_texture,uv+o).rgb;
			float l=max(s.r,max(s.g,s.b));
			float m=smoothstep(threshold,threshold+0.25,l);
			float w=1.0/(1.0+float(x*x+y*y));
			bloom+=s*m*w; weight+=w;
		}
	}
	bloom/=max(weight,0.001);
	vec4 base=texture(screen_texture,uv);
	COLOR=vec4(base.rgb+bloom*strength,base.a);
}