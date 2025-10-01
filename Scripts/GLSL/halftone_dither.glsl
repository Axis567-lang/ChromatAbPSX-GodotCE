#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// PARAMETERS
layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;

layout(push_constant, std430) uniform Params {
    vec2 screen_size;
    vec2 dither_tex_size;
    float cell_size_px;
    float dot_scale;
    float levels;
} pms;

layout(binding = 1, set = 0) uniform sampler2D screen_sample;

layout(binding = 0, set = 1) uniform sampler2D dither_sample;

float dither_N = pms.dither_tex_size.x;

// Rotacion en radianes para cada canal (simula CMY halftone angles)
const float angleC = radians(15.0);
const float angleM = radians(75.0);
const float angleY = 0.0;

// Rotacion en radianes para cada canal (simula CMY halftone angles)
const float angleR = 0.0;
const float angleG = radians(2.0);
const float angleB = radians(-2.0);

mat2 rot(float a) {
    return mat2(cos(a), -sin(a),
                sin(a),  cos(a));
}

/*float halftone_value(float angle, vec2 uni_cell_size, float color_element, vec2 uv){
    // vec2 uv_rot = rot(angle) * uv;
    // vec2 d = mod(uv_rot, uni_cell_size) - 0.5 * uni_cell_size;

    // vec2 d = mod(uv, uni_cell_size) - 0.5 * uni_cell_size;

    // ////////////////////////////////////////////////////////////////////////
    /*vec2 uv_centered = uv - 0.5 * pms.screen_size; // centrar la rotación

    vec2 uv_rot = rot(angle) * uv_centered;
    uv_rot += 0.5 * pms.screen_size; // volver a coordenadas originales*/

    // //////////////////////   CELDAS HEX  //////////////////////////////////
    // quitar el comentario /* hehe
    /*vec2 cell;
    cell.x = floor(uv.x / uni_cell_size.x);
    cell.y = floor(uv.y / (uni_cell_size.y * 0.75)); // vertical spacing con overlap

    // offset horizontal para filas impares
    float offset = mod(cell.y, 2.0) * 0.5 * uni_cell_size.x;

    // centro de la celda
    vec2 center = vec2(
        cell.x *uni_cell_size.x + offset + 0.5 * uni_cell_size.x,
        cell.y *uni_cell_size.y * 0.75 + 0.5 * uni_cell_size.y
    );

    vec2 d = uv - center;
    //  //////////////////////////////////////////////////////////////////

    float dist = length(d);

    // vec3 center_color = texture(screen_sample, uv - d).rgb;
    // float grey = 0.299 * center_color.r + 0.587 * center_color.g + 0.114 * center_color.b;

    // Tomamos el minimo entre ancho y alto, 
    //  para que el radio del punto no sobresalga de la celda si la resolucion no es cuadrada.
    float rad = color_element * min(uni_cell_size.x, uni_cell_size.y) * pms.dot_scale;

    // vec2 cell = floor(uv / uni_cell_size);

    float noise = fract(sin(dot(cell, vec2(12.9898,78.233))) * 43758.5453);
    rad *= mix(0.95, 1.05, noise); // +-5% de variacion, suavemente
    
    // return step(dist, rad);
    //  return smoothstep(rad, rad - 0.5, dist);
    float edge = 0.2 * rad;
    return smoothstep(rad, rad - edge, dist);
}*/



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

    //  ---------------------- DITHERING FUSION ----------------------    //

    vec2 uniform_cell_size = vec2(pms.cell_size_px) / screen_size;

    // 1. luminancia
    float lum = dot(inCol, vec3(0.299, 0.587, 0.114));

    // 2. ordered dithering (Bayer)
    vec2 dither_uv = vec2(
        mod(float(pixel.x), float(dither_N)) / float(dither_N),
        mod(float(pixel.y), float(dither_N)) / float(dither_N)
    );
    float threshold = texture(dither_sample, dither_uv).r;

    // 3. cuantización con dithering → nivel discreto
    float scaled = lum * float(pms.levels);
    float dithered = floor(scaled + threshold);
    float level = dithered / float(pms.levels); // [0,1]

    // 4. Halftone: calcular celda y centro
    //      Celdas Hex ----------------------------------------------------------
    /*vec2 cell;
    cell.x = floor(uv.x / uniform_cell_size.x);
    cell.y = floor(uv.y / (uniform_cell_size.y * 0.75));

    float offset = mod(cell.y, 2.0) * 0.5 * uniform_cell_size.x;

    vec2 center = vec2(
        cell.x * uniform_cell_size.x + offset + 0.5 * uniform_cell_size.x,
        cell.y * uniform_cell_size.y * 0.75 + 0.5 * uniform_cell_size.y
    );

    vec2 d = uv - center;
    float dist = length(d);*/
    //      FIN -----------------------------------------------------------------

    //      Celdas Triangulares -------------------------------------------------
    // Escala a un grid triangular
    vec2 q = uv / uniform_cell_size;

    // base de coordenadas para triangulos equilateros
    float s = sqrt(3.0);
    vec2 basisX = vec2(1.0, 0.0);
    vec2 basisY = vec2(0.5, s*0.5);

    // Proyectar
    vec2 tri = vec2(dot(q, basisX), dot(q, basisY));

    // Índices de la celda
    vec2 cell = floor(tri);

    // Centro de celda en coords originales
    vec2 center = (cell.x * basisX + cell.y * basisY) * uniform_cell_size;

    vec2 d = uv - center;
    float dist = length(d);
    //      FIN -----------------------------------------------------------------

    // 5. radio del dot según nivel discreto
    float rad = level * min(uniform_cell_size.x, uniform_cell_size.y) * pms.dot_scale;

    // 6. variación suave para romper repetición
    float noise = fract(sin(dot(cell, vec2(12.9898,78.233))) * 43758.5453);
    rad *= mix(0.95, 1.05, noise);

    // 7. suavizado del borde del punto
    float edge = 0.2 * rad;
    float mask = smoothstep(rad, rad - edge, dist);

    // 8. aplicar al color original
    vec3 outCol = inCol * mask;

    imageStore(screen_tex, pixel, vec4(outCol, 1.0));

    //  --------------------------------------------------------------    //

    
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
    //vec2 uniform_cell_size = vec2(pms.cell_size_px) / screen_size;

    //  Color RGB 
    /*vec3 halftone_color;
    // halftone_value(float angle, float color_element, vec2 uni_cell_size, vec2 uv)
    halftone_color.r = halftone_value(angleR, uniform_cell_size, inCol.r, uv);
    halftone_color.g = halftone_value(angleG, uniform_cell_size, inCol.g, uv);
    halftone_color.b = halftone_value(angleB, uniform_cell_size, inCol.b, uv);*/

    //  Convertir a CMY
    /*vec3 cmy = 1.0 - inCol;

    float c = halftone_value(angleC, uniform_cell_size, cmy.r, uv);
    float m = halftone_value(angleM, uniform_cell_size, cmy.g, uv);
    float y = halftone_value(angleY, uniform_cell_size, cmy.b, uv);
    // aka
    vec3 halftone_color = 1.0 - vec3(c, m, y); // de vuelta a RGB*/

    //  RGB pero ahora sí respetando el color
    /*float r_dot = halftone_value(angleR, uniform_cell_size, inCol.r, uv);
    float g_dot = halftone_value(angleG, uniform_cell_size, inCol.g, uv);
    float b_dot = halftone_value(angleB, uniform_cell_size, inCol.b, uv);

    vec3 halftone_color = vec3(
        inCol.r * r_dot,
        inCol.g * g_dot,
        inCol.b * b_dot
    );

    imageStore(screen_tex, pixel, vec4(halftone_color, 1.0));*/
    //  ------------------------------------------  //

    //  ----------- Halftone Dithering Grey ------------  //
    /*vec2 d = mod(uv, uniform_cell_size) - 0.5 * uniform_cell_size;

    vec3 center_color = texture(screen_sample, uv - d).rgb;
    float grey = 0.299 * center_color.r + 0.587 * center_color.g + 0.114 * center_color.b;

    // float adj_grey = pow(grey, 0.9); // <1 levanta sombras, >1 aplasta

    float dist = length(d);
    float scale = 10.;

    // float rad = adj_grey * uniform_cell_size.x * scale;
    float rad = grey * uniform_cell_size.x * scale;

    vec3 halftone_color = vec3(dist < rad);

    imageStore(screen_tex, pixel, vec4(halftone_color, 1.0));*/
    //  ----------- ----------------------- ------------  //


	// imageStore(screen_tex, pixel, vec4(inCol, 1.0));
}

