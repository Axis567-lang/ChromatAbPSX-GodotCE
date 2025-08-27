#[compute]
#version 450

layout(local_size_x = 16, local_size_y = 16, local_size_z = 1) in;

// PARAMETERS
layout(rgba16f, binding = 0, set = 0) uniform image2D screen_tex;

layout(push_constant, std430) uniform Params {
    vec2 screen_size;
    vec2 lut_tex_size;
} pms;

layout(binding = 1, set = 0) uniform sampler2D screen_sample;

layout(binding = 0, set = 1) uniform sampler2D lut_sample;

// VARIABLE
int lut_N_i = int( pow(pms.lut_tex_size.x * pms.lut_tex_size.y, 1.0/3.0) );
float lut_N = float(lut_N_i);

//  #---------- QUANTIZATION BY LUT INDEXING ----------#

// FUNCTIONS
/*vec2 computeUV(vec3 index)
{
    float slice = index.z; // capa en Z
    float x = index.x + slice * lut_N;
    float y = index.y;

    return (vec2(x, y) + 0.5) / pms.lut_tex_size;
}*/
// TEST 5 
vec2 computeUV(vec3 index)
{
    // index = floor(color * (lut_N - 1))
    float slice = index.z;

    // Para LUT 64x64x64 en textura 512x512
    float tilesPerRow = pms.lut_tex_size.x / lut_N; // 512 / 64

    float tileX = mod(slice, tilesPerRow);
    float tileY = floor(slice / tilesPerRow);

    float x = index.x + tileX * lut_N;
    float y = index.y + tileY * lut_N;
    x = clamp(x, 0.0, pms.lut_tex_size.x - 1.0);
    y = clamp(y, 0.0, pms.lut_tex_size.y - 1.0);

    return (vec2(x, y) + 0.5) / pms.lut_tex_size;
}

// MAIN
void main()
{
	// Convierte la posicion global del hilo de computo a coordenadas de pixel (x, y)
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);

	// Obtiene el tamaño total de la pantalla desde los push constants
	vec2 size = pms.screen_size;

	// Si el pixel esta fuera de los limites, termina la ejecucion del hilo
	if (pixel.x >= size.x || pixel.y >= size.y) return;

	// Normaliza las coordenadas del pixel para obtener UV (entre 0 y 1)
	vec2 uv = vec2(pixel) / size;
	//	-----------------

    vec3 inCol = texture(screen_sample, uv).rgb;
    vec3 index = floor(inCol * (lut_N - 1.0));

    vec2 lut_uv = computeUV(index);
    vec3 lut_color = texture(lut_sample, lut_uv).rgb;

    imageStore(screen_tex, pixel, vec4(lut_color, 1.0));
	// imageStore(screen_tex, pixel, vec4(inCol, 1.0));
}
// # -------------------------------------------------------------------- #

// # --------- QUANTIZATION BY LUMINANCE ------ #
/*
// FUNCTIONS
vec2 computeUV(vec3 index) 
{
    float slice = index.z; // capa en Z
    float x = index.x + slice * lut_N;
    float y = index.y;

    return (vec2(x, y) + 0.5) / lut_tex_size;

}

// MAIN
void main()
{
	// Convierte la posicion global del hilo de computo a coordenadas de pixel (x, y)
	ivec2 pixel = ivec2(gl_GlobalInvocationID.xy);

	// Obtiene el tamaño total de la pantalla desde los push constants
	vec2 size = pms.screen_size;

	// Si el pixel está fuera de los limites, termina la ejecución del hilo
	if (pixel.x >= size.x || pixel.y >= size.y) return;

	// Normaliza las coordenadas del pixel para obtener UV (entre 0 y 1)
	vec2 uv = vec2(pixel) / size;
	//	-----------------

    vec3 inCol = texture(screen_sample, uv).rgb;
    vec3 index = floor(inCol * (lut_N - 1.0));

    // float lum = dot( inCol, vec3( 0.2126, 0.7152, 0.0722 ) );
	// vec3 color_lum = texture( lut_sample, vec2(lum, 0) ).rgb;

    float lum = dot(inCol, vec3(0.2126, 0.7152, 0.0722));
    vec2 uv_lut = vec2(lum, 0.5); // usar el centro vertical de la LUT
    vec3 color_lum = texture(lut_sample, uv_lut).rgb;


    // imageStore(screen_tex, pixel, vec4(lut_color, 1.0));
    imageStore(screen_tex, pixel, vec4(color_lum, 1.0));
}
*/
// # -------------------------------------------------------------------- #

