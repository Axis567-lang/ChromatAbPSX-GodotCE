#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;

layout(binding = 0, set = 1) uniform sampler2D gradient;

layout(push_constant, std430) uniform Params {
    vec2 screen_size;

	float gradient_flip; // usar como bool
	float gradient_intensity;
} pms;

//	FUNCTION
vec3 palette(vec3 col) {
	float lum = dot( col, vec3( 0.2126, 0.7152, 0.0722 ) );
	return texture( gradient, vec2(abs(float(pms.gradient_flip) - lum), 0) ).rgb;
}

void main()
{
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);			// screen
    vec2 res = pms.screen_size;								// res
    // calculate uv
    vec2 uv = pixel / res;									// uv								

    if(pixel.x >= res.x || pixel.y >= res.y) return;

    vec4 color = imageLoad(screen_tex, pixel);				// col

	vec3 col_pal = mix(color.rgb, palette(color.rgb), pms.gradient_intensity);

	imageStore(screen_tex, pixel, vec4(col_pal, 1.0));
}
