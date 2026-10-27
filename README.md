# rd450x-fan-control

Adaptive fan control for the Lenovo ThinkServer RD450X. With CPUs outside the factory configuration, the BMC keeps every fan at 100% regardless of temperature.

Every 5 seconds the service reads all IPMI sensors in one call (with a cached SDR, ~0.3 s) and sets all fans with the OEM command `ipmitool raw 0x2e 0x30 0x00 <fan> <pwm>`:

- each sensor group has its own curve, from `MIN_PWM` (30%) to 100%; the group demanding the most wins:

  | Sensors | MIN_PWM up to | 100% at |
  |---|---|---|
  | CPU1/CPU2 | 65 °C | 80 °C |
  | CPU and DIMM VRs | 70 °C | 90 °C |
  | DIMMs | 70 °C | 85 °C |
  | PCH | 65 °C | 85 °C |
  | System, Outlet | 60 °C | 70 °C |
  | HDD (board sensor) | 62 °C | 72 °C |

- ramps up immediately; ramps down only once temperatures are `HYSTERESIS` (3 °C) below the current point, by at most `STEP_DOWN` (5%) per cycle;
- 100% when sensors cannot be read or any of System Fan1–3 drops below the critical threshold (stalled fan);
- every `ipmitool` call has a `IPMI_TIMEOUT` (10 s); a systemd watchdog (60 s) restarts the service if it hangs;
- 100% on stop, crash or watchdog kill.

On start it lowers the System Fan1–3 thresholds to 164/246 RPM (critical/non-critical): the stock 820/492 RPM thresholds fire at any duty below ~55%.

## Measurements (2× E5-2697A v4, idle)

| PWM | RPM | Hottest sensor |
|---|---|---|
| 100% | ~1500 | 54 °C |
| 40% | ~575–655 | 56 °C |
| 30% | 410 | 59 °C |
| 25% | ≤328 | 59 °C |
| 20% | ≤328 | 59 → 63 °C, rising |
| 15% | ≤328 | 63 → 70 °C, rising |

328 RPM is the lowest value the fan sensor reports.

## Install

```bash
apt install ipmitool
install -m 755 rd450x-fan.sh /usr/local/sbin/
install -m 644 rd450x-fan.service /etc/systemd/system/
systemctl daemon-reload
systemctl enable --now rd450x-fan
journalctl -u rd450x-fan -f
```

Parameters can be overridden in `/etc/default/rd450x-fan`: `MIN_PWM`, `STEP_DOWN`, `HYSTERESIS`, `INTERVAL`, `IPMI_TIMEOUT`. Curves are the `CURVES` table in the script.

## Rollback

```bash
systemctl disable --now rd450x-fan
for f in 1 2 3; do ipmitool sensor thresh "System Fan$f" lcr 492; ipmitool sensor thresh "System Fan$f" lnc 820; done
```

## References

- [Hackmag: Building a PC with a Lenovo RD450X Server Motherboard](https://hackmag.com/security/lenovo-rd450x-pc)
- [32fca06c/rd450x_pwmcontrol](https://github.com/32fca06c/rd450x_pwmcontrol)
- [Vabavia/rd450x-fan-control](https://github.com/Vabavia/rd450x-fan-control)

## License

MIT, see [LICENSE](LICENSE).
