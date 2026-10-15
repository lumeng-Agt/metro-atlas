extends SceneTree

func _initialize() -> void:
	call_deferred("_run")

func _run() -> void:
	WorldData.load_assets()
	var manifest_file := FileAccess.open("res://data/basemap/manifest.json", FileAccess.READ)
	if manifest_file == null:
		push_error("Offline vector basemap manifest is missing")
		quit(1)
		return
	var manifest: Dictionary = JSON.parse_string(manifest_file.get_as_text())
	manifest_file.close()
	var ok: bool = manifest.get("cities", {}).size() == 5
	var verified_chunks := 0
	for city in WorldData.cities():
		var city_id := str(city.get("id", ""))
		var package: Dictionary = manifest.get("cities", {}).get(city_id, {})
		var chunks: Array = package.get("chunks", [])
		if chunks.is_empty():
			ok = false
			push_error("No offline map chunks for %s" % city_id)
			continue
		for raw_name in chunks:
			var chunk_name := str(raw_name)
			var chunk_path := "res://data/basemap/%s/%s" % [city_id, chunk_name]
			var bytes := FileAccess.get_file_as_bytes(chunk_path)
			if bytes.is_empty():
				ok = false
				push_error("Offline map chunk is missing or empty: %s/%s" % [city_id, chunk_name])
				continue
			var hashing := HashingContext.new()
			hashing.start(HashingContext.HASH_SHA256)
			hashing.update(bytes)
			var checksum := hashing.finish().hex_encode()
			if checksum != str(package.get("chunkSha256", {}).get(chunk_name, "")):
				ok = false
				push_error("Offline map chunk checksum mismatch: %s/%s" % [city_id, chunk_name])
				continue
			verified_chunks += 1
		var sample_chunk_name := str(chunks[0])
		var sample_chunk_path := "res://data/basemap/%s/%s" % [city_id, sample_chunk_name]
		var sample_bytes := FileAccess.get_file_as_bytes(sample_chunk_path)
		var decoded_bytes := sample_bytes.decompress_dynamic(32 * 1024 * 1024, FileAccess.COMPRESSION_GZIP)
		var parsed: Variant = JSON.parse_string(decoded_bytes.get_string_from_utf8()) if not decoded_bytes.is_empty() else null
		if not parsed is Dictionary or str(parsed.get("cityId", "")) != city_id or parsed.get("features", []).is_empty():
			ok = false
			push_error("Offline map chunk cannot be read: %s/%s" % [city_id, sample_chunk_name])
		else:
			print("PASS: %s offline map chunk · %d features · checksum OK" % [city_id, parsed.get("features", []).size()])
	if ok:
		print("PASS: all five cities have readable offline vector map packages · %d chunks checksummed" % verified_chunks)
		quit(0)
	else:
		quit(1)