/*
#define dot2(a) dot(a,a)
#define scale 10.

// Conversions from https://www.shadertoy.com/view/wt23Rt
vec3 rgb2xyz(vec3 c)
{
	vec3 tmp=vec3(
		(c.r>.04045)?pow((c.r+.055)/1.055,2.4):c.r/12.92,
		(c.g>.04045)?pow((c.g+.055)/1.055,2.4):c.g/12.92,
		(c.b>.04045)?pow((c.b+.055)/1.055,2.4):c.b/12.92
	);
	mat3 mat=mat3(
		.4124,.3576,.1805,
		.2126,.7152,.0722,
		.0193,.1192,.9505
	);
	return 100.*(tmp*mat);
}

vec3 xyz2lab(vec3 c)
{
	vec3 n=c/vec3(95.047,100.,108.883),
	     v=vec3(
		(n.x>.008856)?pow(n.x,1./3.):(7.787*n.x)+(16./116.),
		(n.y>.008856)?pow(n.y,1./3.):(7.787*n.y)+(16./116.),
		(n.z>.008856)?pow(n.z,1./3.):(7.787*n.z)+(16./116.)
	);
	return vec3((116.*v.y)-16.,500.*(v.x-v.y),200.*(v.y-v.z));
}

// Perceptual color difference
float CIE94( vec3 a, vec3 b ) 
{
	float aC = sqrt(a.y*a.y+a.z*a.z);
	float bC = sqrt(b.y*b.y+b.z*b.z);

	float L2 = (a.x-b.x)*(a.x-b.x);
	float C2 = (aC - bC)*(aC - bC);
	float H2 = (a.y-b.y)*(a.y-b.y) + (a.z-b.z)*(a.z-b.z) - C2;

	return sqrt(
		L2 + 
		C2 / ((1.+ 0.045*aC)*(1.+ 0.045*aC)) +
		H2 / ((1.+ 0.015*aC)*(1.+ 0.015*aC))
	);
}

float colorDiff( vec3 a, vec3 b )
{
    a = xyz2lab(rgb2xyz(a));
    b = xyz2lab(rgb2xyz(b));
    return CIE94(a,b);
}

// Palette from https://lospec.com/palette-list/mulfok32
#define paletteSize 32
vec3 palette[] = vec3[](
vec3(0.357,0.651,0.459), // #5ba675
vec3(0.420,0.788,0.424), // #6bc96c
vec3(0.671,0.867,0.392), // #abdd64
vec3(0.988,0.937,0.553), // #fcef8d
vec3(1.000,0.722,0.475), // #ffb879
vec3(0.918,0.384,0.384), // #ea6262
vec3(0.800,0.259,0.369), // #cc425e
vec3(0.639,0.157,0.345), // #a32858
vec3(0.459,0.090,0.337), // #751756
vec3(0.224,0.035,0.278), // #390947
vec3(0.380,0.094,0.318), // #611851
vec3(0.529,0.208,0.333), // #873555
vec3(0.651,0.333,0.373), // #a6555f
vec3(0.788,0.451,0.451), // #c97373
vec3(0.949,0.682,0.600), // #f2ae99
vec3(1.000,0.765,0.949), // #ffc3f2
vec3(0.933,0.561,0.796), // #ee8fcb
vec3(0.831,0.431,0.702), // #d46eb3
vec3(0.529,0.243,0.518), // #873e84
vec3(0.122,0.063,0.165), // #1f102a
vec3(0.290,0.188,0.322), // #4a3052
vec3(0.482,0.329,0.502), // #7b5480
vec3(0.651,0.522,0.624), // #a6859f
vec3(0.851,0.741,0.784), // #d9bdc8
vec3(1.000,1.000,1.000), // #ffffff
vec3(0.682,0.886,1.000), // #aee2ff
vec3(0.553,0.718,1.000), // #8db7ff
vec3(0.427,0.502,0.980), // #6d80fa
vec3(0.518,0.396,0.925), // #8465ec
vec3(0.514,0.302,0.769), // #834dc4
vec3(0.490,0.176,0.627), // #7d2da0
vec3(0.306,0.094,0.486)  // #4e187c 
);

// Quantize with distances in RGB
vec3 quantizeRGB( vec3 inCol )
{
    vec3 col = vec3(0);
    float nearest = 100.0;
    
    for (int i = 0; i < paletteSize; i++)
    {
        vec3 paletteCol = palette[i];
        float dist = dot2(paletteCol - inCol);
        
        if (dist < nearest) 
        {
            col = paletteCol;
            nearest = dist;
        }
    }
    
    return col;
}

// Quantize with CIE94 Color difference
vec3 quantizeCIE94( vec3 inCol )
{
    vec3 col = vec3(0);
    float nearest = 100.0;
    
    for (int i = 0; i < paletteSize; i++)
    {
        vec3 paletteCol = palette[i];
        float dist = colorDiff(paletteCol, inCol);
        
        if (dist < nearest) 
        {
            col = paletteCol;
            nearest = dist;
        }
    }
    
    return col;
}

void mainImage( out vec4 fragColor, in vec2 fragCoord )
{
    // Square coordinates
    vec2 uv = (fragCoord - vec2((iResolution.x - iResolution.y)/2.,0))/iResolution.y;
    uv.y = 1. - uv.y;

    // Tiling
    vec3 col = vec3(fract(uv * scale),floor(uv.x * scale) / (scale*scale) + floor(uv.y * scale) / scale);

    // Border
    if (uv.x < 0. || uv.x >= 1.) 
    {
        col = uv.x > -.35 ? vec3(0) : palette[int(uv.y*float(paletteSize))];
    }
    
    // Quantization type

    int type = (int(iTime) / 2) % 3;
    if (type == 1)
    {
        col = quantizeRGB(col);
    } 
    else if (type == 2) 
    {
        col = quantizeCIE94(col);
    }
    
    // Output to screen
    fragColor = vec4(col,1.0);
}
*/