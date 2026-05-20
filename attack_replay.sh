#!/bin/bash
VERSION="v2.0.0"

if [ -t 1 ]; then
    RED=$(tput setaf 1)
    GREEN=$(tput setaf 2)
    YELLOW=$(tput setaf 3)
    BLUE=$(tput setaf 6)
    MAGENTA=$(tput setaf 5)
    CYAN=$(tput setaf 6)
    BOLD=$(tput bold)
    DIM=$(tput dim)
    RESET=$(tput sgr0)
else
    RED=""; GREEN=""; YELLOW=""; BLUE=""; MAGENTA=""; CYAN=""; BOLD=""; DIM=""; RESET=""
fi

print_banner() {
    echo "${CYAN}──────────────────────────────────────────────────────────────${RESET}"
    echo "${BOLD}${CYAN}                  Attack Replay ${VERSION}${RESET}"
    echo "${CYAN}──────────────────────────────────────────────────────────────${RESET}"
}

print_header() {
    echo
    echo "${BOLD}${CYAN}◆ $1${RESET}"
    echo "${CYAN}──────────────────────────────────────────────────────────────${RESET}"
}

print_key() {
    local param="$1"
    local desc="$2"
    
    printf "${BOLD}%s${RESET}" "$param"
    printf "%$((25 - ${#param}))s" " "
    echo "$desc"
}

print_success() {
    echo "${GREEN}✓${RESET} $1"
}

print_error() {
    echo "${RED}✗${RESET} $1" >&2
}

print_file() {
    echo "${CYAN}▶${RESET} ${BOLD}$1${RESET} ${DIM}$2${RESET}"
}

log() { 
    [ $QUIET -eq 0 ] && echo "$@"; 
}

error() { 
    print_error "$@"; 
}

decline_edit() {
    local_count=$1
    last_two=$((local_count % 100))
    last_one=$((local_count % 10))
    
    if [ $last_two -ge 11 ] && [ $last_two -le 14 ]; then
        echo "файлов"
    else
        case $last_one in
            1) echo "файла" ;;
            *) echo "файлов" ;;
        esac
    fi
}

decline_play() {
    local_count=$1
    last_two=$((local_count % 100))
    last_one=$((local_count % 10))
    
    if [ $last_two -ge 11 ] && [ $last_two -le 14 ]; then
        echo "файлов"
    else
        case $last_one in
            1) echo "файл" ;;
            2|3|4) echo "файла" ;;
            *) echo "файлов" ;;
        esac
    fi
}

