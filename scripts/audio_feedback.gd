class_name AudioFeedback
extends RefCounted

const SAMPLE_RATE := 22050

static func make_tone(kind: String, volume: float) -> AudioStreamWAV:
	var frequencies: Array[float] = [760.0]
	var duration := 0.055
	match kind:
		"confirm":
			frequencies = [760.0, 1080.0]
			duration = 0.105
		"cancel":
			frequencies = [460.0]
			duration = 0.075
		"snap":
			frequencies = [920.0]
			duration = 0.045
		"error":
			frequencies = [260.0, 190.0]
			duration = 0.13
	var sample_count := roundi(float(SAMPLE_RATE) * duration)
	var data := PackedByteArray()
	data.resize(sample_count * 2)
	for index in range(sample_count):
		var t := float(index) / float(SAMPLE_RATE)
		var pulse_length := duration / float(frequencies.size())
		var pulse_index := mini(frequencies.size() - 1, floori(t / pulse_length))
		var pulse_t := fposmod(t, pulse_length)
		var frequency := frequencies[pulse_index]
		var envelope := minf(1.0, pulse_t / 0.008) * minf(1.0, (pulse_length - pulse_t) / 0.018)
		var sample_value := roundi(sin(TAU * frequency * pulse_t) * envelope * clampf(volume, 0.0, 1.0) * 5600.0)
		data[index * 2] = sample_value & 0xff
		data[index * 2 + 1] = (sample_value >> 8) & 0xff
	var stream := AudioStreamWAV.new()
	stream.format = AudioStreamWAV.FORMAT_16_BITS
	stream.mix_rate = SAMPLE_RATE
	stream.stereo = false
	stream.loop_mode = AudioStreamWAV.LOOP_DISABLED
	stream.data = data
	return stream
