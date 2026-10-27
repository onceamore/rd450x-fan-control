#!/bin/bash
# Temperature-driven fan control for Lenovo RD450X: its BMC pins all fans at 100% with non-stock CPUs.
set -u

MIN_PWM=${MIN_PWM:-30}
MAX_PWM=100
STEP_DOWN=${STEP_DOWN:-5}
HYSTERESIS=${HYSTERESIS:-3}
INTERVAL=${INTERVAL:-5}
IPMI_TIMEOUT=${IPMI_TIMEOUT:-10}
SDR_CACHE=${SDR_CACHE:-/run/rd450x-fan.sdr}
FANS=("System Fan1" "System Fan2" "System Fan3")
# Readings are quantised in 82 RPM steps; stock 820/492 thresholds alarm at any PWM below ~55%.
LOWER_CRITICAL=164
LOWER_NON_CRITICAL=246

# sensor-name regex : temp at MIN_PWM : temp at MAX_PWM
CURVES=(
	'^CPU[12] Temp$:65:80'
	'VR( Temp)?$:70:90'
	'^CPU[12] DIMM [A-D][01]$:70:85'
	'^PCH Temp$:65:85'
	'^(System|Outlet) Temp$:60:70'
	'^HDD Temp$:62:72'
)

log() { echo "<$1>$2"; }

ipmi() { timeout "$IPMI_TIMEOUT" ipmitool -S "$SDR_CACHE" "$@"; }

set_pwm() { ipmi raw 0x2e 0x30 0x00 0x00 "$(printf '0x%02x' "$1")" >/dev/null; }

read_sensors() { ipmi -c sdr list full 2>/dev/null; }

pwm_for_curve() {
	local t=$1 low=$2 high=$3
	if ((t <= low)); then
		echo "$MIN_PWM"
	elif ((t >= high)); then
		echo "$MAX_PWM"
	else
		echo $((MIN_PWM + (t - low) * (MAX_PWM - MIN_PWM) / (high - low)))
	fi
}

# Prints the PWM demanded by the hottest sensor relative to its own curve, offset by $2 degrees.
demanded_pwm() {
	local sensors=$1 offset=$2 name value curve regex low high pwm max=0 matched=0
	while IFS=, read -r name value _; do
		[[ $value =~ ^[0-9]+$ ]] && ((value > 0)) || continue
		for curve in "${CURVES[@]}"; do
			IFS=: read -r regex low high <<<"$curve"
			[[ $name =~ $regex ]] || continue
			matched=1
			pwm=$(pwm_for_curve $((value + offset)) "$low" "$high")
			((pwm > max)) && max=$pwm
			break
		done
	done <<<"$sensors"
	((matched)) && echo "$max" || echo "$MAX_PWM"
}

stalled_fans() {
	local sensors=$1 fan rpm
	for fan in "${FANS[@]}"; do
		rpm=$(awk -F, -v f="$fan" '$1 == f { print $2 }' <<<"$sensors")
		[[ $rpm =~ ^[0-9]+$ ]] && ((rpm >= LOWER_CRITICAL)) || echo -n "$fan "
	done
}

lower_fan_thresholds() {
	local fan
	for fan in "${FANS[@]}"; do
		ipmi sensor thresh "$fan" lcr "$LOWER_CRITICAL" >/dev/null
		ipmi sensor thresh "$fan" lnc "$LOWER_NON_CRITICAL" >/dev/null
	done
}

next_pwm() {
	local sensors=$1 current=$2 up down
	up=$(demanded_pwm "$sensors" 0)
	((up >= current)) && { echo "$up"; return; }
	down=$(demanded_pwm "$sensors" "$HYSTERESIS")
	((down > current)) && down=$current
	((down < current - STEP_DOWN)) && down=$((current - STEP_DOWN))
	echo "$down"
}

trap 'set_pwm $MAX_PWM; exit' EXIT INT TERM

timeout "$IPMI_TIMEOUT" ipmitool sdr dump "$SDR_CACHE" >/dev/null || { log 3 "cannot dump SDR"; exit 1; }
lower_fan_thresholds
current=$MAX_PWM
prev_stalled=
set_pwm "$current"
systemd-notify --ready

while sleep "$INTERVAL"; do
	sensors=$(read_sensors)
	if [[ -z $sensors ]]; then
		target=$MAX_PWM
		log 4 "sensor read failed"
	else
		stalled=$(stalled_fans "$sensors")
		[[ $stalled != "$prev_stalled" ]] && log 2 "stalled fans: ${stalled:-none}"
		prev_stalled=$stalled
		if [[ -n $stalled ]]; then
			target=$MAX_PWM
		else
			target=$(next_pwm "$sensors" "$current")
		fi
	fi
	# Re-sent every cycle so a BMC reset back to its own default is overridden on the next tick.
	set_pwm "$target" || { log 4 "set_pwm failed"; continue; }
	((target != current)) && log 6 "pwm ${current}->${target}%"
	current=$target
	systemd-notify WATCHDOG=1
done
