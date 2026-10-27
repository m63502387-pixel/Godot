extends Node
# Процедурный звук ветра (без аудиофайлов). Громкость задаёт main через level (0..1).

const RATE := 22050.0

var level := 0.1
var phase := 0.0
var lp := 0.0
var lp2 := 0.0
var audio: AudioStreamPlayer
var playback: AudioStreamGeneratorPlayback


func _ready() -> void:
	var gen := AudioStreamGenerator.new()
	gen.mix_rate = RATE
	gen.buffer_length = 0.3
	audio = AudioStreamPlayer.new()
	audio.stream = gen
	audio.volume_db = -4.0
	add_child(audio)
	audio.play()
	playback = audio.get_stream_playback() as AudioStreamGeneratorPlayback


func _process(_delta: float) -> void:
	if playback == null:
		return
	var frames: int = playback.get_frames_available()
	for i in range(frames):
		phase += 1.0 / RATE
		var white: float = randf() * 2.0 - 1.0
		lp += (white - lp) * (0.02 + 0.05 * level)
		lp2 += (lp - lp2) * 0.2
		var gust: float = 0.6 + 0.4 * sin(phase * 0.7) * sin(phase * 0.31 + 1.0)
		var s: float = clampf(lp2 * gust * level * 6.0, -0.9, 0.9)
		playback.push_frame(Vector2(s, s))
