#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;

layout(push_constant, std430) uniform Params {
    vec2 screen_size;
} pms;

void main()
{
    ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);
    vec2 size = pms.screen_size;

    if(pixel.x >= size.x || pixel.y >= size.y) return;

    vec4 color = imageLoad(screen_tex, pixel);
    
    color.rgb = 1. - color.rgb;
    
    imageStore(screen_tex, pixel, color);
}