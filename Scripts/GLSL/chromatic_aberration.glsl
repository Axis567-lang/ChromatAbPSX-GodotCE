#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;

layout(binding = 0, set = 1) uniform sampler2D screen_sample;

layout(push_constant, std430) uniform Params {
    vec2 screen_size;

	float chromab_polarity;

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

vec3 chrom_ab( sampler2D screen, vec2 uv ) {
	float amount = 0.0016;

	vec3 col;
	col.r = texture( screen, vec2( uv.x - amount, uv.y ) ).r;
	col.b = texture( screen, vec2( uv.x + amount, uv.y ) ).b;
	col.g = texture( screen, vec2( uv.x, uv.y - amount ) ).g;

	return col;
}

// vec3 ACESFilm(vec3 x) {
// 	const float a = 2.51;
// 	const float b = 0.03;
// 	const float c = 2.43;
// 	const float d = 0.59;
// 	const float e = 0.14;
// 	return clamp((x * (a * x + b)) / (x * (c * x + d) + e), 0.0, 1.0);
// }

// vec3 reinhard(vec3 x, float white_point)
// {
// 	return x / (x + vec3(white_point));
// }

// float remap(float val, float oldMin, float oldMax) {
//     return clamp((val - oldMin) / (oldMax - oldMin), 0.0, 1.0);
// }

void main()
{
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);			// screen
    vec2 res = pms.screen_size;								// res
    // calculate uv
    vec2 uv = pixel / res;									// uv								

    if(pixel.x >= res.x || pixel.y >= res.y) return;

    vec4 color = imageLoad(screen_tex, pixel);				// col

	//	Parameters
	// float c = 1.0 + pms.chromab_polarity - pow(radial_mask(uv), pms.vignette_intensity);

	// SOL 1 -> si chr_pol o vgt_int baja de 0 no pasa nada. No sé si eso sea muy correcto
	// float c = clamp(1.0 + pms.chromab_polarity - pow(radial_mask(uv), pms.vignette_intensity), 0.0, 1.0);

	// SOL 2
	// float mask = radial_mask(uv);
	// float soft_vignette = smoothstep(0.0, 1.0, pow(mask, pms.vignette_intensity));
	// // float c = 1.0 + pms.chromab_polarity - soft_vignette; //	sin clamp -> sí aparecen flashes
	// float c = clamp(1.0 + pms.chromab_polarity - soft_vignette, 0.0, 1.0);

	// SOL 3
		// -->
	// float mask = smoothstep(0.0, 1.0, radial_mask(uv));
	// float c = clamp(1.0 + pms.chromab_polarity - mask * pms.vignette_intensity, 0.0, 1.0);
		
		// -->
	// float c_raw = 1.0 + pms.chromab_polarity - pow(radial_mask(uv), pms.vignette_intensity);
	float c_raw = 1.0 + pms.chromab_polarity + radial_mask(uv) * pms.vignette_intensity;

	float c_min = -0.5;       // valor mínimo esperado para c_raw
	float c_max = 1.0;       // valor máximo esperado para c_raw

	// float c = remap(c_raw, c_min, c_max);

	float c = smoothstep(c_min, c_max, c_raw);

	vec3 col_chr = mix(color.rgb, chrom_ab(screen_sample, uv), c);

	// col_chr = ACESFilm(col_chr);
	// col_chr = reinhard(col_chr, 1.5); // Valores >1 se comprimen; <=1 quedan casi igual

	imageStore(screen_tex, pixel, vec4(col_chr, 1.0));
}
