#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;

layout(set = 1, binding = 0, std140) uniform VignetteData {
	vec4 vignette_rgba;
} vgt;

layout(push_constant, std430) uniform Params {
    vec2 screen_size;

	float vignette_intensity;

} pms;

//	FUNCTIONS
float radial_mask( vec2 uv ) {
	// Esto produce una curva que vale 0 en 0 y 1, y tiene un pico en 0.5.
	uv *= 1.0 - uv;
	//	Se escala por 16.0 para amplificar el rango (0 a 1).
	float mask = uv.x * uv.y * 16.0;
	return mask;
}

//	MAIN
void main()
{
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);			// screen
    vec2 res = pms.screen_size;								// res
    // calculate uv
    vec2 uv = pixel / res;									// uv								

    if(pixel.x >= res.x || pixel.y >= res.y) return;

    vec4 color = imageLoad(screen_tex, pixel);				// col

	//	Parameter
	float v = 1.0 - pow(radial_mask(uv), pms.vignette_intensity);

	vec3 col_vig = mix(color.rgb, vgt.vignette_rgba.rgb * v, vgt.vignette_rgba.a * v);

	imageStore(screen_tex, pixel, vec4(col_vig, 1.0));
}
