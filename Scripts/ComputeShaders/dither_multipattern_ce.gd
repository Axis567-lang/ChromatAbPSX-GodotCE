@tool
class_name DitherMultipatternCe extends CompositorEffect

const GLSL_FILE : RDShaderFile = preload("res://Scripts/GLSL/dither_multipattern.glsl")

#    VARS
@export var dith_tex_1 : Image :
	set(value):
		if value != null:
			_dither_tex_1 = value
			dither_tex_rid_1 = change_dither(_dither_tex_1)

@export var dith_tex_2 : Image :
	set(value):
		if value != null:
			_dither_tex_2 = value
			dither_tex_rid_2 = change_dither(_dither_tex_2)

@export var dith_tex_3 : Image :
	set(value):
		if value != null:
			_dither_tex_3 = value
			dither_tex_rid_3 = change_dither(_dither_tex_3)

@export_range(2, 100, 1) var levels : int = 15

var _dither_tex_1 : Image
var _dither_tex_2 : Image
var _dither_tex_3 : Image

var rd : RenderingDevice
var shader : RID
var pipeline : RID
var linear_sampler : RID

var dither_nearest_sampler : RID
var dither_tex_rid_1 : RID
var dither_tex_rid_2 : RID
var dither_tex_rid_3 : RID

func change_dither(new_dither_tex : Image):
	new_dither_tex.convert(Image.FORMAT_RGBAF)
	
	var dither_fmt = RDTextureFormat.new()
	dither_fmt.width = new_dither_tex.get_width()
	dither_fmt.height = new_dither_tex.get_height()
	dither_fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	dither_fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	
	var dither_sampler_state : RDSamplerState = RDSamplerState.new()
	dither_sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	dither_sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	dither_sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	dither_sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	
	dither_nearest_sampler = rd.sampler_create(dither_sampler_state)
	
	var dither_tex_view = RDTextureView.new()
	
	return rd.texture_create(dither_fmt, dither_tex_view, [new_dither_tex.get_data()])

func _notification(what : int):
	if what == NOTIFICATION_PREDELETE:
		if shader : RenderingServer.free_rid(shader)
		if pipeline : RenderingServer.free_rid(pipeline)
		if linear_sampler : RenderingServer.free_rid(linear_sampler)
		if dither_nearest_sampler : RenderingServer.free_rid(dither_nearest_sampler)
		if dither_tex_rid_1 : RenderingServer.free_rid(dither_tex_rid_1)
		if dither_tex_rid_2 : RenderingServer.free_rid(dither_tex_rid_2)
		if dither_tex_rid_3 : RenderingServer.free_rid(dither_tex_rid_3)

func _init():
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	RenderingServer.call_on_render_thread(_init_compute)

func _init_compute():
	rd = RenderingServer.get_rendering_device()
	if !rd : return
	
	if _dither_tex_1 == null:
		#_dither_tex_1 = preload("res://DitherTextures/Bayer/bayer2.png")
		_dither_tex_1 = preload("res://DitherTextures/Custom/one-dot-4x4.png")
		dither_tex_rid_1 = change_dither(_dither_tex_1)
	
	if _dither_tex_2 == null:
		#_dither_tex_2 = preload("res://DitherTextures/Custom/dith-tex-2-8x8.png")
		_dither_tex_2 = preload("res://DitherTextures/Custom/trebol-dot-4x4.png")
		dither_tex_rid_2 = change_dither(_dither_tex_2)
	
	if _dither_tex_3 == null:
		#_dither_tex_3 = preload("res://DitherTextures/Bayer/bayer8.png")
		_dither_tex_3 = preload("res://DitherTextures/Custom/cruz-dot-4x4.png")
		dither_tex_rid_3 = change_dither(_dither_tex_3)
	
	# Create a sampler for our screen texture
	var sampler_state := RDSamplerState.new()
	sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.mip_filter = RenderingDevice.SAMPLER_FILTER_LINEAR
	sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
	linear_sampler = rd.sampler_create(sampler_state)
	
	# Compile the compute shader and build pipeline
	var spirv : RDShaderSPIRV = GLSL_FILE.get_spirv()
	shader = rd.shader_create_from_spirv(spirv)
	pipeline = rd.compute_pipeline_create(shader)

