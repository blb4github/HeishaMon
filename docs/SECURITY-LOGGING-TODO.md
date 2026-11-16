# TODO — prevent plaintext configuration and credential leakage in logs

**Priority:** security/privacy hardening before the next intentional firmware version.  
**Status:** OPEN / NOT IMPLEMENTED. The live ESP32-S3 firmware is not changed.  
**Observed:** 2026-11-16 on ESP32-S3 Alpha-4099e8f during a normal reboot after OTA. This issue also applies to subsequent crash/watchdog reboots because the same boot code runs.

## Precise cause

In `HeishaMon/webfunctions.cpp`, `loadSettings()`, immediately after deserializing `/config.json`:

```cpp
char log_msg[1024];
serializeJson(jsonDoc, log_msg);
log_message(log_msg);
```

This logs the complete stored configuration, including sensitive fields such as Wi-Fi, MQTT and OTA passwords. It may also reveal connection details and other identifying configuration. **This is an unconditional startup-log disclosure, not a crash-only problem.** The startup path is reached through `loadSettings(&heishamonSettings)` in `HeishaMon/HeishaMon.ino`.

Also audit `WiFi.printDiag(loggingSerial)` before and after settings load: these debug outputs should not disclose passwords or other sensitive identifiers. Other diagnostic, serial and web-console output should be inspected for the same class of disclosure.

**Do not publish any original raw console log or real credentials in this document, a PR, or an upstream issue.**

## Diagnostic logging by boot/reset cause — design refinement (2026-11-16)

The full configuration dump was likely intended to help diagnose which settings were loaded at boot. **Keep useful diagnostics while avoiding plaintext secrets.**

ESP32-S3 provides `esp_reset_reason()` with codes such as `ESP_RST_POWERON` (cold boot), `ESP_RST_SW` (e.g. OTA-triggered `esp_restart`), `ESP_RST_PANIC` and watchdog reasons. HeishaMon already reads this information in `HeishaMon.ino`, but currently only *after* `loadSettings()`, in the Rules crash-restart decision; move/read the reason earlier for logging policy.

**Proposed reset-aware log levels:**

| Boot situation | Suggested diagnostic output |
| --- | --- |
| Power-on / reset button | Sanitized configuration diagnostics: which settings/options are enabled, connection settings only where relevant and non-sensitive, credential **configured/not configured** |
| OTA / other software reset | Firmware version, reset reason, config successfully loaded, no configuration dump |
| Crash, watchdog, brownout | Reset reason, exception/error indicators and safe health diagnostics, no configuration dump |

Note that a physical EN/reset-button press and an actual power-on can be indistinguishable in the reset-reason API; similarly `ESP_RST_SW` is not uniquely proof of OTA. The reset reason is therefore a **diagnostic hint, not an authorization mechanism**. Identifying OTA precisely would require an explicit nonsecret pre-reboot marker, if needed. Even a power-on can be induced or observed by someone else, and startup logs are available through multiple interfaces.

**Credentials must never be logged in plaintext**, regardless of reason. Prefer an allowlist of harmless diagnostics. Avoid a fully expanded settings object on power-on. If more diagnostics are needed, provide an *explicit* authorized diagnostic mode that only exposes safe values and does not run automatically during every reboot.

**Boot-button caution:** `BOOTPIN` is GPIO0 in the ESP32-S3 build. Holding GPIO0 low during reset can select the ROM download mode. In the running firmware the button is already used for factory reset after ~10 seconds. Do **not** propose using a long BOOT-button hold during power-on as the default way to request verbose logs without hardware-specific design/testing.

## Required next firmware change

1. **Remove the full `serializeJson(jsonDoc, log_msg)` + `log_message(log_msg)` configuration dump** from the normal boot path. Keep a concise status message such as `Configuration loaded` / `Configuration parse failed` without echoing the input.
2. If configuration diagnostics are truly needed, **allowlist safe, non-secret fields**; do not redact only currently known secret keys because future settings might add credentials.
3. Review and adjust `WiFi.printDiag` and all other startup, post-crash, serial, web-console and persistent log paths for passwords, tokens, passphrases, usernames, keys, and sensitive network/installation identifiers. Prefer omission over displaying a partial credential.
4. Preserve functioning configuration loading, Wi-Fi, MQTT, OpenTherm, GPIO and Rules. No change to the saved configuration format is intended.
5. Keep non-sensitive diagnostics (firmware version, reset reason, success/failure of config load, error codes, RAM/heap and Rules status).

## Acceptance criteria

- Dummy/sentinel credentials placed in all configured secret fields do **not** appear in serial, web console, MQTT diagnostic output, or retained logs after normal cold boot, OTA reboot, watchdog restart or simulated crash.
- Malformed `config.json` / parsing errors never echo the raw JSON payload.
- Normal configuration/feature operation is unchanged, including GPIO33 and the 255-slot Rules build.
- Verify via a regression test where practical; use synthetic credentials and sanitized logs only.

## Process

- Keep this security work **separate** from the compact 255-variable-slot Rules VM and experimental async webserver changes.
- Implement and review before a future firmware rollout; do **not** flash or reboot the operating installation merely to address documentation.
- After the tested fix, consider submitting a sanitized upstream change to Igor's official HeishaMon repository.
