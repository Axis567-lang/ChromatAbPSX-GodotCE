#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// PARAMETERS
layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;

layout(push_constant, std430) uniform Params {
    vec2 screen_size;
    vec2 dither_tex_size;
    float cell_size_px;
} pms;

layout(binding = 1, set = 0) uniform sampler2D screen_sample;

layout(binding = 0, set = 1) uniform sampler2D dither_sample;

float dither_N = pms.dither_tex_size.x;

// Rotacion en radianes para cada canal (simula CMY halftone angles)
const float angleR = 0.0;            // 0 grados
const float angleG = radians(15.0);  // 15 grados
const float angleB = radians(75.0);  // 75 grados

mat2 rot(float a) {
    return mat2(cos(a), -sin(a),
                sin(a),  cos(a));
}

float halftone_value(float angle, vec2 uni_cell_size, vec2 uv)
{
    vec2 uv_rot = rot(angle) * uv;
    vec2 d = mod(uv_rot, uni_cell_size) - 0.5 * uni_cell_size;
    float dist = length(d);

    vec3 center_color = texture(screen_sample, uv - d).rgb;
    float grey = 0.299 * center_color.r + 0.587 * center_color.g + 0.114 * center_color.b;
    // Tomamos el minimo entre ancho y alto, 
    //  para que el radio del punto no sobresalga de la celda si la resolucion no es cuadrada.
    float rad = grey * min(uni_cell_size.x, uni_cell_size.y) * 0.5;
    return step(dist, rad);
}

// MAIN
void main()
{
	// Convierte la posicion global del hilo de computo a coordenadas de pixel (x, y)
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);

	// Obtiene el tamanio total de la pantalla desde los push constants
	vec2 screen_size = pms.screen_size;                        // R

	// Si el pixel esta fuera de los limites, termina la ejecucion del hilo
	if (pixel.x >= screen_size.x || pixel.y >= screen_size.y) return;

	// Normaliza las coordenadas del pixel para obtener UV (entre 0 y 1)
	vec2 uv = vec2(pixel) / screen_size;                       // U
	//	-----------------

    vec3 inCol = texture(screen_sample, uv).rgb;               // col
    
    //  ------------ ORDERED DITHERING ------------  // 
    // float threshold = bayerMatrix[mod(x, N)][mod(y, N)];
    // color = step(threshold, value);

    // vec2 dither_uv = vec2(mod(pixel.x, dither_N), mod(pixel.y, dither_N));
    /*
    vec2 dither_uv = vec2(
            mod(float(pixel.x), float(dither_N)) / float(dither_N),
            mod(float(pixel.y), float(dither_N)) / float(dither_N)
        );

    vec3 threshold = texture(dither_sample, dither_uv).rgb;
    
    vec3 dither_color = step(threshold, inCol);

    imageStore(screen_tex, pixel, vec4(dither_color, 1.0));
    */
    //  -------------------------------------------  // 

    //  ----------- Halftone Dithering ------------  //
    vec2 uniform_cell_size = vec2(pms.cell_size_px) / screen_size;
    /*

    vec3 halftone_color;
    // halftone_value(float angle, float color_element, vec2 uni_cell_size, vec2 uv)
    halftone_color.r = halftone_value(angleR, uniform_cell_size, uv);
    halftone_color.g = halftone_value(angleG, uniform_cell_size, uv);
    halftone_color.b = halftone_value(angleB, uniform_cell_size, uv);

    imageStore(screen_tex, pixel, vec4(halftone_color, 1.0));*/
    //  ------------------------------------------  //

    //  ----------- Halftone Dithering Grey ------------  //
    vec2 d = mod(uv, uniform_cell_size) - 0.5 * uniform_cell_size;

    vec3 center_color = texture(screen_sample, uv - d).rgb;
    float grey = 0.299 * center_color.r + 0.587 * center_color.g + 0.114 * center_color.b;

    // float adj_grey = pow(grey, 0.9); // <1 levanta sombras, >1 aplasta

    float dist = length(d);
    float scale = 10.;

    // float rad = adj_grey * uniform_cell_size.x * scale;
    float rad = grey * uniform_cell_size.x * scale;

    vec3 halftone_color = vec3(dist < rad);

    imageStore(screen_tex, pixel, vec4(halftone_color, 1.0));
	// imageStore(screen_tex, pixel, vec4(inCol, 1.0));
}


