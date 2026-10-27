#!/bin/bash
# Temperature-driven fan control for Lenovo RD450X: its BMC pins all fans at 100% with non-stock CPUs.
set -u

MIN_PWM=${MIN_PWM:-30}
MAX_PWM=100
T_LOW=${T_LOW:-60}
T_HIGH=${T_HIGH:-75}
STEP_DOWN=${STEP_DOWN:-5}
INTERVAL=${INTERVAL:-5}
FANS=("System Fan1" "System Fan2" "System Fan3")
# Readings are quantised in 82 RPM steps; stock 820/492 thresholds alarm at any PWM below ~55%.
LOWER_CRITICAL=164
LOWER_NON_CRITICAL=246

set_pwm() {
	ipmitool raw 0x2e 0x30 0x00 0x00 "$(printf '0x%02x' "$1")" >/dev/null
}

hottest_temp() {
	ipmitool sdr type temperature 2>/dev/null |
		awk -F'|' '/degrees/ { t = $5 + 0; if (t > max) max = t } END { print max + 0 }'
}

pwm_for() {
	local t=$1
	if ((t == 0 || t >= T_HIGH)); then
		echo "$MAX_PWM"
	elif ((t <= T_LOW)); then
		echo "$MIN_PWM"
	else
		echo $((MIN_PWM + (t - T_LOW) * (MAX_PWM - MIN_PWM) / (T_HIGH - T_LOW)))
	fi
}

lower_fan_thresholds() {
	local fan
	for fan in "${FANS[@]}"; do
		ipmitool sensor thresh "$fan" lcr "$LOWER_CRITICAL" >/dev/null
		ipmitool sensor thresh "$fan" lnc "$LOWER_NON_CRITICAL" >/dev/null
	done
}

trap 'set_pwm $MAX_PWM; exit' EXIT INT TERM

lower_fan_thresholds
current=$MAX_PWM
while sleep "$INTERVAL"; do
	temp=$(hottest_temp)
	target=$(pwm_for "$temp")
	((target < current - STEP_DOWN)) && target=$((current - STEP_DOWN))
	# Re-sent every cycle so a BMC reset back to 100% is overridden on the next tick.
	set_pwm "$target" || target=$MAX_PWM
	((target != current)) && echo "temp=${temp}C pwm=${current}->${target}%"
	current=$target
done
