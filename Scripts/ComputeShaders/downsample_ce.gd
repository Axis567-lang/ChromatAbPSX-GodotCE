@tool
class_name DownSampleCe extends CompositorEffect

@export_range(0.0, 40.0, 0.01) var down_sample : float = 10

const GLSL_FILE : RDShaderFile = preload("res://Scripts/GLSL/downsample.glsl")

var rd : RenderingDevice
var shader : RID
var pipeline : RID
var nearest_sampler : RID

func _notification(what : int):
	if what == NOTIFICATION_PREDELETE:
		if shader : RenderingServer.free_rid(shader)
		if pipeline : RenderingServer.free_rid(pipeline)
		if nearest_sampler : RenderingServer.free_rid(nearest_sampler)

func _init():
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	RenderingServer.call_on_render_thread(_init_compute)

func _init_compute():
	rd = RenderingServer.get_rendering_device()
	if !rd : return
	
	# Create a sampler for our screen texture
	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	nearest_sampler = rd.sampler_create(sampler_state)
	
	# Compile the compute shader and build pipeline
	var spirv : RDShaderSPIRV = GLSL_FILE.get_spirv()
	shader = rd.shader_create_from_spirv(spirv)
	pipeline = rd.compute_pipeline_create(shader)

func _render_callback(p_callback_type : int, render_data : RenderData):
	if !rd or p_callback_type != effect_callback_type or !pipeline : return
	
	var render_scene_buffers : RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	if !render_scene_buffers : return
	
	var size : Vector2i = render_scene_buffers.get_internal_size()
	if size.x == 0 or size.y == 0 : return
	
	# Compute dispatch groups for local_size {16x,16x,1}
	var x_groups := int((size.x - 1) / 16.0) + 1
	var y_groups := int((size.y - 1) / 16.0) + 1
	
	# Pack push constants : [raster_size.x, raster_size.y, polarity, edge_fade]
	var push_constants := PackedFloat32Array([
		size.x,
		size.y,
		down_sample,
		])
	push_constants.append_array([0.0])
	var push_data : PackedByteArray = push_constants.to_byte_array()

	# Loop over each view (monoscopic = 1 view)
	var view_count : int = render_scene_buffers.get_view_count()
	for view in range(view_count):
		var screen_tex : RID = render_scene_buffers.get_color_layer(view)
		if !screen_tex : continue
		
		# Bind image at binding 1 (rgba16f)
		var image_uniform := RDUniform.new()
		image_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		image_uniform.binding = 0
		image_uniform.add_id(screen_tex)

		# Bind sampler + texture at binding 0
		var sampler_uniform := RDUniform.new()
		sampler_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		sampler_uniform.binding = 1
		sampler_uniform.add_id(nearest_sampler)
		sampler_uniform.add_id(screen_tex)
		
		var uniform_set : RID = UniformSetCacheRD.get_cache(shader, 0, [image_uniform, sampler_uniform])
		
		# Record and submit compute commands
		var compute_list : int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()
