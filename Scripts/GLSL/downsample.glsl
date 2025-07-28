#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;

layout(push_constant, std430) uniform Params {
    vec2 screen_size;
    // calculate depth no lineal coords to view coords
    float down_sample;
} pms;

layout(binding = 1, set = 0) uniform sampler2D screen_sample;

void main()
{
	// Convierte la posición global del hilo de cómputo a coordenadas de pixel (x, y)
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);

	// Obtiene el tamaño total de la pantalla desde los push constants
	vec2 size = pms.screen_size;

	// Si el pixel está fuera de los límites, termina la ejecución del hilo
	if (pixel.x >= size.x || pixel.y >= size.y) return;

	// Normaliza las coordenadas del pixel para obtener UV (entre 0 y 1)
	vec2 uv = vec2(pixel) / size;
	//	-----------------
    
    //  Downsampling
    vec2 downUV = floor(pixel / pms.down_sample) * pms.down_sample / size;

    vec3 col;
	col = texture( screen_sample, downUV ).rgb;

	// Escribe el color resultante en la textura de salida
	imageStore(screen_tex, pixel, vec4(col, 1.0));
}