check_dependencies() {
    local missing=()
    ! command -v tcprewrite &>/dev/null && missing+=("tcprewrite")
    ! command -v tcpreplay &>/dev/null && missing+=("tcpreplay")
    ! command -v file &>/dev/null && missing+=("file")
    ! command -v tcpprep &>/dev/null && missing+=("tcpprep")

    if [ ${#missing[@]} -gt 0 ]; then
        print_error "Отсутствуют утилиты: ${missing[*]}"
        echo -n "${BOLD}Установить автоматически? (y/n): ${RESET}"
        read -r answer
        if [[ ! "$answer" =~ ^[YyДд]$ ]]; then
            print_error "Установка отменена"
            exit 1
        fi
        if [ "$EUID" -ne 0 ]; then
            print_error "Для установки нужны права root. Запустите с sudo."
            exit 1
        fi
        echo "${YELLOW}Установка необходимых пакетов...${RESET}"
        if command -v apt-get &>/dev/null; then
            apt-get update && apt-get install -y tcpreplay file
        elif command -v yum &>/dev/null; then
            yum install -y tcpreplay file
        elif command -v dnf &>/dev/null; then
            dnf install -y tcpreplay file
        elif command -v pacman &>/dev/null; then
            pacman -Sy --noconfirm tcpreplay file
        elif command -v zypper &>/dev/null; then
            zypper install -y tcpreplay file
        else
            print_error "Не удалось определить менеджер пакетов. Установите вручную."
            exit 1
        fi
        for cmd in "${missing[@]}"; do
            ! command -v "$cmd" &>/dev/null && { print_error "Не удалось установить $cmd"; exit 1; }
        done
        print_success "Утилиты успешно установлены!"
    fi
}

show_help() {
    print_banner
    cat <<EOF
${BOLD}Использование:${RESET} $0 [опции] <путь_к_pcap_файлу_или_директории>

EOF

    print_header "РЕДАКТИРОВАНИЕ PCAP"
    echo "  --src-mac=<MAC>          MAC источника (aa:bb:cc:dd:ee:ff)"
    echo "  --dst-mac=<MAC>          MAC назначения (aa:bb:cc:dd:ee:ab)"
    echo "  --src-ip=<IP>            IP источника (192.168.1.1)"
    echo "  --dst-ip=<IP>            IP назначения (192.168.1.2)"
    echo "  -k, --keep-original      Сохранять оригиналы pcap файлов (создавать копии)"

    print_header "ВОСПРОИЗВЕДЕНИЕ"
    echo "  -i, --interval <сек>     Пауза между отправкой (воспроизведением) pcap файлов (0 - без паузы)"
    echo "  -l, --loop               Бесконечный цикл (бесконечное воспроизведение pcap файлов с интервалом -i)"
    echo "  -t, --time <сек>         Воспроизведение в течение N сек (с интервалом -i)"
    echo "  -c, --count <число>      Количество повторений набора pcap файлов"
    echo "  --intf <интерфейс>       Интерфейс отправки трафика"
    echo "  --ip <IP>                Автоопределение интерфейса и MAC-адреса по IP с внесением изменений в pcap"

    print_header "РЕЖИМЫ СКОРОСТИ"
    echo "  --topspeed               Максимальная скорость"
    echo "  --pps <число>            Пакетов в секунду"
    echo "  --mbps <число>           Мбит/с"
    echo "  --multiplier <число>     Множитель оригинальной скорости"
    echo "  --oneatatime             По одному пакету (Enter)"

    print_header "ДОПОЛНИТЕЛЬНО"
    echo "  --stats                  Короткая статистика (Actual, Rated)"
    echo "  --limit <число>          Ограничить число пакетов"
    echo "  --pktlen                 Использовать реальную длину пакета (не рекомендуется!)"
    echo "  --truncate               Обрезать пакеты до стандартного MTU (1500) при воспроизведении"
    echo "  -v, --verbose            Детальный вывод пакетов (вывод tcpdump)"
    echo "  -q, --quiet              Тихий режим вывода статистики"

    print_header "ВСПОМОГАТЕЛЬНЫЕ КОМАНДЫ"
    echo "  -s, --show-interfaces    Показать интерфейсы"
    echo "  -a, --arp-resolve <IP>   Определить MAC по IP"
    echo "  -V, --version            Версия программы"
    echo "  -h, --help               Справка"

    echo
    echo "${BOLD}Примеры:${RESET}"
    echo "  ${CYAN}$0 --intf eth0 dir/ --pps 5000 -t 360 -i 10${RESET}"
    echo "  ${CYAN}$0 --intf eth0 dir/ --mbps 3 -l -i 0${RESET}"
    echo "  ${CYAN}$0 --intf eth0 file.pcap -c 5 --pps 5000 --truncate${RESET}"
    echo "  ${CYAN}$0 --ip 192.168.1.1 capture.pcap --topspeed${RESET}"
    echo "  ${CYAN}$0 --intf eth0 dir/ -l --stats${RESET}"
    echo "  ${CYAN}$0 --src-mac aa:bb:cc:dd:ee:ff --dst-mac=aa:bb:cc:dd:ee:ab file.pcap -k${RESET}"

    exit 0
}

resolve_mac_by_ip() {
    local target_ip="$1"
    local timeout=8
    [[ $target_ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]] || { print_error "Неверный IP: $target_ip"; return 1; }
    ip neigh del "$target_ip" dev "$INTERFACE" 2>/dev/null || true
    ping -c 3 -W 2 "$target_ip" >/dev/null 2>&1
    local attempts=0
    while [ $attempts -lt $timeout ]; do
        mac=$(ip neigh show "$target_ip" dev "$INTERFACE" 2>/dev/null | grep -oE 'lladdr [0-9a-f:]{17}' | awk '{print $2}')
        if [[ -n "$mac" && "$mac" != "(incomplete)" ]]; then
            echo "$mac"
            return 0
        fi
        sleep 1
        ((attempts++))
    done
    print_error "Не удалось определить MAC для IP $target_ip"
    return 1
}

auto_select_interface() {
    local target_ip="$1"
    local route=$(ip route get "$target_ip" 2>/dev/null)
    if [[ $? -eq 0 && -n "$route" ]]; then
        echo "$route" | grep -o 'dev [^ ]\+' | awk '{arg=$2} END {print arg}'
    fi
}

get_local_mac() { ip link show "$1" 2>/dev/null | grep -oE 'link/ether [0-9a-f:]{17}' | awk '{print $2}'; }
get_local_ip() { ip addr show "$1" 2>/dev/null | grep -oE 'inet [0-9]+\.[0-9]+\.[0-9]+\.[0-9]+' | awk '{print $2}' | head -1; }

validate_ip() {
    local ip="$1"
    if [[ $ip =~ ^[0-9]+\.[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
        IFS='.' read -r i1 i2 i3 i4 <<< "$ip"
        for octet in "$i1" "$i2" "$i3" "$i4"; do
            [[ ${#octet} -gt 1 && ${octet:0:1} == "0" ]] && return 1
            ((10#$octet < 0 || 10#$octet > 255)) && return 1
        done
        return 0
    fi
    return 1
}

validate_mac() { [[ $1 =~ ^([0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}$ ]]; }

show_interfaces() {
    printf "\n${BOLD}%-23s %-23s %-25s %-10s${RESET}\n" "Интерфейс" "IP-адрес" "MAC-адрес" "Состояние"
    echo "------------------------------------------------------------------"
    
    local interfaces=$(ip link show | grep -E '^[0-9]+:' | awk -F: '{print $2}' | sed 's/^[[:space:]]*//; s/@.*//')
    for intf in $interfaces; do
        local state=$(ip link show "$intf" 2>/dev/null | grep -q "state UP" && echo "up" || echo "down")
        local mac=$(get_local_mac "$intf" || echo "-")
        [ -z "$mac" ] && mac="-"
        
        local ip=""
        if [[ "$intf" == "lo" ]]; then
            ip="127.0.0.1"
            mac="00:00:00:00:00:00"
            state="up"
        else
            ip=$(get_local_ip "$intf" || echo "-")
            [ -z "$ip" ] && ip="-"
        fi
        
        local status_color="${RED}"
        [[ "$state" == "up" ]] && status_color=$'\033[1;32m'

        printf "%-14s %-18s %-23s" "$intf" "$ip" "$mac"
        
        local mac_len=${#mac}
        local target_width=10
        local pad_left=$(( ((target_width - ${#state}) / 2) - (23 - mac_len) + 3 ))
        [ $pad_left -lt 0 ] && pad_left=0

        printf "%${pad_left}s${status_color}%s${RESET}\n" "" "$state"
    done
    exit 0
}

create_ip_maps() {
    local pcap_file="$1"
    local maps=""
    [[ -f "$pcap_file" ]] || { echo ""; return; }
    [ -n "$NEW_SRC_IP" ] && maps="$maps --srcipmap=0.0.0.0/0:$NEW_SRC_IP/32"
    [ -n "$NEW_DST_IP" ] && maps="$maps --dstipmap=0.0.0.0/0:$NEW_DST_IP/32"
    echo "$maps"
}

process_file() {
    local input_file="$1" output_file="$2" keep_original="$3"
    [[ ! -s "$input_file" ]] && { log "${YELLOW}Предупреждение: Файл пустой: $input_file${RESET}"; return 1; }
    local cmd="tcprewrite"
    
    if [ -n "$SOURCE_MAC" ] && [ $CHANGE_SRC_MAC -eq 1 ]; then
        cmd="$cmd --enet-smac=$SOURCE_MAC"
    fi
    
    if [ -n "$DEST_MAC" ] && [ $CHANGE_DST_MAC -eq 1 ]; then
        cmd="$cmd --enet-dmac=$DEST_MAC"
    fi
    
    if [ $CHANGE_IP -eq 1 ]; then
        cmd="$cmd $(create_ip_maps "$input_file")"
    fi
    
    if [ $keep_original -eq 0 ]; then
        local temp="${input_file}.tmp"
        $cmd --infile="$input_file" --outfile="$temp" >/dev/null 2>&1
        if [ $? -eq 0 ]; then
            mv "$temp" "$input_file"
            return 0
        else
            $cmd --fixcsum --infile="$input_file" --outfile="$temp" >/dev/null 2>&1
            if [ $? -eq 0 ]; then
                mv "$temp" "$input_file"
                return 0
            else
                rm -f "$temp"
                return 1
            fi
        fi
    else
        $cmd --infile="$input_file" --outfile="$output_file" >/dev/null 2>&1
        if [ $? -ne 0 ]; then
            $cmd --fixcsum --infile="$input_file" --outfile="$output_file" >/dev/null 2>&1
        fi
        return $?
    fi
}

print_final_stats() {
    local sent_files=$1
    local real_time=$2
    local total_dur=$3
    
    local time_float=$(printf "%.2f" "$real_time" 2>/dev/null)
    if [ -z "$time_float" ]; then
        time_float=$(echo "scale=2; $real_time" | bc 2>/dev/null || echo "$real_time")
    fi
    
    if [ $QUIET -eq 1 ] || [ $SHORT_STATS -eq 1 ]; then
        if [ $TOTAL_PACKETS -gt 0 ] || [ $TOTAL_BYTES -gt 0 ]; then
            local avg_rate=$(echo "scale=1; $TOTAL_BYTES / $real_time" | bc 2>/dev/null || echo "0")
            local avg_mbps=$(echo "scale=3; $TOTAL_BYTES * 8 / $real_time / 1000000" | bc 2>/dev/null || echo "0")
            local avg_pps=$(echo "scale=0; $TOTAL_PACKETS / $real_time" | bc 2>/dev/null || echo "0")
            
            echo
            echo "Actual: $TOTAL_PACKETS packets ($TOTAL_BYTES bytes) sent in ${real_time} seconds"
            echo "Rated: $avg_rate Bps, $avg_mbps Mbps, $avg_pps pps"
            echo "Statistics for network device: $INTERFACE"
            echo "        Successful packets:        $TOTAL_PACKETS"
            echo "        Failed packets:            0"
            echo "        Truncated packets:         0"
            echo "        Retried packets (ENOBUFS): 0"
            echo "        Retried packets (EAGAIN):  0"
        fi
    fi
    
    print_header "ЗАВЕРШЕНО"
    print_key "Отправлено" "${GREEN}${sent_files}${RESET} $(decline_play $sent_files)"
    print_key "Время" "${YELLOW}${time_float} сек${RESET}"
    echo "${CYAN}──────────────────────────────────────────────────────────────${RESET}"
}

play_files() {
    local files=("$@")
    local total=${#files[@]}
    [ $total -eq 0 ] && { print_error "Нет файлов для воспроизведения"; return; }

    if [ -n "$INTERFACE" ]; then
        if ! ip link show "$INTERFACE" &>/dev/null; then
            print_error "Интерфейс $INTERFACE не существует в системе."
            exit 1
        fi
        
        if ! ip link show "$INTERFACE" 2>/dev/null | grep -q "UP"; then
            print_error "Интерфейс $INTERFACE находится в состоянии DOWN. Тест отменен."
            exit 1
        fi
    fi

    local repeat_count=$PLAY_COUNT
    [ $repeat_count -lt 1 ] && repeat_count=1
    local use_duration=0
    [ $PLAY_TIME -gt 0 ] && use_duration=1

    local loop_opt=""
    
    if [ $LOOP_MODE -eq 1 ] && [ $use_duration -eq 0 ] && [ $INTERVAL -eq 0 ]; then
        loop_opt=""
    fi

    local duration_opt=""
    [ $use_duration -eq 1 ] && duration_opt="--duration=$PLAY_TIME"

    if [ $TOPSPEED -eq 1 ]; then
        SPEED_OPT="--topspeed"
    elif [ -n "$PPS" ]; then
        SPEED_OPT="--pps=$PPS"
    elif [ -n "$MBPS" ]; then
        SPEED_OPT="--mbps=$MBPS"
    elif [ -n "$MULTIPLIER" ]; then
        SPEED_OPT="--multiplier=$MULTIPLIER"
    elif [ $ONEATATIME -eq 1 ]; then
        SPEED_OPT="--oneatatime"
    else
        SPEED_OPT=""
    fi

    local common_opts=""
    [ $PKTLEN -eq 1 ] && common_opts="$common_opts --pktlen"
    [ -n "$LIMIT" ] && common_opts="$common_opts --limit=$LIMIT"
    if [ $VERBOSE -eq 1 ]; then
        common_opts="$common_opts -v"
    fi
    if [ $QUIET -eq 1 ] && [ $VERBOSE -eq 0 ]; then
        common_opts="$common_opts -q"
    fi

    local intf_opts=""
    [ -n "$INTERFACE" ] && intf_opts=(-i "$INTERFACE")

    print_header "ПАРАМЕТРЫ ВОСПРОИЗВЕДЕНИЯ"
    
    print_key "Файлов" "$total"
    print_key "Интерфейс" "${INTERFACE:-${YELLOW}авто${RESET}}"
    
    if [ $TOPSPEED -eq 1 ]; then
        print_key "Скорость" "${GREEN}максимальная${RESET}"
    elif [ -n "$PPS" ]; then
        print_key "Скорость" "${GREEN}${PPS} pps${RESET}"
    elif [ -n "$MBPS" ]; then
        local mbps_float=$(printf "%.2f" "$MBPS" 2>/dev/null)
        if [ -z "$mbps_float" ]; then
            mbps_float=$(echo "scale=2; $MBPS" | bc 2>/dev/null || echo "$MBPS")
        fi
        print_key "Скорость" "${GREEN}${mbps_float} Mbps${RESET}"
    elif [ -n "$MULTIPLIER" ]; then
        local multiplier_float=$(printf "%.2f" "$MULTIPLIER" 2>/dev/null)
        if [ -z "$multiplier_float" ]; then
            multiplier_float=$(echo "scale=2; $MULTIPLIER" | bc 2>/dev/null || echo "$MULTIPLIER")
        fi
        print_key "Скорость" "${GREEN}${multiplier_float}-кратная${RESET}"
    elif [ $ONEATATIME -eq 1 ]; then
        print_key "Скорость" "${YELLOW}по одному${RESET}"
    else
        print_key "Скорость" "оригинальная"
    fi
    
    if [ $use_duration -eq 1 ] && [ $LOOP_MODE -eq 1 ]; then
        print_key "Повторов" "${MAGENTA}∞ бесконечный${RESET}"
        if [ $INTERVAL -gt 0 ]; then
            print_key "Интервал" "${CYAN}${INTERVAL} сек${RESET}"
        fi
    elif [ $use_duration -eq 1 ]; then
        if [ $INTERVAL -eq 0 ]; then
            print_key "Режим" "${YELLOW}по времени (${PLAY_TIME} сек, без интервалов)${RESET}"
        else
            print_key "Режим" "${YELLOW}по времени (${PLAY_TIME} сек, интервал ${INTERVAL} сек)${RESET}"
        fi
    elif [ $LOOP_MODE -eq 1 ]; then
        print_key "Повторов" "${MAGENTA}∞ бесконечный${RESET}"
        if [ $INTERVAL -gt 0 ]; then
            print_key "Интервал" "${CYAN}${INTERVAL} сек${RESET}"
        fi
    else
        if [ $repeat_count -gt 0 ]; then
            print_key "Повторов" "${CYAN}$repeat_count${RESET}"
            print_key "Интервал" "${CYAN}${INTERVAL} сек${RESET}"
        fi
    fi
    
    [ $TRUNCATE -eq 1 ] && print_key "" "${YELLOW}truncate MTU 1500${RESET}"
    
    echo

    START_TOTAL_TIME=$(date +%s.%N)
    local start_total=$START_TOTAL_TIME
    local total_dur=0
    local sent=0

    local file_timeout=30
    
    if [ $PKTLEN -eq 1 ]; then
        file_timeout=20
    fi

    if [ $use_duration -eq 1 ]; then
        if [ $INTERVAL -eq 0 ] 2>/dev/null || [ $INTERVAL -eq 0 ]; then
            local end_time=$(echo "$start_total + $PLAY_TIME" | bc)
            local iter_num=1
            
            while true; do
                [ $INTERRUPTED -eq 1 ] && break
                
                local current_time=$(date +%s.%N)
                if [ $(echo "$current_time >= $end_time" | bc) -eq 1 ]; then
                    break
                fi
                
                local file_idx=0
                for file in "${files[@]}"; do
                    [ $INTERRUPTED -eq 1 ] && break 2
                    
                    ((file_idx++))
                    
                    current_time=$(date +%s.%N)
                    if [ $(echo "$current_time >= $end_time" | bc) -eq 1 ]; then
                        break 2
                    fi
                    
                    local full_path="$file"
                    print_file "$full_path" "(файл $file_idx/$total, повтор $iter_num)"
                    
                    local remaining=$(echo "$end_time - $current_time" | bc)
                    if [ $(echo "$remaining <= 0" | bc) -eq 1 ]; then
                        break 2
                    fi
                    
                    local start=$(date +%s.%N)
                    local replay_bin="tcpreplay"
                    [ $TRUNCATE -eq 1 ] && replay_bin="tcpreplay-edit --mtu-trunc --mtu=1500"
                    
                    local timeout_sec=$file_timeout
                    if [ $(echo "$remaining < $timeout_sec" | bc) -eq 1 ]; then
                        timeout_sec=$remaining
                    fi
                    
                    local cmd="$replay_bin ${intf_opts[@]} $SPEED_OPT $common_opts \"$file\""
                    local output
                    local packets=""
                    local bytes=""
                    local rc=0
                    
                    if [ $ONEATATIME -eq 1 ]; then
                        local temp_file=$(mktemp)
                        $replay_bin "${intf_opts[@]}" $SPEED_OPT $common_opts "$file" 2>&1 | tee "$temp_file"
                        rc=$?
                        packets=$(cat "$temp_file" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                        bytes=$(cat "$temp_file" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                        rm -f "$temp_file"
                    elif [ $VERBOSE -eq 1 ]; then
                        timeout $timeout_sec bash -c "$cmd" 2>&1 | grep -E '^[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+|IP|ARP|TCP|UDP|ICMP' | grep -v 'reading from file' | grep -v 'tcpdump:' | grep -v 'User interrupt'
                        rc=$?
                        if [ $rc -eq 0 ] && [ $SHORT_STATS -eq 1 ]; then
                            output=$(bash -c "$cmd" 2>&1)
                            packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                            bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                        fi
                    elif [ $QUIET -eq 1 ]; then
                        if [ $SHORT_STATS -eq 1 ]; then
                            output=$(timeout $timeout_sec bash -c "$cmd" 2>&1)
                            if [ -n "$output" ]; then
                                echo "$output" | grep -E "Actual:|Rated:" | head -20
                                packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                                bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                            fi
                            rc=$?
                        else
                            timeout $timeout_sec bash -c "$cmd" >/dev/null 2>&1
                            rc=$?
                            if [ $rc -eq 0 ] && [ $SHORT_STATS -eq 1 ]; then
                                output=$(bash -c "$cmd" 2>&1)
                                packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                                bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                            fi
                        fi
                    else
                        if [ $SHORT_STATS -eq 1 ]; then
                            output=$(timeout $timeout_sec bash -c "$cmd" 2>&1)
                            if [ -n "$output" ]; then
                                echo "$output" | grep -E "Actual:|Rated:" | head -20
                                packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                                bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                            fi
                            rc=$?
                        else
                            timeout $timeout_sec bash -c "$cmd"
                            rc=$?
                            if [ $rc -eq 0 ] && [ $SHORT_STATS -eq 1 ]; then
                                output=$(bash -c "$cmd" 2>&1)
                                packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                                bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                            fi
                        fi
                    fi
                    
                    local dur=$(echo "$(date +%s.%N) - $start" | bc)
                    total_dur=$(echo "$total_dur + $dur" | bc)
                    
                    if [ $rc -eq 124 ] || [ $rc -eq 137 ]; then
                        if [ $QUIET -eq 0 ] && [ $ONEATATIME -eq 0 ]; then
                            print_error "Таймаут ($timeout_sec сек) - файл пропущен"
                        fi
                    elif [ $rc -eq 0 ]; then
                        ((sent++))
                        TOTAL_SENT_FILES=$sent
                        TOTAL_ELAPSED_DUR=$(echo "$TOTAL_ELAPSED_DUR + $dur" | bc)
                        if [ -n "$packets" ] && [ -n "$bytes" ]; then
                            TOTAL_PACKETS=$((TOTAL_PACKETS + packets))
                            TOTAL_BYTES=$((TOTAL_BYTES + bytes))
                        fi
                    else
                        if [ $QUIET -eq 0 ] && [ $ONEATATIME -eq 0 ]; then
                            print_error "ошибка $rc - файл пропущен"
                        fi
                    fi
                    
                    current_time=$(date +%s.%N)
                    if [ $(echo "$current_time >= $end_time" | bc) -eq 1 ]; then
                        break 2
                    fi
                    
                    if [ $ONEATATIME -eq 0 ] && [ $file_idx -lt $total ]; then
                        if [ $INTERVAL -gt 0 ]; then
                            local sleep_time=$INTERVAL
                            local next_start=$(echo "$current_time + $sleep_time" | bc)
                            
                            if [ $(echo "$next_start >= $end_time" | bc) -eq 1 ]; then
                                break 2
                            fi
                            
                            if [ $QUIET -eq 0 ]; then
                                echo "${DIM}Пауза ${INTERVAL} сек...${RESET}"
                                echo
                                sleep $sleep_time
                            else
                                sleep $sleep_time
                            fi
                        else
                            if [ $QUIET -eq 0 ]; then
                                echo
                            fi
                        fi
                        
                        current_time=$(date +%s.%N)
                        if [ $(echo "$current_time >= $end_time" | bc) -eq 1 ]; then
                            break 2
                        fi
                    fi
                done
                
                [ $INTERRUPTED -eq 1 ] && break
                
                ((iter_num++))
                
                current_time=$(date +%s.%N)
                if [ $(echo "$current_time >= $end_time" | bc) -eq 1 ]; then
                    break
                fi
                
                if [ $ONEATATIME -eq 0 ] && [ $INTERVAL -gt 0 ]; then
                    local sleep_time=$INTERVAL
                    local next_start=$(echo "$current_time + $sleep_time" | bc)
                    
                    if [ $(echo "$next_start >= $end_time" | bc) -eq 1 ]; then
                        break
                    fi
                    
                    if [ $QUIET -eq 0 ]; then
                        echo "${DIM}Пауза ${INTERVAL} сек...${RESET}"
                        echo
                        sleep $sleep_time
                    else
                        sleep $sleep_time
                    fi
                fi
            done
            
            local dur=$(echo "$(date +%s.%N) - $start_total" | bc)
            :
        else
            local end_time=$(echo "$start_total + $PLAY_TIME" | bc)
            local iter_num=1
            
            while true; do
                [ $INTERRUPTED -eq 1 ] && break
                
                local current_time=$(date +%s.%N)
                if [ $(echo "$current_time >= $end_time" | bc) -eq 1 ]; then
                    break
                fi
                
                local file_idx=0
                for file in "${files[@]}"; do
                    [ $INTERRUPTED -eq 1 ] && break 2
                    
                    ((file_idx++))
                    
                    current_time=$(date +%s.%N)
                    if [ $(echo "$current_time >= $end_time" | bc) -eq 1 ]; then
                        break 2
                    fi
                    
                    local full_path="$file"
                    print_file "$full_path" "(файл $file_idx/$total, повтор $iter_num)"
                    
                    local remaining=$(echo "$end_time - $current_time" | bc)
                    if [ $(echo "$remaining <= 0" | bc) -eq 1 ]; then
                        break 2
                    fi
                    
                    local start=$(date +%s.%N)
                    local replay_bin="tcpreplay"
                    [ $TRUNCATE -eq 1 ] && replay_bin="tcpreplay-edit --mtu-trunc --mtu=1500"
                    
                    local timeout_sec=$file_timeout
                    if [ $(echo "$remaining < $timeout_sec" | bc) -eq 1 ]; then
                        timeout_sec=$remaining
                    fi
                    
                    local cmd="$replay_bin ${intf_opts[@]} $SPEED_OPT $common_opts \"$file\""
                    local output
                    local packets=""
                    local bytes=""
                    local rc=0
                    
                    if [ $ONEATATIME -eq 1 ]; then
                        local temp_file=$(mktemp)
                        $replay_bin "${intf_opts[@]}" $SPEED_OPT $common_opts "$file" 2>&1 | tee "$temp_file"
                        rc=$?
                        packets=$(cat "$temp_file" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                        bytes=$(cat "$temp_file" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                        rm -f "$temp_file"
                    elif [ $VERBOSE -eq 1 ]; then
                        timeout $timeout_sec bash -c "$cmd" 2>&1 | grep -E '^[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+|IP|ARP|TCP|UDP|ICMP' | grep -v 'reading from file' | grep -v 'tcpdump:' | grep -v 'User interrupt'
                        rc=$?
                        if [ $rc -eq 0 ] && [ $SHORT_STATS -eq 1 ]; then
                            output=$(bash -c "$cmd" 2>&1)
                            packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                            bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                        fi
                    elif [ $QUIET -eq 1 ]; then
                        if [ $SHORT_STATS -eq 1 ]; then
                            output=$(timeout $timeout_sec bash -c "$cmd" 2>&1)
                            if [ -n "$output" ]; then
                                echo "$output" | grep -E "Actual:|Rated:" | head -20
                                packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                                bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                            fi
                            rc=$?
                        else
                            timeout $timeout_sec bash -c "$cmd" >/dev/null 2>&1
                            rc=$?
                            if [ $rc -eq 0 ] && [ $SHORT_STATS -eq 1 ]; then
                                output=$(bash -c "$cmd" 2>&1)
                                packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                                bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                            fi
                        fi
                    else
                        if [ $SHORT_STATS -eq 1 ]; then
                            output=$(timeout $timeout_sec bash -c "$cmd" 2>&1)
                            if [ -n "$output" ]; then
                                echo "$output" | grep -E "Actual:|Rated:" | head -20
                                packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                                bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                            fi
                            rc=$?
                        else
                            timeout $timeout_sec bash -c "$cmd"
                            rc=$?
                            if [ $rc -eq 0 ] && [ $SHORT_STATS -eq 1 ]; then
                                output=$(bash -c "$cmd" 2>&1)
                                packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                                bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                            fi
                        fi
                    fi
                    
                    local dur=$(echo "$(date +%s.%N) - $start" | bc)
                    total_dur=$(echo "$total_dur + $dur" | bc)
                    
                    if [ $rc -eq 124 ] || [ $rc -eq 137 ]; then
                        if [ $QUIET -eq 0 ] && [ $ONEATATIME -eq 0 ]; then
                            print_error "Таймаут ($timeout_sec сек) - файл пропущен"
                        fi
                    elif [ $rc -eq 0 ]; then
                        ((sent++))
                        TOTAL_SENT_FILES=$sent
                        TOTAL_ELAPSED_DUR=$(echo "$TOTAL_ELAPSED_DUR + $dur" | bc)
                        if [ -n "$packets" ] && [ -n "$bytes" ]; then
                            TOTAL_PACKETS=$((TOTAL_PACKETS + packets))
                            TOTAL_BYTES=$((TOTAL_BYTES + bytes))
                        fi
                    else
                        if [ $QUIET -eq 0 ] && [ $ONEATATIME -eq 0 ]; then
                            print_error "ошибка $rc - файл пропущен"
                        fi
                    fi
                    
                    current_time=$(date +%s.%N)
                    if [ $(echo "$current_time >= $end_time" | bc) -eq 1 ]; then
                        break 2
                    fi
                    
                    if [ $ONEATATIME -eq 0 ] && [ $file_idx -lt $total ]; then
                        if [ $INTERVAL -gt 0 ]; then
                            local sleep_time=$INTERVAL
                            local next_start=$(echo "$current_time + $sleep_time" | bc)
                            
                            if [ $(echo "$next_start >= $end_time" | bc) -eq 1 ]; then
                                break 2
                            fi
                            
                            if [ $QUIET -eq 0 ]; then
                                echo "${DIM}Пауза ${INTERVAL} сек...${RESET}"
                                echo
                                sleep $sleep_time
                            else
                                sleep $sleep_time
                            fi
                        else
                            if [ $QUIET -eq 0 ]; then
                                echo
                            fi
                        fi
                        
                        current_time=$(date +%s.%N)
                        if [ $(echo "$current_time >= $end_time" | bc) -eq 1 ]; then
                            break 2
                        fi
                    fi
                done
                
                [ $INTERRUPTED -eq 1 ] && break
                
                ((iter_num++))
                
                current_time=$(date +%s.%N)
                if [ $(echo "$current_time >= $end_time" | bc) -eq 1 ]; then
                    break
                fi
                
                if [ $ONEATATIME -eq 0 ] && [ $INTERVAL -gt 0 ]; then
                    local sleep_time=$INTERVAL
                    local next_start=$(echo "$current_time + $sleep_time" | bc)
                    
                    if [ $(echo "$next_start >= $end_time" | bc) -eq 1 ]; then
                        break
                    fi
                    
                    if [ $QUIET -eq 0 ]; then
                        echo "${DIM}Пауза ${INTERVAL} сек...${RESET}"
                        echo
                        sleep $sleep_time
                    else
                        sleep $sleep_time
                    fi
                fi
            done
            
            local dur=$(echo "$(date +%s.%N) - $start_total" | bc)
            :
        fi
    else
        if [ $LOOP_MODE -eq 1 ]; then
            local cycle=1
            while true; do
                [ $INTERRUPTED -eq 1 ] && break
                
                local file_idx=0
                for file in "${files[@]}"; do
                    [ $INTERRUPTED -eq 1 ] && break 2
                    
                    ((file_idx++))
                    local full_path="$file"
                    print_file "$full_path" "(файл $file_idx/$total, повтор $cycle)"
                    
                    local start=$(date +%s.%N)
                    local replay_bin="tcpreplay"
                    [ $TRUNCATE -eq 1 ] && replay_bin="tcpreplay-edit --mtu-trunc --mtu=1500"
                    
                    local cmd="$replay_bin ${intf_opts[@]} $SPEED_OPT $common_opts \"$file\""
                    local output
                    local packets=""
                    local bytes=""
                    local rc=0
                    
                    if [ $ONEATATIME -eq 1 ]; then
                        local temp_file=$(mktemp)
                        $replay_bin "${intf_opts[@]}" $SPEED_OPT $common_opts "$file" 2>&1 | tee "$temp_file"
                        rc=$?
                        packets=$(cat "$temp_file" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                        bytes=$(cat "$temp_file" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                        rm -f "$temp_file"
                    elif [ $VERBOSE -eq 1 ]; then
                        bash -c "$cmd" 2>&1 | grep -E '^[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+|IP|ARP|TCP|UDP|ICMP' | grep -v 'reading from file' | grep -v 'tcpdump:' | grep -v 'User interrupt'
                        rc=${PIPESTATUS[0]}
                        if [ $rc -eq 0 ] && [ $SHORT_STATS -eq 1 ]; then
                            output=$(bash -c "$cmd" 2>&1)
                            packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                            bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                        fi
                    elif [ $QUIET -eq 1 ]; then
                        if [ $SHORT_STATS -eq 1 ]; then
                            output=$(bash -c "$cmd" 2>&1)
                            if [ -n "$output" ]; then
                                echo "$output" | grep -E "Actual:|Rated:" | head -20
                                packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                                bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                            fi
                            rc=$?
                        else
                            bash -c "$cmd" >/dev/null 2>&1
                            rc=$?
                            if [ $rc -eq 0 ] && [ $SHORT_STATS -eq 1 ]; then
                                output=$(bash -c "$cmd" 2>&1)
                                packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                                bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                            fi
                        fi
                    else
                        if [ $SHORT_STATS -eq 1 ]; then
                            output=$(bash -c "$cmd" 2>&1)
                            if [ -n "$output" ]; then
                                echo "$output" | grep -E "Actual:|Rated:" | head -20
                                packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                                bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                            fi
                            rc=$?
                        else
                            bash -c "$cmd"
                            rc=$?
                            if [ $rc -eq 0 ] && [ $SHORT_STATS -eq 1 ]; then
                                output=$(bash -c "$cmd" 2>&1)
                                packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                                bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                            fi
                        fi
                    fi
                    
                    local dur=$(echo "$(date +%s.%N) - $start" | bc)
                    total_dur=$(echo "$total_dur + $dur" | bc)
                    
                    if [ $rc -eq 124 ] || [ $rc -eq 137 ]; then
                        if [ $QUIET -eq 0 ] && [ $ONEATATIME -eq 0 ]; then
                            print_error "Таймаут ($file_timeout сек) - файл пропущен"
                        fi
                    elif [ $rc -eq 0 ]; then
                        ((sent++))
                        TOTAL_SENT_FILES=$sent
                        TOTAL_ELAPSED_DUR=$(echo "$TOTAL_ELAPSED_DUR + $dur" | bc)
                        if [ -n "$packets" ] && [ -n "$bytes" ]; then
                            TOTAL_PACKETS=$((TOTAL_PACKETS + packets))
                            TOTAL_BYTES=$((TOTAL_BYTES + bytes))
                        fi
                    else
                        if [ $QUIET -eq 0 ] && [ $ONEATATIME -eq 0 ]; then
                            print_error "ошибка $rc - файл пропущен"
                        fi
                    fi
                    
                    if [ $ONEATATIME -eq 0 ] && [ $file_idx -lt $total ]; then
                        if [ $INTERVAL -gt 0 ]; then
                            if [ $QUIET -eq 0 ]; then
                                echo "${DIM}Пауза ${INTERVAL} сек...${RESET}"
                                echo
                                sleep $INTERVAL
                            else
                                sleep $INTERVAL
                            fi
                        else
                            if [ $QUIET -eq 0 ]; then
                                echo
                            fi
                        fi
                    fi
                done
                
                [ $INTERRUPTED -eq 1 ] && break
                
                if [ $ONEATATIME -eq 0 ] && [ $INTERVAL -gt 0 ]; then
                    if [ $QUIET -eq 0 ]; then
                        echo "${DIM}Пауза ${INTERVAL} сек...${RESET}"
                        echo
                        sleep $INTERVAL
                    else
                        sleep $INTERVAL
                    fi
                fi
                ((cycle++))
            done
        else
            for ((rep=1; rep<=repeat_count; rep++)); do
                [ $INTERRUPTED -eq 1 ] && break
                
                local file_idx=0
                for file in "${files[@]}"; do
                    [ $INTERRUPTED -eq 1 ] && break 2
                    
                    ((file_idx++))
                    local full_path="$file"
                    print_file "$full_path" "(файл $file_idx/$total, повтор $rep)"
                    
                    local start=$(date +%s.%N)
                    local replay_bin="tcpreplay"
                    [ $TRUNCATE -eq 1 ] && replay_bin="tcpreplay-edit --mtu-trunc --mtu=1500"
                    
                    local cmd="$replay_bin ${intf_opts[@]} $SPEED_OPT $common_opts \"$file\""
                    local output
                    local packets=""
                    local bytes=""
                    local rc=0
                    
                    if [ $ONEATATIME -eq 1 ]; then
                        local temp_file=$(mktemp)
                        $replay_bin "${intf_opts[@]}" $SPEED_OPT $common_opts "$file" 2>&1 | tee "$temp_file"
                        rc=$?
                        packets=$(cat "$temp_file" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                        bytes=$(cat "$temp_file" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                        rm -f "$temp_file"
                    elif [ $VERBOSE -eq 1 ]; then
                        bash -c "$cmd" 2>&1 | grep -E '^[0-9]{2}:[0-9]{2}:[0-9]{2}\.[0-9]+|IP|ARP|TCP|UDP|ICMP' | grep -v 'reading from file' | grep -v 'tcpdump:' | grep -v 'User interrupt'
                        rc=${PIPESTATUS[0]}
                        if [ $rc -eq 0 ] && [ $SHORT_STATS -eq 1 ]; then
                            output=$(bash -c "$cmd" 2>&1)
                            packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                            bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                        fi
                    elif [ $QUIET -eq 1 ]; then
                        if [ $SHORT_STATS -eq 1 ]; then
                            output=$(bash -c "$cmd" 2>&1)
                            if [ -n "$output" ]; then
                                echo "$output" | grep -E "Actual:|Rated:" | head -20
                                packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                                bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                            fi
                            rc=$?
                        else
                            bash -c "$cmd" >/dev/null 2>&1
                            rc=$?
                            if [ $rc -eq 0 ] && [ $SHORT_STATS -eq 1 ]; then
                                output=$(bash -c "$cmd" 2>&1)
                                packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                                bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                            fi
                        fi
                    else
                        if [ $SHORT_STATS -eq 1 ]; then
                            output=$(bash -c "$cmd" 2>&1)
                            if [ -n "$output" ]; then
                                echo "$output" | grep -E "Actual:|Rated:" | head -20
                                packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                                bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                            fi
                            rc=$?
                        else
                            bash -c "$cmd"
                            rc=$?
                            if [ $rc -eq 0 ] && [ $SHORT_STATS -eq 1 ]; then
                                output=$(bash -c "$cmd" 2>&1)
                                packets=$(echo "$output" | grep -oP 'Actual: \K\d+(?= packets)' | head -1)
                                bytes=$(echo "$output" | grep -oP '\((\d+) bytes\)' | head -1 | grep -oP '\d+')
                            fi
                        fi
                    fi
                    
                    local dur=$(echo "$(date +%s.%N) - $start" | bc)
                    total_dur=$(echo "$total_dur + $dur" | bc)
                    
                    if [ $rc -eq 124 ] || [ $rc -eq 137 ]; then
                        if [ $QUIET -eq 0 ] && [ $ONEATATIME -eq 0 ]; then
                            print_error "Таймаут ($file_timeout сек) - файл пропущен"
                        fi
                    elif [ $rc -eq 0 ]; then
                        ((sent++))
                        TOTAL_SENT_FILES=$sent
                        TOTAL_ELAPSED_DUR=$(echo "$TOTAL_ELAPSED_DUR + $dur" | bc)
                        if [ -n "$packets" ] && [ -n "$bytes" ]; then
                            TOTAL_PACKETS=$((TOTAL_PACKETS + packets))
                            TOTAL_BYTES=$((TOTAL_BYTES + bytes))
                        fi
                    else
                        if [ $QUIET -eq 0 ] && [ $ONEATATIME -eq 0 ]; then
                            print_error "ошибка $rc - файл пропущен"
                        fi
                    fi
                    
                    if [ $ONEATATIME -eq 0 ] && [ $file_idx -lt $total ]; then
                        if [ $INTERVAL -gt 0 ]; then
                            if [ $QUIET -eq 0 ]; then
                                echo "${DIM}Пауза ${INTERVAL} сек...${RESET}"
                                echo
                                sleep $INTERVAL
                            else
                                sleep $INTERVAL
                            fi
                        else
                            if [ $QUIET -eq 0 ]; then
                                echo
                            fi
                        fi
                    fi
                done
                
                if [ $ONEATATIME -eq 0 ] && [ $rep -lt $repeat_count ]; then
                    if [ $INTERVAL -gt 0 ]; then
                        if [ $QUIET -eq 0 ]; then
                            echo "${DIM}Пауза ${INTERVAL} сек...${RESET}"
                            echo
                            sleep $INTERVAL
                        else
                            sleep $INTERVAL
                        fi
                    else
                        if [ $QUIET -eq 0 ]; then
                            echo
                        fi
                    fi
                fi
            done
        fi
    fi

    if [ $INTERRUPTED -eq 0 ]; then
        local real_time=$(echo "$(date +%s.%N) - $start_total" | bc)
        print_final_stats "$sent" "$real_time" "$total_dur"
    fi
}

SOURCE_MAC=""
DEST_MAC=""
SOURCE_IP=""
DEST_IP=""
NEW_SRC_IP=""
NEW_DST_IP=""
KEEP_ORIGINAL=0
INTERVAL=5
LOOP_MODE=0
PLAY_TIME=0
PLAY_COUNT=1
INTERFACE=""
TARGET_IP=""
INPUT_PATH=""
CHANGE_SRC_MAC=0
CHANGE_DST_MAC=0
CHANGE_IP=0
SHOW_INTERFACES=0
ARP_RESOLVE_MODE=0
PLAY_MODE=0
TOPSPEED=0
PPS=""
MBPS=""
MULTIPLIER=""
ONEATATIME=0
UNIQUE_IP=0
UNIQUE_IP_LOOPS=""
UNIQUE_MAC=0
UNIQUE_PORTS=0
FLOW_EXPIRY=""
NO_FLOW_STATS=0
SHORT_STATS=0
LIMIT=""
PKTLEN=0
TRUNCATE=0
CACHEFILE=""
DUAL_MODE=0
VERBOSE=0
QUIET=0
PARAMS=()
VALIDATION_ERROR=0

INTERRUPTED=0
START_TOTAL_TIME=0
TOTAL_SENT_FILES=0
TOTAL_ELAPSED_DUR=0
TOTAL_PACKETS=0
TOTAL_BYTES=0

cleanup_on_interrupt() {
    INTERRUPTED=1
    
    local real_time=$(echo "$(date +%s.%N) - $START_TOTAL_TIME" | bc)
    
    if [ $TOTAL_SENT_FILES -gt 0 ]; then
        print_final_stats "$TOTAL_SENT_FILES" "$real_time" "$TOTAL_ELAPSED_DUR"
    fi
    
    exit 130
}

trap cleanup_on_interrupt SIGINT

while [[ $# -gt 0 ]]; do
    case $1 in
        -V|--version)
            echo "Attack Replay $VERSION"
            exit 0
            ;;
        --src-mac=*)
            tmp="${1#*=}"
            if validate_mac "$tmp"; then
                SOURCE_MAC="$tmp"
                CHANGE_SRC_MAC=1
            else
                echo "${YELLOW}Некорректный MAC источника: $tmp${RESET}"
                VALIDATION_ERROR=1
            fi
            shift
            ;;
        --src-mac)
            if [[ -n "$2" ]]; then
                tmp="$2"
                if validate_mac "$tmp"; then
                    SOURCE_MAC="$tmp"
                    CHANGE_SRC_MAC=1
                    shift 2
                else
                    echo "${YELLOW}Некорректный MAC источника: $tmp${RESET}"
                    VALIDATION_ERROR=1
                    shift 2
                fi
            else
                error "--src-mac требует значение"
                exit 1
            fi
            ;;
        --dst-mac=*)
            tmp="${1#*=}"
            if validate_mac "$tmp"; then
                DEST_MAC="$tmp"
                CHANGE_DST_MAC=1
            else
                echo "${YELLOW}Некорректный MAC назначения: $tmp${RESET}"
                VALIDATION_ERROR=1
            fi
            shift
            ;;
        --dst-mac)
            if [[ -n "$2" ]]; then
                tmp="$2"
                if validate_mac "$tmp"; then
                    DEST_MAC="$tmp"
                    CHANGE_DST_MAC=1
                    shift 2
                else
                    echo "${YELLOW}Некорректный MAC назначения: $tmp${RESET}"
                    VALIDATION_ERROR=1
                    shift 2
                fi
            else
                error "--dst-mac требует значение"
                exit 1
            fi
            ;;
        --src-ip=*)
            tmp="${1#*=}"
            if validate_ip "$tmp"; then
                NEW_SRC_IP="$tmp"
                CHANGE_IP=1
            else
                echo "${YELLOW}Некорректный IP источника: $tmp${RESET}"
                VALIDATION_ERROR=1
            fi
            shift
            ;;
        --src-ip)
            if [[ -n "$2" ]]; then
                tmp="$2"
                if validate_ip "$tmp"; then
                    NEW_SRC_IP="$tmp"
                    CHANGE_IP=1
                    shift 2
                else
                    echo "${YELLOW}Некорректный IP источника: $tmp${RESET}"
                    VALIDATION_ERROR=1
                    shift 2
                fi
            else
                error "--src-ip требует значение"
                exit 1
            fi
            ;;
        --dst-ip=*)
            tmp="${1#*=}"
            if validate_ip "$tmp"; then
                NEW_DST_IP="$tmp"
                CHANGE_IP=1
            else
                echo "${YELLOW}Некорректный IP назначения: $tmp${RESET}"
                VALIDATION_ERROR=1
            fi
            shift
            ;;
        --dst-ip)
            if [[ -n "$2" ]]; then
                tmp="$2"
                if validate_ip "$tmp"; then
                    NEW_DST_IP="$tmp"
                    CHANGE_IP=1
                    shift 2
                else
                    echo "${YELLOW}Некорректный IP назначения: $tmp${RESET}"
                    VALIDATION_ERROR=1
                    shift 2
                fi
            else
                error "--dst-ip требует значение"
                exit 1
            fi
            ;;
        --truncate)
            TRUNCATE=1
            shift
            ;;
        -k|--keep-original)
            KEEP_ORIGINAL=1
            shift
            ;;
        -i|--interval)
            INTERVAL="$2"
            PLAY_MODE=1
            shift 2
            ;;
        -l|--loop)
            LOOP_MODE=1
            PLAY_MODE=1
            shift
            ;;
        -t|--time)
            PLAY_TIME="$2"
            PLAY_MODE=1
            shift 2
            ;;
        -c|--count)
            PLAY_COUNT="$2"
            PLAY_MODE=1
            shift 2
            ;;
        --intf)
            INTERFACE="$2"
            PLAY_MODE=1
            shift 2
            ;;
        --ip)
            TARGET_IP="$2"
            PLAY_MODE=1
            shift 2
            ;;
        --topspeed)
            TOPSPEED=1
            PLAY_MODE=1
            shift
            ;;
        --pps)
            PPS="$2"
            PLAY_MODE=1
            shift 2
            ;;
        --mbps)
            MBPS="$2"
            PLAY_MODE=1
            shift 2
            ;;
        --multiplier)
            MULTIPLIER="$2"
            PLAY_MODE=1
            shift 2
            ;;
        --oneatatime)
            ONEATATIME=1
            PLAY_MODE=1
            shift
            ;;
        --stats)
            SHORT_STATS=1
            PLAY_MODE=1
            shift
            ;;
        --limit)
            LIMIT="$2"
            PLAY_MODE=1
            shift 2
            ;;
        --pktlen)
            PKTLEN=1
            PLAY_MODE=1
            shift
            ;;
        --cachefile)
            CACHEFILE="$2"
            PLAY_MODE=1
            shift 2
            ;;
        --dual)
            DUAL_MODE=1
            PLAY_MODE=1
            shift
            ;;
        -v|--verbose)
            VERBOSE=1
            PLAY_MODE=1
            shift
            ;;
        -q|--quiet)
            QUIET=1
            PLAY_MODE=1
            shift
            ;;
        -s|--show-interfaces)
            SHOW_INTERFACES=1
            shift
            ;;
        -a|--arp-resolve)
            ARP_RESOLVE_MODE=1
            TARGET_IP="$2"
            shift 2
            ;;
        -h|--help)
            show_help
            ;;
        -*)
            error "Неизвестный параметр: $1"
            show_help
            ;;
        *)
            PARAMS+=("$1")
            shift
            ;;
    esac
