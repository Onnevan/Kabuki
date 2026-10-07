shader_type canvas_item;

uniform int effect_kind = 8;
uniform vec2 blur_direction = vec2(1.0, 0.0);

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
	return dot(c, vec3(0.2126, 0.7152, 0.0722));
}

float grain_hash(vec2 p) {
	vec3 p3 = fract(vec3(p.xyx) * 0.1031);
	p3 += dot(p3, p3.yzx + 33.33 + noise_seed);
	return fract((p3.x + p3.y) * p3.z);
}

vec3 grain_rgb(vec2 pixel) {
	float n1 = grain_hash(pixel) - 0.5;
	if (noise_colored < 0.5) return vec3(n1);
	float n2 = grain_hash(pixel + vec2(17.23, 9.71)) - 0.5;
	float n3 = grain_hash(pixel + vec2(41.11, 27.59)) - 0.5;
	return vec3(n1,n2,n3);
}

vec3 sample_rgb(vec2 uv) {
	return texture(TEXTURE, clamp(uv, vec2(0.0), vec2(1.0))).rgb;
}

void fragment() {
	vec2 uv = clamp(UV, vec2(0.0), vec2(1.0));
	vec2 px = TEXTURE_PIXEL_SIZE;
	vec3 color = sample_rgb(uv);

	// 0/1: separable Gaussian blur, horizontal then vertical.
	if (effect_kind == 0 || effect_kind == 1) {
		vec2 dir = normalize(blur_direction);
		vec2 d = px * dir * max(0.25, blur * 0.55);
		vec3 b = sample_rgb(uv) * 0.2270270270;
		b += sample_rgb(uv + d * 1.3846153846) * 0.3162162162;
		b += sample_rgb(uv - d * 1.3846153846) * 0.3162162162;
		b += sample_rgb(uv + d * 3.2307692308) * 0.0702702703;
		b += sample_rgb(uv - d * 3.2307692308) * 0.0702702703;
		color = b;
	}
	// 2: glow/bloom. Explicit taps keep this shader compatible with Mobile.
	else if (effect_kind == 2) {
		vec2 g = px * max(0.5, glow_radius);
		vec3 s0 = sample_rgb(uv);
		vec3 s1 = sample_rgb(uv + vec2( g.x,0.0));
		vec3 s2 = sample_rgb(uv + vec2(-g.x,0.0));
		vec3 s3 = sample_rgb(uv + vec2(0.0, g.y));
		vec3 s4 = sample_rgb(uv + vec2(0.0,-g.y));
		vec3 s5 = sample_rgb(uv + vec2( g.x, g.y));
		vec3 s6 = sample_rgb(uv + vec2(-g.x, g.y));
		vec3 s7 = sample_rgb(uv + vec2( g.x,-g.y));
		vec3 s8 = sample_rgb(uv + vec2(-g.x,-g.y));
		vec3 bloom = vec3(0.0);
		bloom += s0 * smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s0));
		bloom += s1 * smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s1));
		bloom += s2 * smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s2));
		bloom += s3 * smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s3));
		bloom += s4 * smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s4));
		bloom += s5 * smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s5));
		bloom += s6 * smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s6));
		bloom += s7 * smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s7));
		bloom += s8 * smoothstep(glow_threshold,glow_threshold+0.08,luminance_of(s8));
		color += bloom * (glow_strength/9.0);
	}
	// 3: color correction.
	else if (effect_kind == 3) {
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
	// 4: vignette.
	else if (effect_kind == 4) {
		vec2 q = (uv-vec2(0.5))*vec2(1.0,0.82);
		float v = smoothstep(0.30,0.72,length(q));
		color *= 1.0-v*vignette;
	}
	// 5: lens/chromatic aberration.
	else if (effect_kind == 5) {
		vec2 radial = uv-vec2(0.5);
		vec2 shift = radial*chromatic_aberration*0.02;
		color.r = sample_rgb(uv+shift).r;
		color.b = sample_rgb(uv-shift).b;
	}
	// 6: monochrome.
	else if (effect_kind == 6) {
		float gray = luminance_of(color);
		color = mix(color,vec3(gray),monochrome);
	}
	// 7: grain/noise.
	else if (effect_kind == 7) {
		vec2 pixel = floor(uv/max(px,vec2(0.000001)));
		color += grain_rgb(pixel)*noise_amount;
	}

	COLOR = vec4(max(color,vec3(0.0)), texture(TEXTURE,uv).a);
}
