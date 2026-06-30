class_name NeonPulseMusic
extends Node
## Runtime edit of assets/Neon Pulse.mp3 for chart preview and level play.

const MUSIC_PATH := "res://assets/Neon Pulse.mp3"
const CLIP_SECONDS := 90.0
const FADE_IN_SECONDS := 2.5
const FADE_OUT_SECONDS := 4.0

var player: AudioStreamPlayer
var conductor_ref: Conductor
var started := false
var elapsed := 0.0
var clip_done := false
var finale := false


func _ready() -> void:
	player = AudioStreamPlayer.new()
	player.bus = "Master"
	player.volume_db = -80.0
	add_child(player)
	player.stream = _load_stream()


func setup(conductor: Conductor) -> void:
	conductor_ref = conductor


func reset() -> void:
	_stop()
	clip_done = false
	finale = false


func _process(delta: float) -> void:
	if conductor_ref:
		if conductor_ref.running and not started and not clip_done:
			_play()
		elif not conductor_ref.running and started:
			_stop()
		if player:
			player.stream_paused = conductor_ref.paused
	if conductor_ref and conductor_ref.paused:
		return
	if not started:
		return
	elapsed += delta
	if elapsed >= CLIP_SECONDS:
		clip_done = true
		_stop()
		return
	var fade := 1.0
	if FADE_IN_SECONDS > 0.0:
		fade = minf(fade, elapsed / FADE_IN_SECONDS)
	if FADE_OUT_SECONDS > 0.0:
		fade = minf(fade, maxf((CLIP_SECONDS - elapsed) / FADE_OUT_SECONDS, 0.0))
	player.volume_db = linear_to_db(clampf(fade, 0.0001, 1.0))


func _play() -> void:
	if player == null or player.stream == null:
		return
	elapsed = 0.0
	started = true
	player.volume_db = -80.0
	player.play(0.0)


func _stop() -> void:
	started = false
	elapsed = 0.0
	if player:
		player.stop()
		player.volume_db = -80.0


func _load_stream() -> AudioStream:
	if ResourceLoader.exists(MUSIC_PATH):
		var res := load(MUSIC_PATH)
		if res is AudioStream:
			return res
	if FileAccess.file_exists(MUSIC_PATH):
		return AudioStreamMP3.load_from_file(MUSIC_PATH)
	return null