done
if [ ${#PARAMS[@]} -eq 0 ] && [ $SHOW_INTERFACES -eq 0 ] && [ $ARP_RESOLVE_MODE -eq 0 ] && [ $PLAY_MODE -eq 0 ] && [ $CHANGE_SRC_MAC -eq 0 ] && [ $CHANGE_DST_MAC -eq 0 ] && [ $CHANGE_IP -eq 0 ]; then
    show_help
fi

if [ $SHOW_INTERFACES -eq 1 ]; then
    show_interfaces
fi

if [ $ARP_RESOLVE_MODE -eq 1 ]; then
    INTERFACE=$(auto_select_interface "$TARGET_IP") || { error "Не удалось определить интерфейс для $TARGET_IP"; show_interfaces; }
    ip link show "$INTERFACE" | grep -q "state UP" || { ip link set "$INTERFACE" up; sleep 1; }
    
    mac=$(resolve_mac_by_ip "$TARGET_IP" 2>/dev/null)
    
    if [[ "$mac" =~ ^[0-9a-f:]{17}$ ]]; then
        echo "IP: $TARGET_IP, MAC: $(echo "$mac" | tr 'A-Z' 'a-z')"
    else
        echo "[${RED}ERROR${RESET}] Не удалось определить MAC для IP ${MAGENTA}$TARGET_IP${RESET}"
    fi
    exit 0
fi

if [ ${#PARAMS[@]} -eq 0 ]; then
    show_help
fi

INPUT_PATH="${PARAMS[0]}"
INPUT_PATH="${INPUT_PATH//\\/}"

if [ ! -e "$INPUT_PATH" ]; then
    error "Путь '$INPUT_PATH' не существует."
    exit 1
fi

if [ $VALIDATION_ERROR -eq 1 ]; then
    exit 1
fi

if [ -z "$INTERFACE" ] && [ $CHANGE_SRC_MAC -eq 0 ] && [ $CHANGE_DST_MAC -eq 0 ] && [ $CHANGE_IP -eq 0 ] && [ $PLAY_MODE -eq 0 ]; then
    error "Не указан интерфейс для отправки. Используйте --intf <интерфейс>"
    echo
    show_interfaces
    exit 1
fi

if [ -n "$TARGET_IP" ]; then
    CHANGE_DST_MAC=1
    PLAY_MODE=1
    auto_intf=$(auto_select_interface "$TARGET_IP") || { error "Не удалось найти интерфейс для $TARGET_IP"; exit 1; }
    INTERFACE=${INTERFACE:-$auto_intf}
    ip link show "$INTERFACE" | grep -q "state UP" || { ip link set "$INTERFACE" up; sleep 1; }
    DEST_MAC=$(resolve_mac_by_ip "$TARGET_IP")
    if [ $? -ne 0 ]; then
        exit 1
    fi
    if [ $CHANGE_SRC_MAC -eq 0 ]; then
        SOURCE_MAC=$(get_local_mac "$INTERFACE")
        if [ -z "$SOURCE_MAC" ]; then
            error "Не удалось получить MAC интерфейса $INTERFACE"
            exit 1
        fi
        CHANGE_SRC_MAC=1
    fi
    SOURCE_IP=$(get_local_ip "$INTERFACE")
    DEST_IP="$TARGET_IP"
fi

check_dependencies

print_edit_params() {
    [ $CHANGE_SRC_MAC -eq 1 ] && printf "  %-25s %s\n" "Source MAC" "${GREEN}$SOURCE_MAC${RESET}"
    [ $CHANGE_DST_MAC -eq 1 ] && printf "  %-25s %s\n" "Destination MAC" "${GREEN}$DEST_MAC${RESET}"
    [ $CHANGE_IP -eq 1 ] && {
        [ -n "$NEW_SRC_IP" ] && printf "  %-25s %s\n" "Source IP" "${GREEN}$NEW_SRC_IP${RESET}"
        [ -n "$NEW_DST_IP" ] && printf "  %-25s %s\n" "Destination IP" "${GREEN}$NEW_DST_IP${RESET}"
    }
    
    if [ $KEEP_ORIGINAL -eq 1 ]; then
        printf "  %-30s %s\n" "Режим" "${YELLOW}сохранение оригиналов${RESET}"
    else
        printf "  %-30s %s\n" "Режим" "${YELLOW}изменение оригиналов${RESET}"
    fi
}

if [ -f "$INPUT_PATH" ]; then
    [[ "$INPUT_PATH" != *.pcap && "$INPUT_PATH" != *.pcapng ]] && { error "Файл должен иметь расширение .pcap или .pcapng"; exit 1; }
    
    processed_files=()
    success=0
    failed=0
    total_files=1
    
    if [ $CHANGE_SRC_MAC -eq 1 ] || [ $CHANGE_DST_MAC -eq 1 ] || [ $CHANGE_IP -eq 1 ]; then
        print_header "РЕДАКТИРОВАНИЕ PCAP"
        print_edit_params
        
        echo "Начинается редактирование ${CYAN}1${RESET} $(decline_edit 1)"
        echo
        
        base=$(basename "$INPUT_PATH")
        printf "${CYAN}▶${RESET} ${BOLD}%s${RESET} " "$base"
        
        if [ $KEEP_ORIGINAL -eq 1 ]; then
            outdir=$(dirname "$INPUT_PATH")
            filename="${base%.*}"
            ext="${base##*.}"
            rand_id=$(printf "%05d%05d" $((RANDOM % 100000)) $((RANDOM % 100000)))
            
            out="$outdir/${filename}_${rand_id}.${ext}"
            if process_file "$INPUT_PATH" "$out" 1; then
                processed_files+=("$out")
                ((success++))
                echo "${GREEN}✓${RESET}"
                echo
                echo "Отредактированный файл был сохранен в $out"
            else
                ((failed++))
                echo "${RED}✗${RESET}"
            fi
        else
            if process_file "$INPUT_PATH" "" 0; then
                processed_files+=("$INPUT_PATH")
                ((success++))
                echo "${GREEN}✓${RESET}"
                echo
                echo "Отредактированный файл был сохранен в $INPUT_PATH"
            else
                ((failed++))
                echo "${RED}✗${RESET}"
            fi
        fi
    else
        processed_files+=("$INPUT_PATH")
    fi
    
    if [ $PLAY_MODE -eq 1 ]; then
        if [ ${#processed_files[@]} -gt 0 ]; then
            play_files "${processed_files[@]}"
        fi
    else
        if [ $CHANGE_SRC_MAC -eq 1 ] || [ $CHANGE_DST_MAC -eq 1 ] || [ $CHANGE_IP -eq 1 ]; then
            failed_color="${GREEN}"
            [ $failed -gt 0 ] && failed_color="${RED}"
            echo "Редактирование завершено. Обработано: ${GREEN}$success${RESET}, Ошибок: ${failed_color}$failed${RESET}"
            exit 0
        else
            print_error "Не указан режим воспроизведения. Используйте -i, -l, -t или -c"
            show_help
        fi
    fi

elif [ -d "$INPUT_PATH" ]; then
    files=()
    while IFS= read -r -d '' file; do
        files+=("$file")
    done < <(find "$INPUT_PATH" -maxdepth 1 \( -name "*.pcap" -o -name "*.pcapng" \) -type f -print0 | sort -z)
    
    if [ ${#files[@]} -eq 0 ]; then
        error "Нет pcap-файлов в директории."
        exit 0
    fi
    
    processed_files=()
    success=0
    failed=0
    total_files=${#files[@]}
    
    if [ $CHANGE_SRC_MAC -eq 1 ] || [ $CHANGE_DST_MAC -eq 1 ] || [ $CHANGE_IP -eq 1 ]; then
        print_header "РЕДАКТИРОВАНИЕ PCAP"
        print_edit_params
        
        echo "Начинается редактирование ${CYAN}$total_files${RESET} $(decline_edit $total_files)"
        
        if [ $KEEP_ORIGINAL -eq 1 ]; then
            dir_id=$(printf "%010d" $((RANDOM % 1000000000)))
            outdir="${INPUT_PATH%/}/edited_${dir_id}"
            mkdir -p "$outdir"
            echo "Создана директория для результатов: $outdir"
            echo
        fi
        
        for file in "${files[@]}"; do
            base=$(basename "$file")
            printf "${CYAN}▶${RESET} ${BOLD}%s${RESET} " "$base"
            
            if [ $KEEP_ORIGINAL -eq 1 ]; then
                outfile="$outdir/$base"
                
                if [ -f "$outfile" ]; then
                    filename="${base%.*}"
                    ext="${base##*.}"
                    outfile="$outdir/${filename}_copy.${ext}"
                fi
                
                if process_file "$file" "$outfile" 1; then
                    processed_files+=("$outfile")
                    ((success++))
                    echo "${GREEN}✓${RESET}"
                else
                    ((failed++))
                    echo "${RED}✗${RESET}"
                fi
            else
                if process_file "$file" "" 0; then
                    processed_files+=("$file")
                    ((success++))
                    echo "${GREEN}✓${RESET}"
                else
                    ((failed++))
                    echo "${RED}✗${RESET}"
                fi
            fi
        done
        
        echo
        
        if [ $success -gt 0 ]; then
            if [ $KEEP_ORIGINAL -eq 1 ]; then
                echo "Отредактированные файлы сохранены в $outdir"
            else
                echo "Отредактированные файлы сохранены в ${INPUT_PATH%/}/"
            fi
        fi
    else
        processed_files=("${files[@]}")
    fi
    
    if [ $PLAY_MODE -eq 1 ]; then
        if [ ${#processed_files[@]} -gt 0 ]; then
            play_files "${processed_files[@]}"
        fi
    else
        if [ $CHANGE_SRC_MAC -eq 1 ] || [ $CHANGE_DST_MAC -eq 1 ] || [ $CHANGE_IP -eq 1 ]; then
            failed_color="${GREEN}"
            [ $failed -gt 0 ] && failed_color="${RED}"
            echo "Редактирование завершено. Обработано: ${GREEN}$success${RESET}, Ошибок: ${failed_color}$failed${RESET}"
            exit 0
        else
            print_error "Не указан режим воспроизведения. Используйте -i, -l, -t или -c"
            show_help
        fi
    fi
else
    error "'$INPUT_PATH' — не файл и не директория."
    exit 1
fi
