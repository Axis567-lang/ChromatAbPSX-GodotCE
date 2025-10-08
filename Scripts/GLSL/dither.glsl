#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// PARAMETERS
layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;

layout(push_constant, std430) uniform Params {
    vec2 screen_size;

    vec2 dither_tex_size_1;
    vec2 dither_tex_size_2;
    vec2 dither_tex_size_3;

    float levels;

    float inv_proj_2w;
    float inv_proj_3w;
} pms;

layout(binding = 1, set = 0) uniform sampler2D screen_sample;

layout(binding = 0, set = 1) uniform sampler2D dither_sample_1;
layout(binding = 1, set = 1) uniform sampler2D dither_sample_2;
layout(binding = 2, set = 1) uniform sampler2D dither_sample_3;

layout(binding = 0, set = 2) uniform sampler2D depth_tex;

float dither_N = pms.dither_tex_size_1.x;

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

    /*
    vec3 inCol = texture(screen_sample, uv).rgb;
    
    //  ------------ ORDERED DITHERING ------------ // 
    // float threshold = bayerMatrix[mod(x, N)][mod(y, N)];
    // color = step(threshold, value);

    // vec2 dither_uv = vec2(mod(pixel.x, dither_N), mod(pixel.y, dither_N));
    vec2 dither_uv = vec2(
            mod(float(pixel.x), float(dither_N)) / float(dither_N),
            mod(float(pixel.y), float(dither_N)) / float(dither_N)
        );

    vec3 threshold = texture(dither_sample_1, dither_uv).rgb;
    
    vec3 dither_color = step(threshold, inCol);

    imageStore(screen_tex, pixel, vec4(dither_color, 1.0));


	// imageStore(screen_tex, pixel, vec4(inCol, 1.0));*/

    // Obten el color de entrada
    vec3 inCol = texture(screen_sample, uv).rgb;

    // Depth
    float depth = texture(depth_tex, uv).r;
    float linear_depth = 1. / (depth * pms.inv_proj_2w + pms.inv_proj_3w);
    linear_depth = clamp(linear_depth / 50., 0., 1.);
    // --------- END

    vec2 dither_uv = vec2(
            mod(float(pixel.x), float(dither_N)) / float(dither_N),
            mod(float(pixel.y), float(dither_N)) / float(dither_N)
        );

    // Obten el umbral de la matriz de Bayer (dither_sample_1) en un solo canal
    float threshold;
    if (linear_depth < 0.1)
        threshold = texture(dither_sample_1, dither_uv).r;
    else if (linear_depth < 0.4)
        threshold = texture(dither_sample_2, dither_uv).r;
    else
        threshold = texture(dither_sample_3, dither_uv).r;

    // Convierte a luminancia (puedes usar otra formula si quieres)
    /*float lum = dot(inCol, vec3(0.299, 0.587, 0.114));
    
    // Escala la luminancia a niveles discretos con dithering
    float scaled = lum * float(pms.levels);

    // Aplica el dithering con el umbral
    float dithered = floor(scaled + threshold);

    // Normaliza de vuelta a [0,1]
    float outLum = dithered / float(pms.levels);

    float safeLum = max(lum, 1e-6);
    vec3 outCol = clamp(inCol * (outLum / safeLum), 0.0, 1.0);

    // Reconstruye el color (aquí simplemente escala el color original manteniendo la proporción)
    //vec3 outCol = inCol * (outLum / lum);

    
    imageStore(screen_tex, pixel, vec4(outCol, 1.0));*/

    //  ESCALADO A CADA CANAL
    vec3 scaled = inCol * float(pms.levels);

    vec3 dithered = floor(scaled + threshold);

    vec3 outCol = dithered / float(pms.levels);


    imageStore(screen_tex, pixel, vec4(outCol, 1.0));

}


