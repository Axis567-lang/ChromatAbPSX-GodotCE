#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;

layout(push_constant, std430) uniform Params {
    vec2 screen_size;

	float noise_frequency;
	float noise_tiling;
	float noise_intensity;

	float time;
} pms;

//	FUNCTIONS
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

vec3 hard_light( vec3 base, vec3 blend ) {
	vec3 limit = step( 0.5, blend );
	return mix( 2.0 * base * blend, 1.0 - 2.0 * ( 1.0 - base ) * ( 1.0 - blend ), limit );
}

// MAIN
void main()
{
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);			// screen
    vec2 res = pms.screen_size;								// res
    // calculate uv
    vec2 uv = pixel / res;									// uv								

    if(pixel.x >= res.x || pixel.y >= res.y) return;

    vec4 color = imageLoad(screen_tex, pixel);				// col

	//	Parameters
	float n = noise_simplex(vec2(pixel) * pms.noise_tiling);

	vec3 tex_noise = vec3(n);

	vec3 col_nos = mix(color.rgb, hard_light(color.rgb, tex_noise), pms.noise_intensity);

	imageStore(screen_tex, pixel, vec4(col_nos, 1.0));
}

