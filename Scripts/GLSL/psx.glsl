#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;

layout(binding = 0, set = 1) uniform sampler2D gradient;
layout(binding = 0, set = 2) uniform sampler2D dither;

layout(binding = 0, set = 3) uniform sampler2D screen_sample;

layout(push_constant, std430) uniform Params {
    vec2 screen_size;

	float psx_toggle; // usar como bool en logica
	float dither_scale;
} pms;

//	FUNCTION
vec3 psx_tex(vec3 col, sampler2D tex, vec2 uv) {
	vec2 dither_size = vec2(textureSize(dither, 0)); // for GLES2: substitute for the dimensions of the dithering matrix
	vec2 buf_size = vec2(textureSize(tex, 0)) * pms.dither_scale;
	vec3 dither_vec = texture(dither, uv * (buf_size / dither_size)).rgb - 0.5;

	float gradient_size = float( textureSize(gradient, 0).x );
	return round(col * gradient_size + dither_vec) / gradient_size;
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

	vec3 col_psx = mix(color.rgb, psx_tex(color.rgb, screen_sample, uv), pms.psx_toggle);

	imageStore(screen_tex, pixel, vec4(col_psx, 1.0));
}

