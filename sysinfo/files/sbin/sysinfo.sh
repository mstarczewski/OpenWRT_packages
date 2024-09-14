#!/bin/sh

# Based on # obsy, http://eko.one.pl
# Define color codes and attributes
PASTEL_CYAN="\033[1;36m"
LIGHT_YELLOW="\033[1;33m"   
WHITE="\033[1;37m"          
BOLD="\033[1m"              
RESET="\033[0m"
LIGHT_RED="\033[1;31m"
GREEN="\033[0;32m"
LIGHT_ORANGE="\033[38;5;214m"

# Function to create a horizontal line
hr_line() {
    LINEH=$1
    echo "-"$(for i in $(seq 2 "$LINEH"); do printf "-"; done)
}

# Display human-readable sizes
hr() {
    if [ $1 -gt 0 ]; then
        printf "$(awk -v n=$1 'BEGIN{for(i=split("B KB MB GB TB PB",suffix);s<1;i--)s=n/(2**(10*i));printf (int(s)==s)?"%.0f%s":"%.1f%s",s,suffix[i+2]}' 2>/dev/null)"
    else
        printf "0B"
    fi
}

# Get machine information
MACH=""
[ -e /tmp/sysinfo/model ] && MACH=$(cat /tmp/sysinfo/model)
[ -z "$MACH" ] && MACH=$(awk -F: '/Hardware/ {print $2}' /proc/cpuinfo)
[ -z "$MACH" ] && MACH=$(awk -F: '/system type/ {print $2}' /proc/cpuinfo)
[ -z "$MACH" ] && MACH=$(awk -F: '/machine/ {print $2}' /proc/cpuinfo)
[ -z "$MACH" ] && MACH=$(awk -F: '/model name/ {print $2}' /proc/cpuinfo | head -1)

# Uptime
U=$(cut -d. -f1 /proc/uptime)
D=$(expr $U / 60 / 60 / 24)
H=$(expr $U / 60 / 60 % 24)
M=$(expr $U / 60 % 60)
S=$(expr $U % 60)
U=$(printf "%dd, %02d:%02d:%02d" "$D" "$H" "$M" "$S")

# Load averages
L=$(awk '{ print $1" "$2" "$3}' /proc/loadavg)

# Flash memory
RFS=$(df /overlay 2>/dev/null | awk '/overlay/ {printf "%.0f:%.0f:%s", $4*1024, $2*1024, $5}')
[ -z "$RFS" ] && RFS=$(df / 2>/dev/null | awk '/dev\/root/ {printf "%.0f:%.0f:%s", $4*1024, $2*1024, $5}')
if [ -n "$RFS" ]; then
    a1=$(echo "$RFS" | cut -f1 -d:)
    a2=$(echo "$RFS" | cut -f2 -d:)
    a3=$(echo "$RFS" | cut -f3 -d:)
    RFS="total: "$(hr $a2)", free: "$(hr $a1)", used: "$a3
fi

# Memory usage
total_mem="$(awk '/^MemTotal:/ {print $2*1024}' /proc/meminfo)"
buffers_mem="$(awk '/^Buffers:/ {print $2*1024}' /proc/meminfo)"
cached_mem="$(awk '/^Cached:/ {print $2*1024}' /proc/meminfo)"
free_mem="$(awk '/^MemFree:/ {print $2*1024}' /proc/meminfo)"
free_mem="$((free_mem + buffers_mem + cached_mem))"
MEM=$(echo "total: "$(hr $total_mem)", free: "$(hr $free_mem)", used: "$(( (total_mem - free_mem) * 100 / total_mem))"%")

# Start display output
LINE1=$(wc -L /etc/banner | awk '{print $1}')
LINE=$((LINE1-5))
LINEH=$((LINE1+25))
hr_line "$LINEH"

# Display machine, uptime, load, flash, and memory
printf "${LIGHT_ORANGE}- Machine: ${WHITE}%s${RESET}\n" "$MACH"
printf "${LIGHT_ORANGE}- Uptime: ${WHITE}%s${RESET}\n" "$U"
printf "${LIGHT_ORANGE}- Load: ${WHITE}%s${RESET}\n" "$L"
printf "${LIGHT_ORANGE}- Flash: ${WHITE}%s${RESET}\n" "$RFS"
printf "${LIGHT_ORANGE}- Memory: ${WHITE}%s${RESET}\n" "$MEM"

