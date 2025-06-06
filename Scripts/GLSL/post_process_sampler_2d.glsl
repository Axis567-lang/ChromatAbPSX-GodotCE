#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;
layout(binding = 0, set = 1) uniform sampler2D depth_tex;

layout(push_constant, std430) uniform Params {
    vec2 screen_size;
    // calculate depth no lineal coords to view coords
    float inv_proj_2w;
    float inv_proj_3w;
} pms;

void main()
{
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    vec2 size = pms.screen_size;
    // calculate uv
    vec2 uv = pixel / size;

    if(pixel.x >= size.x || pixel.y >= size.y) return;

    float depth = texture(depth_tex, uv).r;
    float linear_depth = 1. / (depth * pms.inv_proj_2w + pms.inv_proj_3w);
    linear_depth = clamp(linear_depth / 50., 0., 1.);

    vec4 color = imageLoad(screen_tex, pixel);
    
    color.rgb = vec3(linear_depth);
    
    imageStore(screen_tex, pixel, color);

    //imageStore(screen_tex, pixel, vec4(vec3(depth), 1.0));
    // imageStore(screen_tex, pixel, vec4(vec3(depth), 1.0));  // Asigna directamente el valor de profundidad
    //imageStore(screen_tex, pixel, vec4(linear_depth, 0.0, 0.0, 1.0));  // Usar solo el canal rojo para verificar el valor
    // imageStore(screen_tex, pixel, vec4(linear_depth, linear_depth, linear_depth, 1.0));  // Usar los tres canales para ver si hay diferencia

}



/* ORTHOGONAL (yesiamthatstupid)
void main()
{
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
	vec2 size = pms.screen_size;
	vec2 uv = pixel / size;

	if (pixel.x >= size.x || pixel.y >= size.y) return;

    float depth = texture(depth_tex, uv).r;

	// Aplicar un mapeo manual para aumentar contraste
	float mapped_depth = (depth - 0.5) * 50.0; // Ajusta los valores si la imagen sigue uniforme
	mapped_depth = clamp(mapped_depth, 0.0, 1.0);

	// Mostrar profundidad en escala de grises
	imageStore(screen_tex, pixel, vec4(mapped_depth, mapped_depth, mapped_depth, 1.0));
}
*/

