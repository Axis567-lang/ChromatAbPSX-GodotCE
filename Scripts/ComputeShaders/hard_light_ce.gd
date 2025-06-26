@tool
class_name HardLightCe extends CompositorEffect

# ------------- Custom Variables
@export_group("HardLight Properties")
@export var noise_frequency : float = 1.0
@export var noise_tiling : float = 0.25
@export var noise_intensity : float = 0.025

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
	
	# Time in seconds
	var time_seconds = Time.get_ticks_msec() / 1000.0
	
	# ¡¡¡¡¡¡¡¡¡¡¡¡ MULTIPLOS DE 16 !!!!!!!!!!!
	var push_constants : PackedFloat32Array = PackedFloat32Array()
	push_constants.append(size.x)                         # 0
	push_constants.append(size.y)                         # 1
	
	# ------------- Pushing Export Variables
	push_constants.append(noise_frequency)                # 2
	push_constants.append(noise_tiling)                   # 3
	push_constants.append(noise_intensity)                # 4
	
	push_constants.append(time_seconds)                   # 5
	#
		# Total 6 floats actuales → faltan 2 para llegar a 8
	push_constants.append_array([0.0, 0.0])
	
	# Steer Rendering / VR
	for view in scene_buffers.get_view_count():
		var screen_tex : RID = scene_buffers.get_color_layer(view)
		var depth_tex : RID = scene_buffers.get_depth_layer(view)
		
		# Screen Uniform
		var uniform : RDUniform = RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = 0
		uniform.add_id(screen_tex)
		
		var image_uniform_set : RID = UniformSetCacheRD.get_cache(shader, 0, [uniform])
		
		# Compute List
		var compute_list : int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, image_uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_constants.to_byte_array(), push_constants.size() * 4)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()

func init_compute_shader() -> void:
	rd = RenderingServer.get_rendering_device()
	if not rd: return
	
	var glsl_file : RDShaderFile = load("res://Scripts/GLSL/hard_light.glsl")
	shader = rd.shader_create_from_spirv(glsl_file.get_spirv())
	pipeline = rd.compute_pipeline_create(shader)
	
