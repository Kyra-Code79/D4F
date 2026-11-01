extends Node
## Autoload Singleton: AudioManager
## Provides lightweight procedural SFX synthesis via AudioStreamWAV so all UI,
## workshop, countdown, checkpoint, collision, and victory sounds work with zero binary bloat.

const MIX_RATE := 22050
var _sfx_players: Array[AudioStreamPlayer] = []
const MAX_CONCURRENT_SFX := 6

func _ready() -> void:
	for i in range(MAX_CONCURRENT_SFX):
		var p := AudioStreamPlayer.new()
		p.bus = "Master"
		add_child(p)
		_sfx_players.append(p)

func play_sfx(sfx_name: String, pitch_scale: float = 1.0) -> void:
	if DisplayServer.get_name() == "headless":
		return
	var sfx_vol := 0.9
	if has_node("/root/SettingsManager"):
		sfx_vol = float(get_node("/root/SettingsManager").get_setting("audio", "sfx_volume", 0.9))
	if sfx_vol <= 0.001:
		return

	var stream: AudioStreamWAV = _build_tone_stream(sfx_name)
	if stream == null:
		return

	for p in _sfx_players:
		if not p.playing:
			p.stream = stream
			p.pitch_scale = clampf(pitch_scale, 0.5, 2.0)
			p.volume_db = linear_to_db(clampf(sfx_vol * 0.45, 0.001, 1.0))
			p.play()
			return

func _build_tone_stream(sfx_name: String) -> AudioStreamWAV:
	var freq_start := 440.0
	var freq_end := 440.0
	var duration := 0.08
	match sfx_name:
		"ui_click":
			freq_start = 580.0
			freq_end = 740.0
			duration = 0.05
		"brush_stroke":
			freq_start = 320.0
			freq_end = 390.0
			duration = 0.04
		"countdown_tick":
			freq_start = 523.25
			freq_end = 523.25
			duration = 0.11
		"countdown_go":
			freq_start = 783.99
			freq_end = 1046.50
			duration = 0.25
		"checkpoint":
			freq_start = 659.25
			freq_end = 987.77
			duration = 0.16
		"collision":
			freq_start = 180.0
			freq_end = 90.0
			duration = 0.12
		"elimination":
			freq_start = 420.0
			freq_end = 140.0
			duration = 0.28
		"victory":
			freq_start = 523.25
			freq_end = 1046.50
			duration = 0.35
		_:
			freq_start = 440.0
			freq_end = 480.0
			duration = 0.06

	var sample_count := int(MIX_RATE * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2) # 16-bit PCM mono
	var phase := 0.0
	for i in range(sample_count):
		var t := float(i) / float(max(sample_count - 1, 1))
		var freq := lerpf(freq_start, freq_end, t)
		var env := sin(t * PI) # smooth attack & release envelope
		phase += TAU * freq / float(MIX_RATE)
		var sample_val := sin(phase) * env * 0.65
		var pcm16 := clampi(int(sample_val * 32767.0), -32768, 32767)
		data.encode_s16(i * 2, pcm16)

	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = MIX_RATE
	wav.stereo = false
	wav.data = data
	return wav
