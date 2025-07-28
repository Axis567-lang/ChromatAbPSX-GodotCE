shader_type canvas_item;

uniform float chromab_polarity : hint_range( -3.0, 3.0, 0.1 ) = -0.6;

uniform float noise_frequency : hint_range( 0.0, 6.0, 0.1 ) = 1.0;
uniform float noise_tiling : hint_range( 0.1, 1.0, 0.05 ) = 0.25;
uniform float noise_intensity : hint_range( 0.0, 1.0, 0.005 ) = 0.025;

uniform float vignette_intensity = 0.1;
uniform vec4 vignette_rgba : source_color = vec4( 0.0, 0.0, 0.0, 1.0 );

uniform bool psx_toggle = true;
uniform float dither_scale: hint_range( 0.1, 2.0, 0.05 ) = 1.0;

uniform bool gradient_flip = false;
uniform float gradient_intensity: hint_range( 0.0, 1.0, 0.05 ) = 0.15;

uniform sampler2D gradient : hint_default_black, filter_nearest;
uniform sampler2D dither_tex: hint_default_white, repeat_enable, filter_nearest;

// *** functions ***

vec2 hash_2d( vec2 uv ) {
	float time = fract( TIME * noise_frequency );

	vec2 uvh = vec2(
		dot( uv, vec2( 127.1, 311.7 ) ),
		dot( uv, vec2( 269.5, 183.3 ) )
		);

	return fract( sin( uvh ) * 43758.5453123 + time ) * 2.0 - 1.0;
}

float noise_simplex( in vec2 p ) {
	const float K1 = 0.366025404; // (sqrt(3)-1)/2;
	const float K2 = 0.211324865; // (3-sqrt(3))/6;

	vec2  i = floor( p + (p.x+p.y)*K1 );
	vec2  a = p - i + (i.x+i.y)*K2;
	float m = step(a.y,a.x);
	vec2  o = vec2(m,1.0-m);
	vec2  b = a - o + K2;
	vec2  c = a - 1.0 + 2.0*K2;
	vec3  h = max( 0.5-vec3(dot(a,a), dot(b,b), dot(c,c) ), 0.0 );
	vec3  n = h*h*h*h*vec3( dot(a,hash_2d(i+0.0)), dot(b,hash_2d(i+o)), dot(c,hash_2d(i+1.0)));
	return dot( n, vec3(70.0) );
}

//float noise_perlin( vec2 uv ) {
//    vec2 uv_index = floor( uv );
//    vec2 uv_fract = fract( uv );
//
//    vec2 blur = smoothstep( 0.0, 1.0, uv_fract );
//
//    return mix( mix( dot( hash_2d(uv_index + vec2(0.0,0.0) ), uv_fract - vec2(0.0,0.0) ),
//                     dot( hash_2d(uv_index + vec2(1.0,0.0) ), uv_fract - vec2(1.0,0.0) ), blur.x),
//                mix( dot( hash_2d(uv_index + vec2(0.0,1.0) ), uv_fract - vec2(0.0,1.0) ),
//                     dot( hash_2d(uv_index + vec2(1.0,1.0) ), uv_fract - vec2(1.0,1.0) ), blur.x), blur.y) + 0.5;
//}

vec3 hard_light( vec3 base, vec3 blend ) {
	vec3 limit = step( 0.5, blend );
	return mix( 2.0 * base * blend, 1.0 - 2.0 * ( 1.0 - base ) * ( 1.0 - blend ), limit );
}

float radial_mask( vec2 uv ) {
	uv *= 1.0 - uv;
	float mask = uv.x * uv.y * 16.0;
	return mask;
}

vec3 chrom_ab( sampler2D screen, vec2 uv ) {
	float amount = 0.0016;

	vec3 col;
	col.r = texture( screen, vec2( uv.x - amount, uv.y ) ).r;
	col.b = texture( screen, vec2( uv.x + amount, uv.y ) ).b;
	col.g = texture( screen, vec2( uv.x, uv.y - amount ) ).g;

	return col;
}

vec3 psx_tex(vec3 col, sampler2D tex, vec2 uv) {
	vec2 dither_size = vec2(textureSize(dither_tex, 0)); // for GLES2: substitute for the dimensions of the dithering matrix
	vec2 buf_size = vec2(textureSize(tex, 0)) * dither_scale;
	vec3 dither = texture(dither_tex, uv * (buf_size / dither_size)).rgb - 0.5;

	float gradient_size = float( textureSize(gradient, 0).x );
	return round(col * gradient_size + dither) / gradient_size;
}

vec3 palette(vec3 col) {
	float lum = dot( col, vec3( 0.2126, 0.7152, 0.0722 ) );
	return texture( gradient, vec2(abs(float(gradient_flip) - lum), 0) ).rgb;
}

// *** shader ***

void fragment() {
	vec2 uv = UV;
	vec2 sps = SCREEN_PIXEL_SIZE;
	vec2 res = (1.0 / sps);
	vec2 screen = res * uv;

	vec3 col = texture(TEXTURE, uv).rgb;

	float c = 1.0 + chromab_polarity - pow(radial_mask(uv), vignette_intensity);
	float v = 1.0 - pow(radial_mask(uv), vignette_intensity);
	float n = noise_simplex(screen * noise_tiling);
	vec3 tex_noise = vec3(n);

	vec3 col_chr = mix(col, chrom_ab(TEXTURE, uv), c);
	vec3 col_psx = mix(col_chr, psx_tex(col_chr, TEXTURE, uv), psx_toggle ? 1.0 : 0.0);
	vec3 col_pal = mix(col_psx, palette(col_psx), gradient_intensity);
	vec3 col_nos = mix(col_pal, hard_light(col_pal, tex_noise), noise_intensity);
	vec3 col_vig = mix(col_nos, vignette_rgba.rgb * v, vignette_rgba.a * v);

	COLOR.rgb = col_vig;
	
	//vec3 color = vec3(0.5);
	//vec3 tex_color = texture(TEXTURE, UV).rgb;
//
	//COLOR.rgb = pow(tex_color, vec3(2.2));
}