shader_type canvas_item;

uniform sampler2D screen_texture : hint_screen_texture, repeat_disable, filter_linear;
uniform int effect_kind = 0;
uniform vec2 blur_direction = vec2(1.0,0.0);

uniform float blur = 0.0;
uniform float glow_strength = 0.0;
uniform float glow_threshold = 0.7;
uniform float glow_radius = 3.0;
uniform float exposure = 0.0;
uniform float saturation = 1.0;
uniform float contrast = 1.0;
uniform float temperature = 0.0;
uniform float color_tint = 0.0;
uniform float vignette = 0.0;
uniform float chromatic_aberration = 0.0;
uniform float monochrome = 0.0;
uniform float noise_amount = 0.0;
uniform float noise_seed = 0.0;
uniform float noise_colored = 0.0;

float luminance_of(vec3 c) {
	return dot(c,vec3(0.2126,0.7152,0.0722));
}

float grain_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx)*0.1031);
	p3 += dot(p3,p3.yzx+33.33+noise_seed);
	return fract((p3.x+p3.y)*p3.z);
}

vec3 grain_rgb(vec2 pixel) {
	float n1 = grain_hash(pixel)-0.5;
	if (noise_colored < 0.5) return vec3(n1);
	float n2 = grain_hash(pixel+vec2(17.23,9.71))-0.5;
	float n3 = grain_hash(pixel+vec2(41.11,27.59))-0.5;
	return vec3(n1,n2,n3);
}

vec3 read_screen(vec2 uv) {
	return texture(screen_texture,clamp(uv,vec2(0.0),vec2(1.0))).rgb;
}

void fragment() {
	vec2 uv = SCREEN_UV;
	vec3 color = read_screen(uv);

	// 0 = Lens Aberration
	if (effect_kind == 0) {
		vec2 radial = uv-vec2(0.5);
		vec2 shift = radial*chromatic_aberration*0.02;
		color.r = read_screen(uv+shift).r;
		color.b = read_screen(uv-shift).b;
	}
	// 1/2 = Gaussian blur horizontal / vertical.
	else if (effect_kind == 1 || effect_kind == 2) {
		vec2 d = SCREEN_PIXEL_SIZE*blur_direction*max(0.0,blur);
		if (blur > 0.001) {
			color = read_screen(uv)*0.2270270270;
			color += read_screen(uv+d*1.3846153846)*0.3162162162;
			color += read_screen(uv-d*1.3846153846)*0.3162162162;
			color += read_screen(uv+d*3.2307692308)*0.0702702703;
			color += read_screen(uv-d*3.2307692308)*0.0702702703;
		}
	}
	// 3 = Glow
	else if (effect_kind == 3) {
		vec2 g = SCREEN_PIXEL_SIZE*max(0.5,glow_radius);
		vec3 bloom = vec3(0.0);
		vec3 s0 = read_screen(uv);
		vec3 s1 = read_screen(uv+vec2( g.x,0.0));
		vec3 s2 = read_screen(uv+vec2(-g.x,0.0));
		vec3 s3 = read_screen(uv+vec2(0.0, g.y));
		vec3 s4 = read_screen(uv+vec2(0.0,-g.y));
		vec3 s5 = read_screen(uv+vec2( g.x, g.y));
		vec3 s6 = read_screen(uv+vec2(-g.x, g.y));
		vec3 s7 = read_screen(uv+vec2( g.x,-g.y));
		vec3 s8 = read_screen(uv+vec2(-g.x,-g.y));
		bloom += s0*smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s0));
		bloom += s1*smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s1));
		bloom += s2*smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s2));
		bloom += s3*smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s3));
		bloom += s4*smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s4));
		bloom += s5*smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s5));
		bloom += s6*smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s6));
		bloom += s7*smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s7));
		bloom += s8*smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s8));
		color += bloom*(glow_strength/9.0);
	}
	// 4 = Color Correction
	else if (effect_kind == 4) {
		color *= exp2(exposure);
		float y = luminance_of(color);
		color = mix(vec3(y),color,saturation);
		color = (color-vec3(0.5))*contrast+vec3(0.5);
		color.r += temperature*0.15;
		color.b -= temperature*0.15;
		color.g += color_tint*0.10;
		color.r -= color_tint*0.04;
		color.b -= color_tint*0.04;
	}
	// 5 = Vignette
	else if (effect_kind == 5) {
		vec2 q = (uv-vec2(0.5))*vec2(1.0,0.82);
		float v = smoothstep(0.30,0.72,length(q));
		color *= 1.0-v*vignette;
	}
	// 6 = Black & White
	else if (effect_kind == 6) {
		float gray = luminance_of(color);
		color = mix(color,vec3(gray),monochrome);
	}
	// 7 = Noise
	else if (effect_kind == 7) {
		vec2 pixel = floor(uv/max(SCREEN_PIXEL_SIZE,vec2(0.000001)));
		color += grain_rgb(pixel)*noise_amount;
	}

	COLOR = vec4(max(color,vec3(0.0)),1.0);
}
