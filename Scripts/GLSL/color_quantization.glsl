#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// PARAMETERS
layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;

layout(push_constant, std430) uniform Params {
    vec2 screen_size;
    vec2 lut_tex_size;
} pms;

layout(binding = 1, set = 0) uniform sampler2D screen_sample;

layout(binding = 0, set = 1) uniform sampler2D lut_sample;

// VARIABLE
//  obtenemos su N -> el tamaño en 3D -> N x N x N
int lut_N_i = int( pow(pms.lut_tex_size.x * pms.lut_tex_size.y, 1.0/3.0) );
float lut_N = float(lut_N_i);

//  #---------- QUANTIZATION BY LUT INDEXING ----------#

// FUNCTIONS
/*vec2 computeUV(vec3 index)
{
    float slice = index.z; // capa en Z
    float x = index.x + slice * lut_N;
    float y = index.y;

    return (vec2(x, y) + 0.5) / pms.lut_tex_size;
}*/
// TEST 5 
vec2 computeUV(vec3 index)
{
    // index = floor(color * (lut_N - 1))
    float slice = index.z;

    // # de cuadritos por fila
    float tilesPerRow = pms.lut_tex_size.x / lut_N; // 512x512 -> 64x64x64 = 512 / 64

    // en que columna de los cuadritos estamos 
    //   -> cada que llegas a tilesPerRow, se reinicia el conteo, por eso se usa el residuo
    float tileX = mod(slice, tilesPerRow);
    // en que fila de los cuadritos estamos
    //   -> si repartes todos los cuadritos que llevas entre 
    //      cuantos hay en cada fila, pues te da la fila en la que llevas
    float tileY = floor(slice / tilesPerRow);

    // "+ tileX * lut_N" : mueve ese punto al inicio de la columna correcta.
    float x = index.x + tileX * lut_N;
    // "+ tileY * lut_N" : mueve ese punto al inicio de la fila correcta.
    float y = index.y + tileY * lut_N;
    x = clamp(x, 0.0, pms.lut_tex_size.x - 1.0);
    y = clamp(y, 0.0, pms.lut_tex_size.y - 1.0);

    return (vec2(x, y) + 0.5) / pms.lut_tex_size;
}

// MAIN
void main()
{
	// Convierte la posicion global del hilo de computo a coordenadas de pixel (x, y)
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);

	// Obtiene el tamanio total de la pantalla desde los push constants
	vec2 size = pms.screen_size;

	// Si el pixel esta fuera de los limites, termina la ejecucion del hilo
	if (pixel.x >= size.x || pixel.y >= size.y) return;

	// Normaliza las coordenadas del pixel para obtener UV (entre 0 y 1)
	vec2 uv = vec2(pixel) / size;
	//	-----------------

    vec3 inCol = texture(screen_sample, uv).rgb;
    vec3 index = floor(inCol * (lut_N - 1.0));

    vec2 lut_uv = computeUV(index);
    vec3 lut_color = texture(lut_sample, lut_uv).rgb;

    imageStore(screen_tex, pixel, vec4(lut_color, 1.0));
	// imageStore(screen_tex, pixel, vec4(inCol, 1.0));
}
// # -------------------------------------------------------------------- #

// # --------- QUANTIZATION BY LUMINANCE ------ #
/*
// FUNCTIONS
vec2 computeUV(vec3 index) 
{
    float slice = index.z; // capa en Z
    float x = index.x + slice * lut_N;
    float y = index.y;

    return (vec2(x, y) + 0.5) / lut_tex_size;

}

// MAIN
void main()
{
	// Convierte la posicion global del hilo de computo a coordenadas de pixel (x, y)
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);

	// Obtiene el tamaño total de la pantalla desde los push constants
	vec2 size = pms.screen_size;

	// Si el pixel está fuera de los limites, termina la ejecución del hilo
	if (pixel.x >= size.x || pixel.y >= size.y) return;

	// Normaliza las coordenadas del pixel para obtener UV (entre 0 y 1)
	vec2 uv = vec2(pixel) / size;
	//	-----------------

    vec3 inCol = texture(screen_sample, uv).rgb;
    vec3 index = floor(inCol * (lut_N - 1.0));

    // float lum = dot( inCol, vec3( 0.2126, 0.7152, 0.0722 ) );
	// vec3 color_lum = texture( lut_sample, vec2(lum, 0) ).rgb;

    float lum = dot(inCol, vec3(0.2126, 0.7152, 0.0722));
    vec2 uv_lut = vec2(lum, 0.5); // usar el centro vertical de la LUT
    vec3 color_lum = texture(lut_sample, uv_lut).rgb;


    // imageStore(screen_tex, pixel, vec4(lut_color, 1.0));
    imageStore(screen_tex, pixel, vec4(color_lum, 1.0));
}
*/
// # -------------------------------------------------------------------- #

