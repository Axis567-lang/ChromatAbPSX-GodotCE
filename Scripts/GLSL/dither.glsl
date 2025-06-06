#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;
layout(binding = 0, set = 1) uniform sampler2D depth_tex;

layout(set = 2, binding = 0, std140) uniform VignetteData {
	vec4 vignette_rgba;
} vgt;

layout(binding = 0, set = 3) uniform sampler2D gradient;
layout(binding = 0, set = 4) uniform sampler2D dither;

layout(binding = 0, set = 5) uniform sampler2D screen_sample;

layout(push_constant, std430) uniform Params {
    vec2 screen_size;
    // calculate depth no lineal coords to view coords
    float inv_proj_2w;
    float inv_proj_3w;

	float chromab_polarity;
	float noise_frequency;
	float noise_tiling;
	float noise_intensity;

	float vignette_intensity;
	float psx_toggle; // usar como bool en logica
	float dither_scale;
	float gradient_flip; // usar como bool
	float gradient_intensity;

	float time;
} pms;

const vec2 offset = vec2(0.0001);
const float sample_size = 5.0;

//	FUNCTIONS
float radial_mask( vec2 uv ) {
	// Esto produce una curva que vale 0 en 0 y 1, y tiene un pico en 0.5.
	uv *= 1.0 - uv;
	//	Se escala por 16.0 para amplificar el rango (0 a 1).
	float mask = uv.x * uv.y * 16.0;
	return mask;
}

vec2 hash_2d( vec2 uv ) {
	float time = fract( pms.time * pms.noise_frequency );

	vec2 uvh = vec2(
		dot( uv, vec2( 127.1, 311.7 ) ),
		dot( uv, vec2( 269.5, 183.3 ) )
		);

	return fract( sin( uvh ) * 43758.5453123 + time ) * 2.0 - 1.0;
}

float noise_simplex( in vec2 p ) {
	//	K1 aplana el espacio para ubicar en qué triángulo (simplex) cae el punto.
	const float K1 = 0.366025404; // (sqrt(3)-1)/2;
	//	K2 corrige el desplazamiento al pasar de espacio simplex a espacio cartesiano.
	const float K2 = 0.211324865; // (3-sqrt(3))/6;

	//	desplaza el punto `p` a un sistema de coordenadas basado en triángulos equiláteros (simplex).  
	vec2  i = floor( p + (p.x + p.y) * K1 );
	//	posición del punto **dentro del triángulo simplex** local, usando el sistema corregido con `K2`.
	vec2  a = p - i + (i.x+i.y)*K2;

	//	División de 2 subtriángulos
	// 		Si a.x > a.y -> m = 1 -> o = vec2(1, 0)
	//		Si a.x < a.y -> m = 0 -> o = vec2(0, 1)
	float m = step(a.y,a.x);
	//	Esto define el segundo vértice del triángulo.
	vec2  o = vec2(m, 1.0-m);

	//	la distancia del punto a la **segunda esquina del triángulo**.
	vec2  b = a - o + K2;
	//	la distancia a la **tercera esquina**.
	vec2  c = a - 1.0 + 2.0 * K2;

	// qué tan cerca está el punto a cada vértice del triángulo. Max 0.0 anula los negativos.
	vec3  h = max( 0.5 - vec3( dot(a,a), dot(b,b), dot(c,c) ), 0.0 );
	//	Se aplican **gradientes hash pseudo-aleatorios** en las tres esquinas del triángulo:
	//		`hash_2d(...)` genera un **vector direccional aleatorio**.
	//		`dot(a, grad)` mide la influencia de ese vértice en la posición del punto.
	//		`h*h*h*h` suaviza la interpolación (el valor se reduce más rápidamente, decayendo más fuerte mientras te alejas del vértice).
	vec3  n = h*h*h*h* vec3( 
		dot( a, hash_2d(i+0.0) ), 
		dot( b, hash_2d(i+o) ), 
		dot( c, hash_2d(i+1.0) ));
	
	return dot( n, vec3(70.0) );
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
	vec2 dither_size = vec2(textureSize(dither, 0)); // for GLES2: substitute for the dimensions of the dithering matrix
	vec2 buf_size = vec2(textureSize(tex, 0)) * pms.dither_scale;
	vec3 dither_vec = texture(dither, uv * (buf_size / dither_size)).rgb - 0.5;

	float gradient_size = float( textureSize(gradient, 0).x );
	return round(col * gradient_size + dither_vec) / gradient_size;
}

vec3 palette(vec3 col) {
	float lum = dot( col, vec3( 0.2126, 0.7152, 0.0722 ) );
	return texture( gradient, vec2(abs(float(pms.gradient_flip) - lum), 0) ).rgb;
}

vec3 hard_light( vec3 base, vec3 blend ) {
	vec3 limit = step( 0.5, blend );
	return mix( 2.0 * base * blend, 1.0 - 2.0 * ( 1.0 - base ) * ( 1.0 - blend ), limit );
}

void main()
{
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);				// uv
    vec2 size_res = pms.screen_size;							// res
    // calculate uv
    vec2 uv_screen = pixel / size_res;						// screen

    if(pixel.x >= size_res.x || pixel.y >= size_res.y) return;

    vec4 color = imageLoad(screen_tex, pixel);				// col

	//	Parameters
	float c = 1.0 + pms.chromab_polarity - pow(radial_mask(uv_screen), pms.vignette_intensity);
	float v = 1.0 - pow(radial_mask(uv_screen), pms.vignette_intensity);
	float n = noise_simplex(uv_screen * pms.noise_tiling);

	vec3 tex_noise = vec3(n);

	vec3 col_chr = mix(color.rgb, chrom_ab(screen_sample, uv_screen), c);
	vec3 col_psx = mix(col_chr, psx_tex(col_chr, screen_sample, uv_screen), pms.psx_toggle);
	vec3 col_pal = mix(col_psx, palette(col_psx), pms.gradient_intensity);
	vec3 col_nos = mix(col_pal, hard_light(col_pal, tex_noise), pms.noise_intensity);
	vec3 col_vig = mix(col_nos, vgt.vignette_rgba.rgb * v, vgt.vignette_rgba.a * v);

	// vec3 gradient_color = texture(gradient, uv).rgb;
	// vec3 dither_color = texture(dither, uv).rgb;
	// --------------------------------------------------------------------------------------------------------------------------------------------
    /*
	void fragment() {
	vec2 uv = UV;
	vec2 sps = SCREEN_PIXEL_SIZE;
	vec2 res = (1.0 / sps);
	vec2 screen = res * uv;

	vec3 col = texture(TEXTURE, uv).rgb;
	***
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
	}*/

	// imageStore(screen_tex, pixel, color);
	imageStore(screen_tex, pixel, vec4(col_vig, 1.0));


}
