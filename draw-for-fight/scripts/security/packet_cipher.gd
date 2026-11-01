class_name PacketCipher
extends RefCounted

const AES_BLOCK_SIZE := 16
const AES_KEY_SIZE := 32

static func derive_packet_iv(iv_seed: PackedByteArray, seq_num: int) -> PackedByteArray:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(iv_seed)
	ctx.update(("D4F_IV_SEQ|" + str(seq_num)).to_utf8_buffer())
	var digest: PackedByteArray = ctx.finish()
	return digest.slice(0, AES_BLOCK_SIZE)

static func compute_packet_mac(mac_key: PackedByteArray, seq_num: int, iv: PackedByteArray, ciphertext: PackedByteArray) -> PackedByteArray:
	var safe_key := mac_key
	if safe_key.is_empty():
		safe_key = PackedByteArray()
		safe_key.resize(32)
		safe_key.fill(0)
	var hmac := HMACContext.new()
	hmac.start(HashingContext.HASH_SHA256, safe_key)
	hmac.update(("D4F_L6_MAC|" + str(seq_num) + "|").to_utf8_buffer())
	hmac.update(iv)
	hmac.update(ciphertext)
	return hmac.finish()

static func pkcs7_pad(data: PackedByteArray) -> PackedByteArray:
	var pad_len := AES_BLOCK_SIZE - (data.size() % AES_BLOCK_SIZE)
	var padded := data.duplicate()
	for _i in range(pad_len):
		padded.append(pad_len & 0xFF)
	return padded

static func pkcs7_unpad(padded: PackedByteArray) -> Dictionary:
	if padded.is_empty() or (padded.size() % AES_BLOCK_SIZE) != 0:
		return {"ok": false, "data": PackedByteArray(), "error": "Invalid ciphertext block alignment."}
	var pad_len: int = padded[padded.size() - 1]
	if pad_len < 1 or pad_len > AES_BLOCK_SIZE or pad_len > padded.size():
		return {"ok": false, "data": PackedByteArray(), "error": "Invalid PKCS#7 padding length."}
	for i in range(padded.size() - pad_len, padded.size()):
		if padded[i] != pad_len:
			return {"ok": false, "data": PackedByteArray(), "error": "Corrupted PKCS#7 padding bytes."}
	return {
		"ok": true,
		"data": padded.slice(0, padded.size() - pad_len),
		"error": ""
	}

static func encrypt_payload(
	plaintext_bytes: PackedByteArray,
	seq_num: int,
	enc_key: PackedByteArray,
	mac_key: PackedByteArray,
	iv_seed: PackedByteArray
) -> Dictionary:
	if enc_key.size() != AES_KEY_SIZE or mac_key.size() != AES_KEY_SIZE or iv_seed.size() < AES_BLOCK_SIZE:
		return {
			"ok": false,
			"layer": 6,
			"error": "Invalid cryptographic key or IV seed lengths."
		}

	var iv := derive_packet_iv(iv_seed, seq_num)
	var padded := pkcs7_pad(plaintext_bytes)

	var aes := AESContext.new()
	var start_err := aes.start(AESContext.MODE_CBC_ENCRYPT, enc_key, iv)
	if start_err != OK:
		return {
			"ok": false,
			"layer": 6,
			"error": "Failed to initialize AESContext for encryption."
		}
	var ciphertext: PackedByteArray = aes.update(padded)
	aes.finish()

	var mac := compute_packet_mac(mac_key, seq_num, iv, ciphertext)
	return {
		"ok": true,
		"layer": 6,
		"seq_num": seq_num,
		"iv_hex": iv.hex_encode(),
		"ciphertext_hex": ciphertext.hex_encode(),
		"mac_hex": mac.hex_encode()
	}

static func decrypt_payload(
	envelope: Dictionary,
	enc_key: PackedByteArray,
	mac_key: PackedByteArray,
	iv_seed: PackedByteArray
) -> Dictionary:
	if enc_key.size() != AES_KEY_SIZE or mac_key.size() != AES_KEY_SIZE or iv_seed.size() < AES_BLOCK_SIZE:
		return {
			"ok": false,
			"layer": 6,
			"error": "Invalid session key lengths for decryption."
		}

	var seq_num := int(envelope.get("seq_num", -1))
	if seq_num <= 0:
		return {
			"ok": false,
			"layer": 6,
			"error": "Missing or invalid sequence number in packet envelope."
		}

	var iv_hex := String(envelope.get("iv_hex", ""))
	var ciphertext_hex := String(envelope.get("ciphertext_hex", ""))
	var mac_hex := String(envelope.get("mac_hex", ""))

	if iv_hex.length() != 32 or mac_hex.length() != 64 or ciphertext_hex.is_empty():
		return {
			"ok": false,
			"layer": 6,
			"error": "Malformed cryptographic envelope fields."
		}

	var iv := iv_hex.hex_decode()
	var ciphertext := ciphertext_hex.hex_decode()
	var received_mac := mac_hex.hex_decode()

	if iv.size() != AES_BLOCK_SIZE or (ciphertext.size() % AES_BLOCK_SIZE) != 0 or received_mac.size() != 32:
		return {
			"ok": false,
			"layer": 6,
			"error": "Decoded IV, ciphertext, or MAC byte length invalid."
		}

	# Verify deterministic IV binding to sequence number
	var expected_iv := derive_packet_iv(iv_seed, seq_num)
	var crypto := Crypto.new()
	if not crypto.constant_time_compare(expected_iv, iv):
		return {
			"ok": false,
			"layer": 6,
			"error": "Packet IV does not match sequence-derived IV."
		}

	# Encrypt-then-MAC: Verify HMAC in constant time BEFORE decrypting
	var expected_mac := compute_packet_mac(mac_key, seq_num, iv, ciphertext)
	if not crypto.constant_time_compare(expected_mac, received_mac):
		return {
			"ok": false,
			"layer": 6,
			"error": "HMAC-SHA256 integrity verification failed (tampered packet)."
		}

	var aes := AESContext.new()
	var start_err := aes.start(AESContext.MODE_CBC_DECRYPT, enc_key, iv)
	if start_err != OK:
		return {
			"ok": false,
			"layer": 6,
			"error": "Failed to initialize AESContext for decryption."
		}
	var decrypted_padded: PackedByteArray = aes.update(ciphertext)
	aes.finish()

	var unpad_res := pkcs7_unpad(decrypted_padded)
	if not bool(unpad_res.get("ok", false)):
		return {
			"ok": false,
			"layer": 6,
			"error": String(unpad_res.get("error", "Padding error"))
		}

	return {
		"ok": true,
		"layer": 6,
		"seq_num": seq_num,
		"plaintext_bytes": unpad_res["data"]
	}
