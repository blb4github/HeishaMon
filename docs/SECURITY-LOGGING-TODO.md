# TODO — conditional configuration logging based on ESP32 reset reason

**Priority:** next planned firmware iteration; not implemented.  
**Decision:** 2026-11-16, per user's explicit preference: retain existing detailed configuration output on recognized **hardware-initiated resets** (power off/on and physical reset button), but suppress it on **all other reset causes**, including OTA, software restarts, panics, watchdogs and unexplained resets.  
**Current live firmware:** Alpha-4099e8f; **do not change or flash it to implement this TODO**.

## Evidence and root cause

In `HeishaMon/webfunctions.cpp`, function `loadSettings()`, the complete stored `/config.json` is emitted unconditionally through:

```cpp
char log_msg[1024];
serializeJson(jsonDoc, log_msg);
log_message(log_msg);
```

This includes sensitive values (e.g. MQTT/OTA/Wi-Fi credentials) if configured. It happens on normal boot, OTA restart and after a crash. The code calls `loadSettings(&heishamonSettings)` from `HeishaMon.ino`. Two `WiFi.printDiag(loggingSerial)` calls also occur in `setup()` and may print Wi-Fi details. Do not publish actual credentials or raw user logs in upstream issues.

## Agreed operating policy

| Reset cause | Proposed logging |
| --- | --- |
| Recognized power-off/on / external hardware reset button | **Preserve the current detailed startup/configuration logging, including settings values as currently shown** (user-requested diagnostic compromise) |
| OTA firmware upgrade | **No raw configuration**; log reboot reason, firmware build/version, configuration load success/failure, and helpful nonsecret diagnostic information |
| Explicit software restart (`esp_restart` or equivalent) | Same restricted logging |
| Panic, exception, watchdog, deadlock | Same restricted logging; include reset reason and safe crash/diagnostic metadata if available |
| Brownout / power glitch, unknown or ambiguous reset | **Restricted logging by default**; do not classify as a deliberately initiated hardware restart merely because power is involved |

**Security trade-off acknowledged:** intentionally showing the complete configuration for hardware resets still exposes plaintext credentials over whichever serial/web/log paths receive that output. A physical reset might be triggered by a third party or power failure, and logs may be remotely observable afterward. This design reduces exposure on automatic reboots but does **not** eliminate credential logging risk. Treat access to all log receivers and exported logs accordingly. Do not interpret the reset reason as user authentication.

## Implementation proposal (ESP32-S3)

1. Determine reset cause **at the very beginning of `setup()`**, before `loadSettings()` and `WiFi.printDiag`:
   `esp_reset_reason_t reason = esp_reset_reason();`.
2. Enable full configuration printing **only for reset-reason values positively confirmed on the target board to correspond to power-on or the physical reset button**. Candidate constants are `ESP_RST_POWERON` and `ESP_RST_EXT`, but the actual reset button/EN wiring and Arduino/ESP-IDF interpretation must be confirmed in a bench test. A dedicated reset button may present as `ESP_RST_POWERON`.
3. Treat **every other** reset reason as restricted. This includes `ESP_RST_SW`, `ESP_RST_PANIC`, `ESP_RST_INT_WDT`, `ESP_RST_TASK_WDT`, `ESP_RST_WDT`, `ESP_RST_BROWNOUT`, `ESP_RST_PWR_GLITCH`, `ESP_RST_UNKNOWN` and any future/unrecognized codes. Fail closed.
4. Pass `fullConfigDiagnostics` (or a small diagnostic-policy enum) to `loadSettings()` rather than adding persistent configuration or delaying reset detection until after config load.
5. When `fullConfigDiagnostics` is false, **do not call `serializeJson(jsonDoc, log_msg)` or `log_message(log_msg)`** on the full document; emit only a short status and error code. Do not create the secret-bearing log string unnecessarily.
6. Check the two `WiFi.printDiag` calls and any other startup/config dump paths, so restricted resets cannot leak credentials through a second route.
7. For software/OTA/crash restarts, include safe diagnostics where available: firmware version, reset code + textual cause, config parse status, free heap/PSRAM, and potentially Rules status. A plain `ESP_RST_SW` does not distinguish OTA from other intentional software restarts; that distinction is optional, not necessary for the agreed policy.
8. Preserve existing functional settings and persistence; do not modify `config.json`, Rules behavior, GPIO33, OpenTherm or heat-pump control.

**ESP8266:** use equivalent platform-specific reset classification if extending the behavior beyond ESP32-S3; do not automatically assume its reset codes map identically. Separate validation is required.

## Tests before next firmware

- [ ] Real power-cycle: the existing full boot/config diagnostic output still appears.
- [ ] Physical reset button: identify the actual reset reason, then confirm the expected full output.
- [ ] OTA firmware update: only reset reason, safe metadata and config load status; none of the sentinel passwords are visible.
- [ ] Explicit software reset: similarly restricted.
- [ ] Simulated panic/watchdog and ambiguous brownout/unknown reason: restricted diagnostic output, no raw settings.
- [ ] Check both Serial and web-console logging; verify no accidental leakage via `WiFi.printDiag`.
- [ ] Use **synthetic test credentials only**; do not attach real logs to a public PR.
- [ ] All 16 Rules, 138 variable slots, GPIO33, OpenTherm and Panasonic communications work unchanged.

## Process

Separate this diagnostic logging improvement from the 255-slot Rules VM and webserver PRs. Document and test the chosen deliberate security trade-off before any proposal to Igor. This file is a future-work specification; no firmware code has been altered.
