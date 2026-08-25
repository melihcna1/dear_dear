@tool
class_name DearDearSheetsClient
extends Node

const URL_SETTING := "dear_dear_asset_importer/webhook_url"
const TOKEN_SETTING := "dear_dear_asset_importer/shared_token"
const URL_ENV := "DEAR_DEAR_ASSET_WEBHOOK_URL"
const TOKEN_ENV := "DEAR_DEAR_ASSET_SHARED_TOKEN"
const APPS_SCRIPT_RESULT_ORIGIN := "https://script.googleusercontent.com/"
const REDIRECT_RESPONSE_CODES := [301, 302, 303]

var _request: HTTPRequest
var _busy := false


func _ready() -> void:
	_request = HTTPRequest.new()
	_request.timeout = 20.0
	# Apps Script's ContentService returns a 302 to a one-time Google content
	# URL. Handle that redirect ourselves so older Godot releases do not resend
	# the POST to the result URL, which Google correctly rejects with HTTP 405.
	_request.max_redirects = 0
	add_child(_request)


func is_configured() -> bool:
	return not webhook_url().is_empty() and not shared_token().is_empty()


func webhook_url() -> String:
	var environment_value := OS.get_environment(URL_ENV).strip_edges()
	if not environment_value.is_empty():
		return environment_value
	var settings: EditorSettings = EditorInterface.get_editor_settings()
	return str(settings.get_setting(URL_SETTING)) if settings.has_setting(URL_SETTING) else ""


func shared_token() -> String:
	var environment_value := OS.get_environment(TOKEN_ENV).strip_edges()
	if not environment_value.is_empty():
		return environment_value
	var settings: EditorSettings = EditorInterface.get_editor_settings()
	return str(settings.get_setting(TOKEN_SETTING)) if settings.has_setting(TOKEN_SETTING) else ""


func save_settings(url: String, token: String) -> void:
	var settings: EditorSettings = EditorInterface.get_editor_settings()
	settings.set_setting(URL_SETTING, url.strip_edges())
	settings.set_setting(TOKEN_SETTING, token.strip_edges())
	settings.save()


func call_action(action: String, payload: Dictionary = {}) -> Dictionary:
	if not is_configured():
		return {"ok": false, "error": {"code": "not_configured", "message": "Configure the Sheets webhook URL and token."}}
	if _busy:
		return {"ok": false, "error": {"code": "busy", "message": "A Sheets request is already running."}}
	_busy = true
	var body := payload.duplicate(true)
	body["action"] = action
	body["token"] = shared_token()
	if not body.has("request_id"):
		body["request_id"] = DearDearAssetDraft._uuid()
	var request_error := _request.request(
		webhook_url(),
		PackedStringArray(["Content-Type: application/json"]),
		HTTPClient.METHOD_POST,
		JSON.stringify(body))
	if request_error != OK:
		_busy = false
		return {"ok": false, "error": {"code": "request_failed", "message": error_string(request_error)}}
	var completed: Array = await _request.request_completed
	var response_code := int(completed[1])
	if response_code in REDIRECT_RESPONSE_CODES:
		var redirect_url := redirect_location(completed[2])
		if redirect_url.is_empty():
			_busy = false
			return {"ok": false, "error": {
				"code": "redirect_missing",
				"message": "Sheets redirected without a result URL.",
			}}
		if not is_trusted_apps_script_redirect(redirect_url):
			_busy = false
			return {"ok": false, "error": {
				"code": "redirect_rejected",
				"message": "Sheets returned an unexpected redirect destination.",
			}}
		var redirect_error := _request.request(
			redirect_url,
			PackedStringArray(["Accept: application/json"]),
			HTTPClient.METHOD_GET)
		if redirect_error != OK:
			_busy = false
			return {"ok": false, "error": {
				"code": "redirect_failed",
				"message": error_string(redirect_error),
			}}
		completed = await _request.request_completed
	_busy = false
	return parse_http_response(int(completed[0]), int(completed[1]), completed[3])


func redirect_location(response_headers: PackedStringArray) -> String:
	for header in response_headers:
		var separator := header.find(":")
		if separator > 0 and header.substr(0, separator).strip_edges().to_lower() == "location":
			return header.substr(separator + 1).strip_edges()
	return ""


func is_trusted_apps_script_redirect(url: String) -> bool:
	return url.to_lower().begins_with(APPS_SCRIPT_RESULT_ORIGIN)


func parse_http_response(transport_result: int, response_code: int, response_body: PackedByteArray) -> Dictionary:
	if transport_result != HTTPRequest.RESULT_SUCCESS:
		return {"ok": false, "error": {"code": "transport_error", "message": "Network request failed (%d)." % transport_result}}
	var parser := JSON.new()
	if parser.parse(response_body.get_string_from_utf8()) != OK:
		return {"ok": false, "error": {"code": "malformed_response", "message": "Sheets returned non-JSON data (HTTP %d)." % response_code}}
	var parsed: Variant = parser.data
	if not (parsed is Dictionary):
		return {"ok": false, "error": {"code": "malformed_response", "message": "Sheets returned non-JSON data (HTTP %d)." % response_code}}
	if response_code < 200 or response_code >= 300 or not bool(parsed.get("ok", false)):
		return parsed
	return parsed
