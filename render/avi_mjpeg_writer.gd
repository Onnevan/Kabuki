class_name AviMjpegWriter
extends RefCounted

var _file: FileAccess
var _width := 0
var _height := 0
var _fps := 24
var _quality := 0.9
var _frame_offsets: Array[int] = []
var _frame_sizes: Array[int] = []
var _max_frame_size := 0
var _riff_size_pos := 0
var _avih_max_bytes_pos := 0
var _avih_total_frames_pos := 0
var _avih_suggested_buffer_pos := 0
var _strh_length_pos := 0
var _strh_suggested_buffer_pos := 0
var _movi_size_pos := 0
var _movi_data_start := 0
var _started := false

func _fourcc(value: String) -> void:
	_file.store_buffer(value.to_ascii_buffer())

func _patch_u32(position: int, value: int) -> void:
	var restore := _file.get_position()
	_file.seek(position)
	_file.store_32(value)
	_file.seek(restore)

func _begin_list(list_type: String) -> int:
	_fourcc("LIST")
	var size_pos := _file.get_position()
	_file.store_32(0)
	_fourcc(list_type)
	return size_pos

func _end_list(size_pos: int) -> void:
	var end_pos := _file.get_position()
	_patch_u32(size_pos,end_pos-(size_pos+4))

func begin(path: String, width: int, height: int, fps: int, quality: float = 0.9) -> Error:
	if _started:
		return ERR_ALREADY_IN_USE
	_width = maxi(1,width)
	_height = maxi(1,height)
	_fps = maxi(1,fps)
	_quality = clampf(quality,0.05,1.0)
	_frame_offsets.clear()
	_frame_sizes.clear()
	_max_frame_size = 0

	_file = FileAccess.open(path,FileAccess.WRITE)
	if _file == null:
		return ERR_CANT_CREATE

	_fourcc("RIFF")
	_riff_size_pos = _file.get_position()
	_file.store_32(0)
	_fourcc("AVI ")

	var hdrl_size_pos := _begin_list("hdrl")

	# Main AVI header (AVIMAINHEADER), 56 bytes.
	_fourcc("avih")
	_file.store_32(56)
	_file.store_32(roundi(1000000.0/float(_fps)))
	_avih_max_bytes_pos = _file.get_position()
	_file.store_32(0)
	_file.store_32(0)
	_file.store_32(0x10) # AVIF_HASINDEX.
	_avih_total_frames_pos = _file.get_position()
	_file.store_32(0)
	_file.store_32(0)
	_file.store_32(1)
	_avih_suggested_buffer_pos = _file.get_position()
	_file.store_32(0)
	_file.store_32(_width)
	_file.store_32(_height)
	for _i in range(4):
		_file.store_32(0)

	var strl_size_pos := _begin_list("strl")

	# Video stream header (AVISTREAMHEADER), 56 bytes.
	_fourcc("strh")
	_file.store_32(56)
	_fourcc("vids")
	_fourcc("MJPG")
	_file.store_32(0)
	_file.store_16(0)
	_file.store_16(0)
	_file.store_32(0)
	_file.store_32(1)
	_file.store_32(_fps)
	_file.store_32(0)
	_strh_length_pos = _file.get_position()
	_file.store_32(0)
	_strh_suggested_buffer_pos = _file.get_position()
	_file.store_32(0)
	_file.store_32(0xFFFFFFFF)
	_file.store_32(0)
	_file.store_16(0)
	_file.store_16(0)
	_file.store_16(_width)
	_file.store_16(_height)

	# BITMAPINFOHEADER for MJPEG.
	_fourcc("strf")
	_file.store_32(40)
	_file.store_32(40)
	_file.store_32(_width)
	_file.store_32(_height)
	_file.store_16(1)
	_file.store_16(24)
	_fourcc("MJPG")
	_file.store_32(_width*_height*3)
	_file.store_32(0)
	_file.store_32(0)
	_file.store_32(0)
	_file.store_32(0)

	_end_list(strl_size_pos)
	_end_list(hdrl_size_pos)

	_movi_size_pos = _begin_list("movi")
	_movi_data_start = _file.get_position()
	_started = true
	return OK

func append_frame(source: Image) -> Error:
	if not _started or _file == null:
		return ERR_UNCONFIGURED
	if source == null or source.is_empty():
		return ERR_INVALID_DATA
	var frame := source
	if frame.get_width() != _width or frame.get_height() != _height:
		frame = source.duplicate()
		frame.resize(_width,_height,Image.INTERPOLATE_LANCZOS)
	var jpg: PackedByteArray = frame.save_jpg_to_buffer(_quality)
	if jpg.is_empty():
		return ERR_CANT_CREATE

	# Classic AVI 1.0 uses 32-bit RIFF sizes. Keep a little headroom for idx1.
	if _file.get_position()+jpg.size()+8+(_frame_offsets.size()+1)*16 >= 0xFFFFFF00:
		return ERR_OUT_OF_MEMORY

	var chunk_start := _file.get_position()
	_fourcc("00dc")
	_file.store_32(jpg.size())
	_file.store_buffer(jpg)
	if (jpg.size() & 1) != 0:
		_file.store_8(0)

	# idx1 offsets are relative to the start of the movi LIST. The common
	# AVI 1.0 convention makes the first media chunk offset 4.
	_frame_offsets.append(chunk_start-_movi_data_start+4)
	_frame_sizes.append(jpg.size())
	_max_frame_size = maxi(_max_frame_size,jpg.size())
	return OK

func frame_count() -> int:
	return _frame_offsets.size()

func finish() -> Error:
	if not _started or _file == null:
		return ERR_UNCONFIGURED

	# Close LIST movi before writing the legacy AVI index.
	var movi_end := _file.get_position()
	_patch_u32(_movi_size_pos,movi_end-(_movi_size_pos+4))

	_fourcc("idx1")
	_file.store_32(_frame_offsets.size()*16)
	for i in range(_frame_offsets.size()):
		_fourcc("00dc")
		_file.store_32(0x10) # AVIIF_KEYFRAME; every MJPEG frame is independent.
		_file.store_32(_frame_offsets[i])
		_file.store_32(_frame_sizes[i])

	var final_size := _file.get_position()
	var frames := _frame_offsets.size()
	_patch_u32(_avih_max_bytes_pos,_max_frame_size*_fps)
	_patch_u32(_avih_total_frames_pos,frames)
	_patch_u32(_avih_suggested_buffer_pos,_max_frame_size)
	_patch_u32(_strh_length_pos,frames)
	_patch_u32(_strh_suggested_buffer_pos,_max_frame_size)
	_patch_u32(_riff_size_pos,final_size-8)

	_file.flush()
	_file.close()
	_file = null
	_started = false
	return OK
