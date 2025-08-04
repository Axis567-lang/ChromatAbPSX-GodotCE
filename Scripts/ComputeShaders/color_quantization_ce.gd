@tool
class_name ColorQuantizationCe extends CompositorEffect

@export var lut_table : Image

const GLSL_FILE : RDShaderFile = preload("res://Scripts/GLSL/color_quantization.glsl")

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
		])
	push_constants.append_array([0.0,0.0])
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
		#prints("lut_table: ", lut_table)
		if lut_table == null:
			lut_table = preload("res://LUT/16-8bit.png")
		
		## TEST 4 /////////////////////////////////////////////////////////////////////		
		#var g_img : Image = gradient.get_image()
		lut_table.convert(Image.FORMAT_RGBAF)
		#print("Image: ", lut_table)
		
		var lut_fmt = RDTextureFormat.new()
		lut_fmt.width = lut_table.get_width()
		lut_fmt.height = lut_table.get_height()
		lut_fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
		lut_fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		
		var lut_sampler_state : RDSamplerState = RDSamplerState.new()
		lut_sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		lut_sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		lut_sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
		lut_sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
		#print("Sampler: ", lut_sampler_state)
		
		var lut_linear_sampler : RID = rd.sampler_create(lut_sampler_state)
		#print("Linear Sampler: ", lut_linear_sampler)
		
		var lut_tex_view = RDTextureView.new()
		
		var lut_tex = rd.texture_create(lut_fmt, lut_tex_view, [lut_table.get_data()])
		var lut_sampler_uniform := RDUniform.new()
		lut_sampler_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		lut_sampler_uniform.binding = 0
		lut_sampler_uniform.add_id(lut_linear_sampler)
		lut_sampler_uniform.add_id(lut_tex)
		
		#var g_uniform_set: RID = rd.uniform_set_create([lut_sampler_uniform], shader, 1)
		## TEST 4 END /////////////////////////////////////////////////////////////////
		
		## TEST 3 /////////////////////////////////////////////////////////////////////
		#	---------------------------------------------------------------------------
		#func create_texture3d_from_images(rd: RenderingDevice, images: Array, width: int, height: int, depth: int) -> RID:
		#
		## Crear formato
		#var tex_fmt = RDTextureFormat.new()
		#tex_fmt.width = width
		#tex_fmt.height = height
		#tex_fmt.depth = depth
		#tex_fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
		#tex_fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		#
		## Preparar el buffer concatenando todas las slices en orden Z
		#var total_bytes_per_slice = width * height * 4 * 4 # 4 canales (RGBA) * 4 bytes (float32)
		#var total_bytes = total_bytes_per_slice * depth
		#
		## Crear PackedByteArray con tamaño total
		#var all_data = PackedByteArray()
		#all_data.resize(total_bytes)
		#
		#for z in range(depth):
			#var slice_img : Image = images[z]
			#slice_img.lock() # Asegurar acceso
			#
			#var slice_data : PackedByteArray = slice_img.get_data() # bytes de la imagen
			## Copiar los bytes de slice_data en all_data en offset adecuado
			#for i in range(total_bytes_per_slice):
				#all_data[z * total_bytes_per_slice + i] = slice_data[i]
			#
			#slice_img.unlock()
		#
		## Crear vista de textura 3D
		#var tex_view = RDTextureView.new()
		#
		## Crear textura 3D con los datos concatenados
		#var tex3d_rid = rd.texture_create(tex_fmt, tex_view, [all_data])
		#
		#return tex3d_rid
		
		#var sampler_state = RDSamplerState.new()
		#sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		#sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		#sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
		#sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
		#sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT # importante para 3D
		
		#var sampler_rid = rd.sampler_create(sampler_state)
		
		#var sampler_uniform = RDUniform.new()
		#sampler_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		#sampler_uniform.binding = 0
		#sampler_uniform.add_id(sampler_rid)
		#sampler_uniform.add_id(tex3d_rid)

		#var uniform_set = rd.uniform_set_create([sampler_uniform], shader, 3)
		#	---------------------------------------------------------------------------
		
		#var width : int = lut_table.get_width()
		#var height : int = lut_table.get_height()
		#var depth : int = lut_table.get_depth()
		#
		#var images : Array[Image] = lut_table.get_data()
		#
		## Preparar el buffer concatenando todas las slices en orden Z
		#var total_bytes_per_slice = width * height * 4 * 4 # 4 canales (RGBA) * 4 bytes (float32)
		#prints("Bytes per Slice: ", total_bytes_per_slice)
		#var total_bytes = total_bytes_per_slice * depth
		#prints("Total Bytes: ", total_bytes)
		#
		## Crear PackedByteArray con tamaño total
		#var all_data = PackedByteArray()
		#all_data.resize(total_bytes)
		#
		#for z in range(depth):
			#var slice_img : Image = images[z]
			#if slice_img.get_format() != 11:
				#slice_img.convert(Image.FORMAT_RGBAF)
			#prints("Slice Format: ", slice_img.get_format())
			#
			#var slice_data : PackedByteArray = slice_img.get_data() # bytes de la imagen
			#print("Slice Data Size:", slice_data.size())
			#
			## Copiar los bytes de slice_data en all_data en offset adecuado
			#for i in range(total_bytes_per_slice):
				#all_data[z * total_bytes_per_slice + i] = slice_data[i]
		
		#var g_img : Image = gradient.get_image()
		#g_img.convert(Image.FORMAT_RGBAF)
		#print("Image: ", g_img)
		
		### Formato de la Textura
		#var l_fmt = RDTextureFormat.new()
		#l_fmt.width = width
		#l_fmt.height = height
		#l_fmt.depth = depth
		#l_fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
		#l_fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT
		#
		### Sampler
		#var l_sampler_state : RDSamplerState = RDSamplerState.new()
		#l_sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		#l_sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		#l_sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
		#l_sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
		#l_sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_REPEAT
		#print("Sampler: ", l_sampler_state)
		#
		#var l_sampler_rid : RID = rd.sampler_create(l_sampler_state)
		#print("Linear Sampler: ", l_sampler_rid)
		#
		#var l_tex_view := RDTextureView.new()
		#
		#var l_tex : RID = rd.texture_create(l_fmt, l_tex_view, [all_data])
		#print("Texture Created: ", l_tex)
		#
		#var l_sampler_uniform := RDUniform.new()
		#l_sampler_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		#l_sampler_uniform.binding = 0
		#l_sampler_uniform.add_id(l_sampler_rid)
		#l_sampler_uniform.add_id(l_tex)
		
		#var l_uniform_set: RID = rd.uniform_set_create([l_sampler_uniform], shader, 3)
		
		## TEST 3 END /////////////////////////////////////////////////////////////////
		
		## TEST 2 ////////////////////////////////////////////////////////////////////
		#var l_img : Image = lut_table.get_image()
		#l_img.convert(Image.FORMAT_RGBAF)
		#
		## Texture Format 
		#var l_fmt = RDTextureFormat.new()
		#l_fmt.width = l_img.get_width()
		#l_fmt.height = l_img.get_height()
		#l_fmt.format = RenderingDevice.DATA_FORMAT_R32G32B32A32_SFLOAT
		#l_fmt.usage_bits = RenderingDevice.TEXTURE_USAGE_CAN_COPY_FROM_BIT | RenderingDevice.TEXTURE_USAGE_SAMPLING_BIT | RenderingDevice.TEXTURE_USAGE_CAN_UPDATE_BIT
		#
		##	Sampler -------------------------------
		#var l_sampler_state : RDSamplerState = RDSamplerState.new()
		#l_sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		#l_sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		#l_sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		#l_sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		#l_sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		##print("Sampler: ", g_sampler_state)
		#var l_linear_sampler : RID = rd.sampler_create(l_sampler_state)
		##print("Linear Sampler: ", g_linear_sampler)
		#
		#var l_tex_view = RDTextureView.new()
		#
		#var l_tex = rd.texture_create(l_fmt, l_tex_view, [l_img.get_data()])
		## -----------------------------------------
		#
		### Uniform ----------------------------------
		#var l_sampler_uniform := RDUniform.new()
		#l_sampler_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		#l_sampler_uniform.binding = 0
		#l_sampler_uniform.add_id(l_linear_sampler)
		#l_sampler_uniform.add_id(l_tex)
		## TEST 2 END ////////////////////////////////////////////////////////////////
		
		
		## TEST 1 ///////////////////////////////////////////////////////////////////
		#var lut_rid : RID = lut_table.get_rid()
		#if lut_rid : prints("lut rid: ", lut_rid)
		
		#var l_sampler_state := RDSamplerState.new()
		#l_sampler_state.min_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		#l_sampler_state.mag_filter = RenderingDevice.SAMPLER_FILTER_NEAREST
		#l_sampler_state.repeat_u = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		#l_sampler_state.repeat_v = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		#l_sampler_state.repeat_w = RenderingDevice.SAMPLER_REPEAT_MODE_CLAMP_TO_EDGE
		#var l_sampler_rid : RID = rd.sampler_create(l_sampler_state)
		#if l_sampler_rid : print("l_sampler_rid")
		
		# Crea el uniform que combina el sampler y la texture3D
		#var lut_uniform := RDUniform.new()
		#lut_uniform.uniform_type = RenderingDevice.UNIFORM_TYPE_SAMPLER_WITH_TEXTURE
		#lut_uniform.binding = 0 # binding debe coincidir con el shader
		#lut_uniform.add_id(l_sampler_rid)
		#lut_uniform.add_id(lut_rid)
		
		#if lut_uniform : print("lut uniform")
		## TEST 1 END ////////////////////////////////////////////////////////////////
		
		var lut_uniform_set: RID = UniformSetCacheRD.get_cache(shader, 1, [lut_sampler_uniform])
		#if lut_uniform_set : print("l_uniform_set")
		# Record and submit compute commands
		var compute_list : int = rd.compute_list_begin()
		rd.compute_list_bind_compute_pipeline(compute_list, pipeline)
		rd.compute_list_bind_uniform_set(compute_list, uniform_set, 0)
		rd.compute_list_bind_uniform_set(compute_list, lut_uniform_set, 1)
		rd.compute_list_set_push_constant(compute_list, push_data, push_data.size())
		rd.compute_list_dispatch(compute_list, x_groups, y_groups, 1)
		rd.compute_list_end()
