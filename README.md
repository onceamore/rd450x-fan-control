# rd450x-fan-control

Adaptive fan control for the Lenovo ThinkServer RD450X. With CPUs outside the factory configuration, the BMC keeps every fan at 100% regardless of temperature.

Every 5 seconds the service takes the highest IPMI temperature reading and sets all fans with the OEM command `ipmitool raw 0x2e 0x30 0x00 <fan> <pwm>`:

- up to `T_LOW` (60 °C): `MIN_PWM` (30%);
- from `T_LOW` to `T_HIGH` (75 °C): linear ramp to 100%;
- above `T_HIGH`, or when sensors cannot be read: 100%;
- ramps down by at most `STEP_DOWN` (5%) per cycle;
- on stop or crash: 100%.

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

Parameters can be overridden in `/etc/default/rd450x-fan`, e.g. `MIN_PWM=25`.

## Rollback

```bash
systemctl disable --now rd450x-fan
for f in 1 2 3; do ipmitool sensor thresh "System Fan$f" lcr 492; ipmitool sensor thresh "System Fan$f" lnc 820; done
```

## References

- [Hackmag: Building a PC with a Lenovo RD450X Server Motherboard](https://hackmag.com/security/lenovo-rd450x-pc)
- [32fca06c/rd450x_pwmcontrol](https://github.com/32fca06c/rd450x_pwmcontrol)
- [Vabavia/rd450x-fan-control](https://github.com/Vabavia/rd450x-fan-control)
