@tool
class_name HalftoneDitherCe extends CompositorEffect

@export var dith_tex : Image :
	set(value):
		if value != null:
			_dither_tex = value
			change_dither(_dither_tex)

# Cell Size in Pixels
@export_range(2, 10, 1) var cell_size : int = 5
@export_range(1, 100, 1) var dot_scale : int = 21

var _dither_tex : Image
const GLSL_FILE : RDShaderFile = preload("res://Scripts/GLSL/halftone_dither.glsl")

var rd : RenderingDevice
var shader : RID
var pipeline : RID
var nearest_sampler : RID

var dither_linear_sampler : RID
var dither_tex_rid : RID

func change_dither(new_dither_tex : Image):
	print("i'm changing dither..")
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
	
	dither_linear_sampler = rd.sampler_create(dither_sampler_state)
	
	var dither_tex_view = RDTextureView.new()
	
	dither_tex_rid = rd.texture_create(dither_fmt, dither_tex_view, [new_dither_tex.get_data()])

func _notification(what : int):
	if what == NOTIFICATION_PREDELETE:
		if shader : RenderingServer.free_rid(shader)
		if pipeline : RenderingServer.free_rid(pipeline)
		if nearest_sampler : RenderingServer.free_rid(nearest_sampler)
		if dither_linear_sampler : RenderingServer.free_rid(dither_linear_sampler)
		if dither_tex_rid : RenderingServer.free_rid(dither_tex_rid)

func _init():
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	RenderingServer.call_on_render_thread(_init_compute)

func _init_compute():
	rd = RenderingServer.get_rendering_device()
	if !rd : return
	
	if _dither_tex == null:
		#dith_tex = preload("res://LUT/16-8bit.png")
		_dither_tex = preload("res://DitherTextures/Bayer/bayer4.png")
		change_dither(_dither_tex)
	
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
	
	# LUT
	#   ////////////////////////////////////////////////////////////////////////////////////////////
	
	var dither_width : float = _dither_tex.get_width();
	var dither_height : float = _dither_tex.get_height();
	
	var dither_tex_size : Vector2  = Vector2(dither_width, dither_height);
	
	# Pack push constants : [raster_size.x, raster_size.y, polarity, edge_fade]
	var push_constants := PackedFloat32Array([
		size.x,
		size.y,
		dither_tex_size.x,
		dither_tex_size.y,
		float(cell_size),
		float(dot_scale)
		])
	push_constants.append_array([0.0, 0.0]) # -> siempre tamaño final múltiplo de 16
	
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
		
		# LUT Table
		## TEST 4 /////////////////////////////////////////////////////////////////////		
		
		var dither_sampler_uniform := RDUniform.new()
		dither_sampler_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		dither_sampler_uniform.binding = 0
		dither_sampler_uniform.add_id(dither_linear_sampler)
		dither_sampler_uniform.add_id(dither_tex_rid)
		
		#var g_uniform_set: RID = rd.uniform_set_create([dither_sampler_uniform], shader, 1)
		## TEST 4 END /////////////////////////////////////////////////////////////////
		
		#var dither_uniform_set: RID = UniformSetCacheRD.get_cache(shader, 1, [dither_sampler_uniform])
		var dither_uniform_set: RID = rd.uniform_set_create([dither_sampler_uniform], shader, 1)
		#if dither_uniform_set : print("l_uniform_set")
		# Record and submit compute commands
		var compute_list : int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		rd.compute_list_bind_uniform_set(compute_list, dither_uniform_set, 1)
		rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()
