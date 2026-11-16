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
