@tool
class_name VignetteCe extends CompositorEffect

const GLSL_FILE : RDShaderFile = preload("res://Scripts/GLSL/vignette.glsl")

# ------------- Custom Variables
@export_group("Vignette Properties")
@export var vignette_intensity : float = 0.1

@export var vignette_rgba : Vector4 = Vector4( 0.0, 0.0, 0.0, 1.0 );

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

	push_constants.append(vignette_intensity)             # 2
	
		# Total 3 floats actuales → faltan 1 para llegar a 16
	push_constants.append_array([0.0])
	
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
		
		# Vignette Uniform
		var float_array = PackedFloat32Array([vignette_rgba.x, vignette_rgba.y, vignette_rgba.z, vignette_rgba.w])
		var byte_array = float_array.to_byte_array()
		
		var vignette_rid : RID = rd.uniform_buffer_create(byte_array.size(), byte_array)
		var vignette_uniform : RDUniform = RDUniform.new()
		vignette_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_UNIFORM_BUFFER
		vignette_uniform.binding = 0
		vignette_uniform.add_id(vignette_rid)
		
		var vignette_uniform_set : RID = UniformSetCacheRD.get_cache(shader, 1, [vignette_uniform])
		
		# Compute List
		var compute_list : int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, image_uniform_set, 0)
		rd.compute_list_bind_uniform_set(compute_list, vignette_uniform_set, 1)
		rd.compute_list_set_push_constant(compute_list, push_constants.to_byte_array(), push_constants.size() * 4)
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()

func init_compute_shader() -> void:
	rd = RenderingServer.get_rendering_device()
	if not rd: return
	
	shader = rd.shader_create_from_spirv(GLSL_FILE.get_spirv())
	pipeline = rd.compute_pipeline_create(shader)
	
