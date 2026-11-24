extends Node
## Audio manager (autoload "Sfx").
##
## * Every sound is audio/<name>.wav - overwrite a file with your own recording to replace it.
## * Spoken lines ("Watch out!", "You can do it!") use audio/voice/<key>_1.wav (Ember) and
##   audio/voice/<key>_2.wav (Frost) if those files exist; otherwise the computer's own
##   text-to-speech voice says them.

const NAMES := [
	"ka_ching", "jump_p1", "jump_p2", "sigh_p1", "sigh_p2", "pant", "land", "hurt",
	"checkpoint", "clear", "win", "shield", "timeup", "ui_move", "ui_click", "pause",
	"count", "go", "alien_roar",
]
const VOICE_TEXT := {"watch_out": "Watch out!", "you_can_do_it": "You can do it!"}

var music_on := false      # off by default: turn it on from the menu if you like it
var sfx_on := true
var voice_on := false      # spoken lines are off by default (menu toggle)

var _streams := {}
var _pool: Array[AudioStreamPlayer] = []
var _music: AudioStreamPlayer
var _voice_player: AudioStreamPlayer


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for n in NAMES:
		var path := "res://audio/%s.wav" % n
		if ResourceLoader.exists(path):
			_streams[n] = load(path)
	for i in 10:
		var p := AudioStreamPlayer.new()
		add_child(p)
		_pool.append(p)
	_voice_player = AudioStreamPlayer.new()
	add_child(_voice_player)
	_music = AudioStreamPlayer.new()
	add_child(_music)
	_music.volume_db = -6.0
	if ResourceLoader.exists("res://audio/music_loop.wav"):
		_music.stream = load("res://audio/music_loop.wav")
		_music.finished.connect(func() -> void:
			if music_on:
				_music.play())


func play(sound: String, vol_db: float = 0.0, pitch: float = 1.0) -> void:
	if not sfx_on or not _streams.has(sound):
		return
	var chosen: AudioStreamPlayer = _pool[0]
	for p in _pool:
		if not p.playing:
			chosen = p
			break
	chosen.stream = _streams[sound]
	chosen.volume_db = vol_db
	chosen.pitch_scale = pitch
	chosen.play()


## Spoken line for hero `pid` (0 or 1). key is "watch_out" or "you_can_do_it".
func voice(pid: int, key: String) -> void:
	if not voice_on:
		return
	var custom := "res://audio/voice/%s_%d.wav" % [key, pid + 1]
	if ResourceLoader.exists(custom):
		_voice_player.stream = load(custom)
		_voice_player.volume_db = -4.0
		_voice_player.play()
		return
	if DisplayServer.has_feature(DisplayServer.FEATURE_TEXT_TO_SPEECH):
		var voices: PackedStringArray = DisplayServer.tts_get_voices_for_language("en")
		var vid := ""
		if voices.size() > 0:
			vid = voices[pid % voices.size()]
		if vid != "":
			DisplayServer.tts_speak(String(VOICE_TEXT.get(key, "")), vid, 75,
				1.55 if pid == 0 else 1.25, 1.05, 0, true)


func start_music() -> void:
	if music_on and _music.stream != null and not _music.playing:
		_music.play()


func set_music(on: bool) -> void:
	music_on = on
	if on:
		start_music()
	else:
		_music.stop()


func duck(on: bool) -> void:
	_music.volume_db = -14.0 if on else -6.0
