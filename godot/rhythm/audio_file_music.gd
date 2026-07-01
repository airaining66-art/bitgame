class_name AudioFileMusic
extends Node
## Plays a chart-selected audio file and follows the Conductor lifecycle.

var stream_path := ""
var fade_in_seconds := 0.0
var fade_out_seconds := 2.0
var finale := false

var player: AudioStreamPlayer
var conductor_ref: Conductor
var started := false
var outro_started := false
var outro_start_time := 0.0


func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.bus = "Master"
	player.volume_db = -80.0 if fade_in_seconds > 0.0 else 0.0
	add_child(player)
	player.stream = _load_stream(stream_path)


func setup(conductor: Conductor) -> void:
	conductor_ref = conductor


func reset() -> void:
	started = false
	outro_started = false
	outro_start_time = 0.0
	if player:
		player.stop()
		player.volume_db = -80.0 if fade_in_seconds > 0.0 else 0.0
	finale = false


func play_outro() -> void:
	outro_started = true
	outro_start_time = Time.get_ticks_msec() / 1000.0


func _process(_delta: float) -> void:
	if conductor_ref == null:
		return
	if conductor_ref.running and not started:
		_play()
	elif not conductor_ref.running and started and not outro_started:
		reset()
	if not started or player == null:
		return
	player.stream_paused = conductor_ref.paused
	if conductor_ref.paused:
		return
	var volume := 1.0
	var seconds := conductor_ref.time_ms() / 1000.0
	var total := conductor_ref.duration_ms() / 1000.0
	if fade_in_seconds > 0.0:
		volume = minf(volume, seconds / fade_in_seconds)
	if fade_out_seconds > 0.0 and not outro_started:
		volume = minf(volume, maxf((total - seconds) / fade_out_seconds, 0.0))
	if outro_started and fade_out_seconds > 0.0:
		var elapsed := (Time.get_ticks_msec() / 1000.0) - outro_start_time
		volume = maxf(1.0 - elapsed / fade_out_seconds, 0.0)
	player.volume_db = linear_to_db(clampf(volume, 0.0001, 1.0))


func _play() -> void:
	if player == null or player.stream == null:
		return
	started = true
	var from_seconds := 0.0
	if conductor_ref:
		from_seconds = maxf(conductor_ref.time_ms() / 1000.0, 0.0)
	player.play(from_seconds)


func _load_stream(path: String) -> AudioStream:
	if path == "":
		return null
	if ResourceLoader.exists(path):
		var res := load(path)
		if res is AudioStream:
			return res
	if FileAccess.file_exists(path):
		var lower := path.to_lower()
		if lower.ends_with(".mp3"):
			return AudioStreamMP3.load_from_file(path)
		if lower.ends_with(".ogg"):
			return AudioStreamOggVorbis.load_from_file(path)
		if lower.ends_with(".wav"):
			return AudioStreamWAV.load_from_file(path)
	return null
