@tool
class_name PaletteRemapCe extends CompositorEffect

const GLSL_FILE : RDShaderFile = preload("res://Scripts/GLSL/palette_remap.glsl")

# ------------- Custom Variables
@export_group("Palette Properties")
@export var gradient_flip : bool = false
@export var gradient_intensity : float = 0.15

@export var gradient : Texture2D

# ------------- Rendering Variables
var rd : RenderingDevice
var shader : RID
var pipeline : RID

func _init() -> void:
	RenderingServer.call_on_render_thread(init_compute_shader)

# executes whenever it receives a notif signal: post-initialize,pre-delete and extension reload
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE and shader.is_valid():
		RenderingServer.free_rid(shader)

func _render_callback(effect_callback_type: int, render_data: RenderData) -> void:
	# define workgroups, pass data to gpu and get results
	if not rd: return
	
	var scene_buffers : RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	var scene_data : RenderSceneDataRD = render_data.get_render_scene_data()
	if not scene_buffers or not scene_data : return
	
	# Resolution
	var size : Vector2i = scene_buffers.get_internal_size()
	if size.x == 0 or size.y == 0 : return
	
	# 16 threads
	var x_groups : int = size.x / 16 + 1
	var y_groups : int = size.y / 16 + 1
	
	# ¡¡¡¡¡¡¡¡¡¡¡¡ MULTIPLOS DE 16 !!!!!!!!!!!
	var push_constants : PackedFloat32Array = PackedFloat32Array()
	push_constants.append(size.x)                         # 0
	push_constants.append(size.y)                         # 1

	push_constants.append(float(gradient_flip))           # 2
	push_constants.append(gradient_intensity)             # 3
	
	# Steer Rendering / VR
	for view in scene_buffers.get_view_count():
		var screen_tex : RID = scene_buffers.get_color_layer(view)
		
		# Screen Uniform
		var uniform : RDUniform = RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = 0
		uniform.add_id(screen_tex)
		
		var image_uniform_set : RID = UniformSetCacheRD.get_cache(shader, 0, [uniform])
		
		# Gradient Uniform
		if gradient == null:
			gradient = preload("res://Palettes/bastille_1x8.tres") # tu textura por defecto
		#print("Gradient: ", gradient)
		
		var g_img : Image = gradient.get_image()
		g_img.convert(Image.FORMAT_RGBAF)
		#print("Image: ", g_img)
		
		var g_fmt = RDTextureFormat.new()
		g_fmt.width = g_img.get_width()
		g_fmt.height = g_img.get_height()
		g_fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
		g_fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		
		var g_sampler_state : RDSamplerState = RDSamplerState.new()
		g_sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		g_sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		g_sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
		g_sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
		#print("Sampler: ", g_sampler_state)
		
		var g_linear_sampler : RID = rd.sampler_create(g_sampler_state)
		#print("Linear Sampler: ", g_linear_sampler)
		
		var g_tex_view = RDTextureView.new()
		
		var g_tex = rd.texture_create(g_fmt, g_tex_view, [g_img.get_data()])
		var g_sampler_uniform := RDUniform.new()
		g_sampler_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		g_sampler_uniform.binding = 0
		g_sampler_uniform.add_id(g_linear_sampler)
		g_sampler_uniform.add_id(g_tex)
		
		var g_uniform_set: RID = rd.uniform_set_create([g_sampler_uniform], shader, 1)
		
		# Compute List
		var compute_list : int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, image_uniform_set, 0)
		rd.compute_list_bind_uniform_set(compute_list, g_uniform_set, 1)
		rd.compute_list_set_push_constant(compute_list, push_constants.to_byte_array(), push_constants.size() * 4)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()

func init_compute_shader() -> void:
	rd = RenderingServer.get_rendering_device()
	if not rd: return
	
	shader = rd.shader_create_from_spirv(GLSL_FILE.get_spirv())
	pipeline = rd.compute_pipeline_create(shader)
	
