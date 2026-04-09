# Boot Optimization Notes

## Applied
- systemd-boot timeout 0
- Silent boot: quiet loglevel=3 systemd.show_status=auto rd.udev.log_level=3
- Disabled NetworkManager-wait-online.service
- greetd replaces SDDM

## Firmware
- Framework 13 firmware takes ~23s (unchangeable)
- Total expected boot: ~28s (23s firmware + ~5s rest)