func _render_callback(p_callback_type : int, render_data : RenderData):
	if !rd or p_callback_type != effect_callback_type or !pipeline : return
	
	var render_scene_buffers : RenderSceneBuffersRD = render_data.get_render_scene_buffers()
	var render_scene_data : RenderSceneDataRD = render_data.get_render_scene_data()
	if !render_scene_buffers or !render_scene_data : return
	
	var size : Vector2i = render_scene_buffers.get_internal_size()
	if size.x == 0 or size.y == 0 : return
	
	# Compute dispatch groups for local_size {16x,16x,1}
	var x_groups := int((size.x - 1) / 16.0) + 1
	var y_groups := int((size.y - 1) / 16.0) + 1
	
	#   Dither Texture     1
	var dither_width_1 : float = _dither_tex_1.get_width();
	var dither_height_1 : float = _dither_tex_1.get_height();
	
	var dither_tex_size_1 : Vector2  = Vector2(dither_width_1, dither_height_1);
	
	#   Dither Texture     2
	var dither_width_2 : float = _dither_tex_2.get_width();
	var dither_height_2 : float = _dither_tex_2.get_height();
	
	var dither_tex_size_2 : Vector2  = Vector2(dither_width_2, dither_height_2);
	
	#   Dither Texture     3
	var dither_width_3 : float = _dither_tex_3.get_width();
	var dither_height_3 : float = _dither_tex_3.get_height();
	
	var dither_tex_size_3 : Vector2  = Vector2(dither_width_3, dither_height_3);
	
	#   Projection
	var inv_proj_mat : Projection = render_scene_data.get_cam_projection().inverse()
	
	# Pack push constants : [raster_size.x, raster_size.y, polarity, edge_fade]
	var push_constants := PackedFloat32Array([
		size.x,
		size.y,
		
		dither_tex_size_1.x,
		dither_tex_size_1.y,
		
		dither_tex_size_2.x,
		dither_tex_size_2.y,
		
		dither_tex_size_3.x,
		dither_tex_size_3.y,
		
		float(levels),
		inv_proj_mat[2].w, 
		inv_proj_mat[3].w
		])
	push_constants.append_array([0.0])
	
	var push_data : PackedByteArray = push_constants.to_byte_array()
	
	# Loop over each view (monoscopic = 1 view)
	var view_count : int = render_scene_buffers.get_view_count()
	for view in range(view_count):
		var screen_tex : RID = render_scene_buffers.get_color_layer(view)
		var depth_tex : RID = render_scene_buffers.get_depth_layer(view)
		if !screen_tex or !depth_tex: continue
		
		# Image Uniform
		var image_uniform := RDUniform.new()
		image_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_IMAGE
		image_uniform.binding = 0
		image_uniform.add_id(screen_tex)
		
		# Image Sampler
		var sampler_uniform := RDUniform.new()
		sampler_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		sampler_uniform.binding = 1
		sampler_uniform.add_id(linear_sampler)
		sampler_uniform.add_id(screen_tex)
		
		var uniform_set : RID = UniformSetCacheRD.get_cache(shader, 0, [image_uniform, sampler_uniform])
		
		# Dither Sampler    --> 1
		var dither_sampler_uniform_1 := RDUniform.new()
		dither_sampler_uniform_1.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		dither_sampler_uniform_1.binding = 0
		dither_sampler_uniform_1.add_id(dither_nearest_sampler)
		dither_sampler_uniform_1.add_id(dither_tex_rid_1)
		
		# Dither Sampler    --> 2
		var dither_sampler_uniform_2 := RDUniform.new()
		dither_sampler_uniform_2.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		dither_sampler_uniform_2.binding = 1
		dither_sampler_uniform_2.add_id(dither_nearest_sampler)
		dither_sampler_uniform_2.add_id(dither_tex_rid_2)
		
		# Dither Sampler    --> 3
		var dither_sampler_uniform_3 := RDUniform.new()
		dither_sampler_uniform_3.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		dither_sampler_uniform_3.binding = 2
		dither_sampler_uniform_3.add_id(dither_nearest_sampler)
		dither_sampler_uniform_3.add_id(dither_tex_rid_3)
		
		#var dither_uniform_set: RID = rd.uniform_set_create([dither_sampler_uniform_2], shader, 1)
		var dither_uniform_set: RID = rd.uniform_set_create([dither_sampler_uniform_1, dither_sampler_uniform_2, dither_sampler_uniform_3], shader, 1)
		
		# Depth Uniform
		var depth_sampler_uniform := RDUniform.new()
		depth_sampler_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		depth_sampler_uniform.binding = 0
		depth_sampler_uniform.add_id(linear_sampler)
		depth_sampler_uniform.add_id(depth_tex)
		
		var depth_uniform_set : RID = UniformSetCacheRD.get_cache(shader, 2, [depth_sampler_uniform])
		
		# Record and submit compute commands
		var compute_list : int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		rd.compute_list_bind_uniform_set(compute_list, dither_uniform_set, 1)
		rd.compute_list_bind_uniform_set(compute_list, depth_uniform_set, 2)
		rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()
