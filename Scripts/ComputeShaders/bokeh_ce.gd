@tool
class_name BokehCe extends CompositorEffect

@export var display_gamma : float = 1.8
@export_range(0, 360, 1) var golden_angle : float = 2.39996323
@export var max_blur_size : float = 20.0
@export_range(0, 1, 0.001) var rad_scale : float = 0.1
@export var u_far : float = 10.0

@export var focus_point : float = 10.0
@export var focus_scale : float = 20.0

const GLSL_FILE : RDShaderFile = preload("res://Scripts/GLSL/bokeh.glsl")

var rd : RenderingDevice
var shader : RID
var pipeline : RID
var sampler_linear : RID

# executes whenever it receives a notif signal: post-initialize,pre-delete and extension reload
func _notification(what: int) -> void:
	if what == NOTIFICATION_PREDELETE:
		if shader : RenderingServer.free_rid(shader)
		if pipeline : RenderingServer.free_rid(pipeline)
		if sampler_linear : RenderingServer.free_rid(sampler_linear)

func _init() -> void:
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	RenderingServer.call_on_render_thread(_init_compute)

func _init_compute():
	rd = RenderingServer.get_rendering_device()
	if !rd : return
	
	# Create a sampler for our screen texture
	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_linear = rd.sampler_create(sampler_state)
	
	# Compile the compute shader and build pipeline
	var spirv : RDShaderSPIRV = GLSL_FILE.get_spirv()
	shader = rd.shader_create_from_spirv(spirv)
	pipeline = rd.compute_pipeline_create(shader)

func _render_callback(p_callback_type : int, render_data: RenderData) -> void:
	if !rd or p_callback_type != effect_callback_type or !pipeline : return
	
	var render_scene_buffers : RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	var render_scene_data : RenderSceneDataRD = render_data.get_render_scene_data()
	if !render_scene_buffers or !render_scene_data : return
	
	# Resolution
	var size : Vector2i = render_scene_buffers.get_internal_size()
	if size.x == 0 or size.y == 0 : return
	
	# Compute dispatch groups for local_size {16x,16x,1}
	var x_groups := int((size.x - 1) / 16.0) + 1
	var y_groups := int((size.y - 1) / 16.0) + 1
	
	# Projection
	var inv_proj_mat : Projection = render_scene_data.get_cam_projection().inverse()
	
	# Pack push constants : [raster_size.x, raster_size.y, polarity, edge_fade]
	var push_constants := PackedFloat32Array([
		size.x, 
		size.y, 
		inv_proj_mat[2].w, 
		inv_proj_mat[3].w,
		
		display_gamma,
		golden_angle,
		max_blur_size,
		rad_scale,
		
		u_far,
		focus_point,
		focus_scale
	])
	push_constants.append_array([0.0])
	var push_data : PackedByteArray = push_constants.to_byte_array()
	
	# Steer Rendering / VR
	var view_count : int = render_scene_buffers.get_view_count()
	# Loop over each view (monoscopic = 1 view)
	for view in range(view_count):
		var screen_tex : RID = render_scene_buffers.get_color_layer(view)
		var depth_tex : RID = render_scene_buffers.get_depth_layer(view)
		if !screen_tex or !depth_tex : continue
		
		# Screen Uniform
		var uniform : RDUniform = RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		uniform.binding = 0
		uniform.add_id(screen_tex)
		
		var image_uniform_set : RID = UniformSetCacheRD.get_cache(shader, 0, [uniform])
		
		# Depth Uniform
		uniform = RDUniform.new()
		uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		uniform.binding = 0
		uniform.add_id(sampler_linear)
		uniform.add_id(depth_tex)
		
		var depth_uniform_set : RID = UniformSetCacheRD.get_cache(shader, 1, [uniform])
		
		# Compute List
		var compute_list : int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, image_uniform_set, 0)
		rd.compute_list_bind_uniform_set(compute_list, depth_uniform_set, 1)
		rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()

func init_compute_shader() -> void:
	rd = RenderingServer.get_rendering_device()
	if not rd: return
	
	shader = rd.shader_create_from_spirv(GLSL_FILE.get_spirv())
	pipeline = rd.compute_pipeline_create(shader)
	