# Display DHCP leases if available
if [ -e /tmp/dhcp.leases ]; then
    printf "${LIGHT_ORANGE}- Leases: ${WHITE}%s${RESET}\n" "$(awk 'END {print NR}' /tmp/dhcp.leases)"
fi

# Display network interfaces
printf "${LIGHT_YELLOW}- Network interface${RESET}\n"
SEC=$(uci show network | awk -F[\.=] '/=interface/{print $2}')
for i in $SEC; do
    [ "x$i" = "xloopback" ] && continue
    S=$i
    [ -n "$(ubus list network.interface."$S"_4 2>/dev/null)" ] && S=$i"_4"
    PROTO=$(uci -q get network."$i".proto)
    IP=$(ubus call network.interface status '{"interface":"'$S'"}' 2>/dev/null | jsonfilter -q -e "@['ipv4-address'][0].address")
    [ -z "$IP" ] && IP=$(uci -q -P /var/state get network."$S".ipaddr)
    printf "    ${WHITE}%s: ${PASTEL_YELLOW}%s, IP: ${WHITE}%s${RESET}\n" "$i" "$PROTO" "${IP:-"?"}"
done

# Display wireless status
printf "${LIGHT_RED}- Wireless device ${RESET}\n"
SEC=$(uci -q show wireless | grep "device='radio" | cut -f2 -d. | sort)
for i in $SEC; do
    SSID=$(uci -q get wireless."$i".ssid)
    DEV=$(uci -q get wireless."$i".device)
    OFF=$(uci -q get wireless."$DEV".disabled)
    OFF2=$(uci -q get wireless."$i".disabled)
    STATUS=$(ubus call network.wireless status '{"device":"'"$DEV"'"}' 2>/dev/null)
    UP=$(echo "$STATUS" | jsonfilter -q -e @.*.up)
    if [ -n "$SSID" ] && [ "x$OFF" != "x1" ] && [ "x$OFF2" != "x1" ] && [ "x$UP" = "xtrue" ]; then
        MODE=$(uci -q -P /var/state get wireless."$i".mode)
        CHANNEL=$(uci -q get wireless."$DEV".channel)
        NET=$(echo "$STATUS" | jsonfilter -e '@.*.interfaces[@.section="'"$i"'"].config.network[*]')
        IFNAMES=$(echo "$STATUS" | jsonfilter -e '@.*.interfaces[@.section="'"$i"'"].ifname')
        for j in $IFNAMES; do
            CNT=$(iw dev $j station dump 2>/dev/null | grep -c Station)
            printf "    ${WHITE}%s: ${PASTEL_YELLOW}SSID: ${WHITE}%s, Mode: ${PASTEL_YELLOW}%s, Channel: ${WHITE}%s, Connections: ${PASTEL_YELLOW}%s${RESET}\n" "$DEV" "$SSID" "$MODE" "$CHANNEL" "${CNT:-0}"
        done
    fi
done

# Display all available temperature sensors with 'temp_input'
printf "${GREEN}- Temperature sensor ${RESET}\n"
find /sys/ -name "temp*_input" 2>/dev/null | while read tempfile; do
    sensor_dir=$(dirname "$tempfile")
    device_name=""
    if [ -f "$sensor_dir/name" ]; then
        device_name=$(cat "$sensor_dir/name")
    fi
    temp_value=$(cat "$tempfile" 2>/dev/null)
    if [ -n "$temp_value" ]; then
        temp_c=$(awk "BEGIN {printf \"%.1f\", $temp_value/1000}")
        if [ -n "$device_name" ]; then
            printf "    ${WHITE}%s: ${BOLD}%s°C${RESET}\n" "$device_name" "$temp_c"
        else
            temp_name=$(basename "$sensor_dir")
            printf "    ${WHITE}%s: ${BOLD}%s°C${RESET}\n" "$temp_name" "$temp_c"
        fi
    fi
done

hr_line "$LINEH"

# Additional system info from /etc/sysinfo.d
ADDON=""
for i in $(ls /etc/sysinfo.d/* 2>/dev/null); do
    T=$($i)
    if [ -n "$T" ]; then
        printf "${PASTEL_CYAN}- Additional Info: ${WHITE}%s${RESET}\n" "$T"
        ADDON="1"
    fi
done

if [ -n "$ADDON" ]; then
    hr_line "$LINE1"
fi

exit 0
