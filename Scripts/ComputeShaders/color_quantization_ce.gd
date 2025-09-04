@tool
class_name ColorQuantizationCe extends CompositorEffect

@export var lut_table : Image :
	#set(value):
		#if lut_table == null:
			##lut_table = preload("res://LUT/16-8bit.png")
			#lut_table = preload("res://LUT/lut_8x8_neutral.png")
		#change_lut(value)
	set(value):
		#if value == null:
			#value = preload("res://LUT/lut_8x8_neutral.png")
		#change_lut(value)
		if value != null:
			_lut_table = value
			change_lut(_lut_table)

var _lut_table : Image
const GLSL_FILE : RDShaderFile = preload("res://Scripts/GLSL/color_quantization.glsl")

var rd : RenderingDevice
var shader : RID
var pipeline : RID
var nearest_sampler : RID

var lut_linear_sampler : RID
var lut_tex : RID

func change_lut(new_lut : Image):
	print("i'm changing lut..")
	new_lut.convert(Image.FORMAT_RGBAF)
	
	var lut_fmt = RDTextureFormat.new()
	lut_fmt.width = new_lut.get_width()
	lut_fmt.height = new_lut.get_height()
	lut_fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
	lut_fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
	
	var lut_sampler_state : RDSamplerState = RDSamplerState.new()
	lut_sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	lut_sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
	lut_sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	lut_sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
	
	lut_linear_sampler = rd.sampler_create(lut_sampler_state)
	
	var lut_tex_view = RDTextureView.new()
	
	lut_tex = rd.texture_create(lut_fmt, lut_tex_view, [new_lut.get_data()])

func _notification(what : int):
	if what == NOTIFICATION_PREDELETE:
		if shader : RenderingServer.free_rid(shader)
		if pipeline : RenderingServer.free_rid(pipeline)
		if nearest_sampler : RenderingServer.free_rid(nearest_sampler)
		if lut_linear_sampler : RenderingServer.free_rid(lut_linear_sampler)
		if lut_tex : RenderingServer.free_rid(lut_tex)

func _init():
	effect_callback_type = EFFECT_CALLBACK_TYPE_POST_TRANSPARENT
	RenderingServer.call_on_render_thread(_init_compute)

func _init_compute():
	rd = RenderingServer.get_rendering_device()
	if !rd : return
	
	if _lut_table == null:
		#lut_table = preload("res://LUT/16-8bit.png")
		_lut_table = preload("res://LUT/lut_8x8_neutral.png")
		change_lut(_lut_table)
	
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
	
	var lut_width : float = _lut_table.get_width();
	var lut_height : float = _lut_table.get_height();
	
	var lut_tex_size : Vector2  = Vector2(lut_width, lut_height);
	
	# Pack push constants : [raster_size.x, raster_size.y, polarity, edge_fade]
	var push_constants := PackedFloat32Array([
		size.x,
		size.y,
		lut_tex_size.x,
		lut_tex_size.y
		])
	
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
		
		var lut_sampler_uniform := RDUniform.new()
		lut_sampler_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		lut_sampler_uniform.binding = 0
		lut_sampler_uniform.add_id(lut_linear_sampler)
		lut_sampler_uniform.add_id(lut_tex)
		
		#var g_uniform_set: RID = rd.uniform_set_create([lut_sampler_uniform], shader, 1)
		## TEST 4 END /////////////////////////////////////////////////////////////////
		
		#var lut_uniform_set: RID = UniformSetCacheRD.get_cache(shader, 1, [lut_sampler_uniform])
		var lut_uniform_set: RID = rd.uniform_set_create([lut_sampler_uniform], shader, 1)
		#if lut_uniform_set : print("l_uniform_set")
		# Record and submit compute commands
		var compute_list : int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		rd.compute_list_bind_uniform_set(compute_list, lut_uniform_set, 1)
		rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()
