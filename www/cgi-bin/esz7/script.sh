#!/bin/sh

BINDIR="/root/bin"

WWWDIR=$(readlink /var/www)
[ -z "$WWWDIR" ] && WWWDIR="/var/www"

MODE="ATLAS"
MODE_TITLE="ББИ II"
CFGNAME="atlas.cfg"
WITSCFGNAME="wits.cfg"
STATUSFNAME="esz7.sts"
TELEMETRYFNAME="stat.txt"
APPLOGFNAME="esz7.log"

if [ -f ${BINDIR}/.APS ]; then
    MODE="SIU"
    MODE_TITLE="Sensors Interface Unit"
    CFGNAME="siu.cfg"
fi

CFGFILE="${BINDIR}/${CFGNAME}"
WITSCFGFILE="${BINDIR}/${WITSCFGNAME}"
STATUSFILE="${BINDIR}/${STATUSFNAME}"
TELEMETRYFILE="${BINDIR}/${TELEMETRYFNAME}"
APPLOGFILE="/var/log/${APPLOGFNAME}"
WCPVERFILE="${WWWDIR}/cgi-bin/esz7/VERSION"

if [ -r "${WCPVERFILE}" ]; then
    TEXT=$(cat "${WCPVERFILE}")
    if [ ! -z "$TEXT" ]; then
        WCPVER_TITLE="$TEXT"
    fi
fi

log()
{
    local NN EE
    while [ $# -gt 0 ]; do
        case "$1" in
            -n) NN="-n"; shift ;;
            -e) EE="-e"; shift ;;
            *)  break ;;
        esac
    done

    if [ -f "${LOG_FILE_UPDATE}" ]; then
        FILE_SIZE=$(wc -c < "${LOG_FILE_UPDATE}" 2>/dev/null)
        if [ "${FILE_SIZE:-0}" -gt "${LOG_FILE_MAX_SIZE}" ]; then
            tail -c "${LOG_FILE_MAX_SIZE}" "${LOG_FILE_UPDATE}" > "${LOG_FILE_UPDATE}.tmp" 2>/dev/null
            mv -f "${LOG_FILE_UPDATE}.tmp" "${LOG_FILE_UPDATE}" 2>/dev/null
        fi
    fi

    echo $NN $EE "$*" >> "${LOG_FILE_UPDATE}"
}

get_app_uptime()
{
    APP_UPTIME=$(ps -o comm,etime | awk '$1 == "esz7" {printf "%s ", $2} END {print ""}')
}

get_system_time()
{
    DATE=$(date "+%d.%m.%Y %H:%M:%S")
    TIMEZONE=$(cat /etc/timezone 2>/dev/null || echo "UTC")
    SYS_TIME="$DATE &nbsp;&nbsp; [$TIMEZONE]"

    UPTIME=$(awk '{
        ts = int($1)
        if (ts < 86400) {
            printf "%02d:%02d:%02d", ts/3600, (ts%3600)/60, ts%60
        } else if (int(ts/2592000) == 0) {
            printf "%d дн %02d:%02d:%02d", (ts%2592000)/86400, ((ts%2592000)%86400)/3600, (((ts%2592000)%86400)%3600)/60, ((ts%2592000)%86400)%60
        } else {
            printf "%d мес %d дн %02d:%02d:%02d", ts/2592000, (ts%2592000)/86400, ((ts%2592000)%86400)/3600, (((ts%2592000)%86400)%3600)/60, ((ts%2592000)%86400)%60
        }
    }' /proc/uptime)
}

set_system_time()
{
    # запрос на синхронизацию времени
    echo "Content-type: text/plain; charset=utf-8"
    echo ""

    touch ${LOG_FILE_SETUP}
    tail -c ${LOG_FILE_MAX_SIZE} ${LOG_FILE_SETUP} > ${LOG_FILE_SETUP}.tmp
    mv ${LOG_FILE_SETUP}.tmp ${LOG_FILE_SETUP} >/dev/null 2>&1

    get_system_time
    echo "${DATE}" >> ${LOG_FILE_SETUP}

    # Очищаем от потенциально опасных символов (оставляем только цифры и точку)
    RAW_TIME=$(echo "$QUERY_STRING" | sed 's/set_time=//')
    CLEAN_TIME=$(echo "$RAW_TIME" | sed 's/[^0-9.]//g')

    # Проверяем, что строка не пустая и соответствует базовой длине формата
    if [ -z "$CLEAN_TIME" ] || [ ${#CLEAN_TIME} -lt 12 ]; then
        echo "ERR_INVALID_FORMAT"
        return
    fi
    if date -s "$CLEAN_TIME" >/dev/null 2>&1; then
        echo "${DATE} SET DATE/TIME: $CLEAN_TIME" >> ${LOG_FILE_SETUP}
        hwclock -w -u >/dev/null 2>&1
        # Возвращаем новое время обратно
        get_system_time
        echo "$DATE<br>[$TIMEZONE]"
    else
        echo "${DATE} SET DATE/TIME TO '$CLEAN_TIME' FAILED" >> ${LOG_FILE_SETUP}
        echo "ERR_SET_DATE_FAILED"
    fi
}

get_versions()
{
    V_SERIAL=$(cat /etc/serialno 2>/dev/null || echo "N/A")
    V_SYSTEM=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d"=" -f 2 | sed s/\"//g || echo "Unknown")
    V_OSNAME=$(uname -a | sed 's/PREEMPT/PREEMPT<br>/')
    V_FW_NAME=$(cat /sys/firmware/devicetree/base/amba/esz7@43c00000/name 2>/dev/null | tr -d '\n\r"')
    V_FW_VER=$(cat /sys/firmware/devicetree/base/amba/esz7@43c00000/version 2>/dev/null | tr -d '\n\r"')
    V_MOD_VER=$(cat /sys/devices/soc0/amba/43c00000.esz7/version 2>/dev/null | grep Module)
    V_ROOTFS_VER=$(head -n 1 /etc/rootfs.issue)

    V_FMWVER="DeviceTree: ${V_FW_NAME} ${V_FW_VER}<br>${V_MOD_VER}<br>Rootfs: ${V_ROOTFS_VER}"

    local STR=$(${BINDIR}/esz7 --version 2>/dev/null)
    V_APP1VER=$(echo "$STR" | cut -d'[' -f 1 | tr -d '\r\n')
    [ -z "$V_APP1VER" ] && V_APP1VER="[no firmware]"

    if which script; then 
        STR=$(script -q -c "${BINDIR}/esz7-term -v" /dev/null)
    else
        STR=$(${BINDIR}/esz7-term -v 2>/dev/null)
    fi
    V_APP2VER=$(echo "$STR" | cut -d '[' -f 1 | tr -d '\n\r')

    V_WCPVER="---"
    [ -f "${WCPVERFILE}" ] && V_WCPVER=$(cat ${WCPVERFILE} 2>/dev/null | tr -d '\n\r')
}

api_get_status()
{
    get_system_time
    local TIME="$DATE<br>[$TIMEZONE]"
    get_versions

    #local SERIAL=$(cat /etc/serialno 2>/dev/null || echo "N/A")
    #local SYSTEM=$(cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d"=" -f 2 | sed s/\"//g || echo "Unknown")
    #local OSNAME=$(uname -a | sed 's/PREEMPT/PREEMPT<br>/')
    #local FW_NAME=$(cat /sys/firmware/devicetree/base/amba/esz7@43c00000/name 2>/dev/null | tr -d '\n\r"')
    #local FW_VER=$(cat /sys/firmware/devicetree/base/amba/esz7@43c00000/version 2>/dev/null | tr -d '\n\r"')
    #local MOD_VER=$(cat /sys/devices/soc0/amba/43c00000.esz7/version 2>/dev/null | grep Module)
    #local ROOTFS_VER=$(head -n 1 /etc/rootfs.issue)
    #local FMWVER="DeviceTree: ${FW_VER} ${FW_VER}<br>Linux ${MOD_VER}<br>Rootfs: ${ROOTFS_VER}"
    #local IPADR=$(ip addr show 2>/dev/null | awk '/inet / {print$2}' | cut -d '/' -f 1 | head -n 1)
    #local STR=$(${BINDIR}/esz7 --version 2>/dev/null)
    #local APPVER=$(echo "$STR" | cut -d'[' -f 1 | tr -d '\n')
    #[ -z "$APPVER" ] && APPVER="[no firmware]"

    IPADR=$(ip addr show 2>/dev/null | awk '/inet / {print$2}' | cut -d '/' -f 1 | head -n 1)

    local STATUS="STOP"
    local STR="$(ps a | grep -E '(/| )esz7$' | awk '{print $1}')"
    if [ ! -z "${STR}" ]; then
        STATUS="RUN"
        STR=$(${BINDIR}/esz7-ctrl status 2>/dev/null)
        local TASKS=$(echo "$STR" | sed ':a;N;$!ba;s/\n/<br>/g')
    fi

    echo "Content-type: application/json"
    echo "Cache-Control: no-cache"
    echo ""
    echo ""
    echo "{"
    echo "  \"mode\":    \"${MODE}\",  "
    echo "  \"time\":    \"${TIME}\",  "
    echo "  \"uptime\":  \"${UPTIME}\","
    echo "  \"status\":  \"${STATUS}\","
    echo "  \"ipadr\":   \"${IPADR}\", "
    echo "  \"serial\":  \"${V_SERIAL}\","
    echo "  \"appver\":  \"${V_APP1VER}\","
    echo "  \"system\":  \"${V_SYSTEM}\","
    echo "  \"osname\":  \"${V_OSNAME}\","
    echo "  \"fmwver\":  \"${V_FMWVER}\","
    echo "  \"tasks\":   \"${TASKS}\", "
    echo "  \"cfgname\": \"${CFGNAME}\""
    echo "}"
}

api_get_setup()
{
    # читается вывод /bin/setup/ и формируется JSON-строка
    STR=$(setup)
    IP=$(echo   "$STR" | grep "ip:"    | awk '{print $2}')
    GW=$(echo   "$STR" | grep "gw:"    | awk '{print $2}')
    MAC=$(echo  "$STR" | grep "mac:"   | awk '{print $2}')
    SSH=$(echo  "$STR" | grep "ssh:"   | awk '{print $2}')
    FTP=$(echo  "$STR" | grep "ftp:"   | awk '{print $2}')
    HTTP=$(echo "$STR" | grep "http:"  | awk '{print $2}')
    LANG=$(echo "$STR" | grep "lang:"  | awk '{print $2}')
    SNO=$(echo  "$STR" | grep "serial:"| awk '{print $2}')

    echo "Content-type: application/json"
    echo "Cache-Control: no-cache"
    echo ""
    echo ""
    echo "{"
    echo "  \"ip\":   \"$IP\",  "
    echo "  \"mac\":  \"$MAC\", "
    echo "  \"gw\":   \"$GW\",  "
    echo "  \"ssh\":  \"$SSH\", "
    echo "  \"ftp\":  \"$FTP\", "
    echo "  \"http\": \"$HTTP\","
    echo "  \"lang\": \"$LANG\","
    echo "  \"sno\":  \"$SNO\"  "
    echo "}"
}

api_get_versions()
{
    get_versions
    echo "Content-Type: application/json"
    echo "Cache-Control: no-cache"
    echo ""
    echo ""
    echo "{"
    echo "  \"app_ver\": \"esz7.zip &nbsp;&nbsp;&nbsp;&nbsp; ${V_APP1VER}<br>esz7-term.zip ${V_APP2VER}\","
    echo "  \"wcp_ver\": \"wcp.zip<br>Web Control Panel Ver. ${V_WCPVER}\","
    echo "  \"fmw_ver\": \"xme072420.zip<br>${V_FMWVER}\""
    echo "}"
}

api_get_telemetry()
{
    get_app_uptime
    [ -z "$APP_UPTIME" ] && APP_UPTIME="---"

    ENC1="0"
    ENC2="0"
    SENT_OK="0"
    SENT_ER="0"

    if [ -r "${TELEMETRYFILE}" ]; then
        while IFS=' ' read -r key val1 val2 val3 $val4 $val5 $val6 $val7; do
            set -- $key $val1 $val2 $val3 $val4 $val5 $val6 $val7
            case "$1" in
                enc: )    ENC1="$2";    ENC2=$3     ;;
                sentok:)  SENT_OK="$2"; SENT_ER="$3"  ;;
                wits:)    WITS_OK="$2"; WITS_ER="$3"  ;;
                ch1avrg:) CH1AVRG="$3"; CH1AVRGV="$4" ;;
                ch2avrg:) CH2AVRG="$3"; CH2AVRGV="$4" ;;
                ch3avrg:) CH3AVRG="$3"; CH3AVRGV="$4" ;;
                ch4avrg:) CH4AVRG="$3"; CH4AVRGV="$4" ;;

                sendto1:) SEND1="$2 $3 $4 $5 $6 $7" ;;
                sendto2:) SEND2="$2 $3 $4 $5 $6 $7" ;;
                sendto3:) SEND3="$2 $3 $4 $5 $6 $7" ;;
            esac
        done < "${TELEMETRYFILE}"
    fi

    if [ -r "${STATUSFILE}" ]; then
        while IFS='=' read -r key val; do
            set -- $key $val
            case "$1" in
                dpt_delay) STATUS_DPTDELAY="$2 мс" ;;
                swap_ch12) STATUS_SWAPCH12="$2" ;;
            esac
        done < "${STATUSFILE}"

        [ "$STATUS_SWAPCH12" = "1" ] || [ "$STATUS_SWAPCH12" = "yes" ] && STATUS_SWAPCH12="[Да]" || STATUS_SWAPCH12="[Нет]"
    fi

    echo "Content-type: application/json"
    echo "Cache-Control: no-cache"
    echo ""
    echo ""
    echo "{"
    echo "  \"uptime\":   \"${APP_UPTIME}\","
    echo "  \"enc1\":     \"${ENC1}\","
    echo "  \"enc2\":     \"${ENC2}\","

    echo "  \"ch1avrg\":  \"${CH1AVRG}\","
    echo "  \"ch2avrg\":  \"${CH2AVRG}\","
    echo "  \"ch3avrg\":  \"${CH3AVRG}\","
    echo "  \"ch4avrg\":  \"${CH4AVRG}\","

    echo "  \"ch1avrgv\":  \"${CH1AVRGV}\","
    echo "  \"ch2avrgv\":  \"${CH2AVRGV}\","
    echo "  \"ch3avrgv\":  \"${CH3AVRGV}\","
    echo "  \"ch4avrgv\":  \"${CH4AVRGV}\","

    echo "  \"send1\":     \"${SEND1}\","
    echo "  \"send2\":     \"${SEND2}\","
    echo "  \"send3\":     \"${SEND3}\","

    echo "  \"sentok\":   \"${SENT_OK}\","
    echo "  \"senterr\":  \"${SENT_ER}\","
    echo "  \"witsok\":   \"${WITS_OK}\","
    echo "  \"witserr\":  \"${WITS_ER}\","
    echo "  \"dptdelay\": \"${STATUS_DPTDELAY}\","
    echo "  \"swapch12\": \"${STATUS_SWAPCH12}\" "
    echo "}"
}

api_get_protocol()
{
    CONTENT="[отсутствует]"
    if [ -r "${APPLOGFILE}" ]; then
        LINES=$(wc -l ${APPLOGFILE} | awk {'print $1'})
        CONTENT=$(tac ${APPLOGFILE} 2>/dev/null | sed ':a;N;$!ba;s/\n/\\n/g')
        #CONTENT=$(cat ${APPLOGFILE} 2>/dev/null)
    fi
    echo "Content-Type: text/plain; charset=application/json"
    echo ""
    echo ""
    echo "{"
    echo "  \"lines\":   \"${LINES}\","
    echo "  \"content\": \"${CONTENT}\" "
    echo "}"
}

api_save_setup()
{
    read -n "${CONTENT_LENGTH}" POST_DATA

    # Декодирование параметров (простая замена %XX символов, если требуется)
    # и получение переменные ip, gw, mac, ssh, ftp, http, lang, sno
    NEW_IP=$(echo   "$POST_DATA" | grep -oE 'ip=[^&]+'   | cut -d= -f2)
    NEW_GW=$(echo   "$POST_DATA" | grep -oE 'gw=[^&]+'   | cut -d= -f2)
    NEW_MAC=$(echo  "$POST_DATA" | grep -oE 'mac=[^&]+'  | cut -d= -f2 | sed 's/%3A/:/g') # замена url-encoded двоеточий
    NEW_SSH=$(echo  "$POST_DATA" | grep -oE 'ssh=[^&]+'  | cut -d= -f2)
    NEW_FTP=$(echo  "$POST_DATA" | grep -oE 'ftp=[^&]+'  | cut -d= -f2)
    NEW_HTTP=$(echo "$POST_DATA" | grep -oE 'http=[^&]+' | cut -d= -f2)
    NEW_LANG=$(echo "$POST_DATA" | grep -oE 'lang=[^&]+' | cut -d= -f2)
    NEW_SNO=$(echo  "$POST_DATA" | grep -oE 'sno=[^&]+'  | cut -d= -f2)

    setup \
        --ip   "$NEW_IP"   \
        --www \
        --gw   "$NEW_GW"   \
        --mac  "$NEW_MAC"  \
        --ssh  "$NEW_SSH"  \
        --ftp  "$NEW_FTP"  \
        --http "$NEW_HTTP" \
        --lang "$NEW_LANG" \
        --sno  "$NEW_SNO" >/dev/null 2>&1

    #echo "Content-Type: text/plain; charset=UTF-8"
    echo "Content-Type: text/plain"
    echo ""
    echo "SUCCESS"
}

api_save_config()
{
    if [ -n "$CONTENT_LENGTH" ] && [ "$CONTENT_LENGTH" -gt 0 ]; then
        POST_DATA=$(dd bs=1 count="$CONTENT_LENGTH" 2>/dev/null)
    fi

    # переводим POST_DATA в DECODED_DATA
    DECODED_DATA=$(printf '%b' $(echo "$POST_DATA" | sed 's/%/\\x/g'))
    # основные поля (NL - с новой строки выводить поле)
    if [ "$MODE" = "ATLAS" ]; then
        FIELDS="host1 port11 port12 NL host2 port21 port22 NL host3 port31 port32 NL wits_port"
    else
        FIELDS="ads_cmd_port ads_data_port NL ss_cmd_port ss_dats_port NL dtr_cmd_port dtr_data_port NL wits_port NL SystemUnits Decimal"
    fi

    # временные файлы для сборки
    head="${CFGFILE}.head"
    body="${CFGFILE}.body"
    tail="${CFGFILE}.tail"
    all_params="${CFGFILE}.params"

    # разделение на части (head и tail)
    awk '/^#/ && !done { print; next } { done=1 }' "${CFGFILE}" > "${head}"
    awk '/DO NOT EDIT/ { done=1 } done { print }'  "${CFGFILE}" > "${tail}"

    # извлечение всех активных параметров из исходного body
    head_lines=$(wc -l < "${head}")
    awk -v skip="${head_lines}" '
        NR <= skip { next }
        /DO NOT EDIT/ { exit }
        /^[[:space:]]*#/ { next } 
        NF == 0 { next }
        {
            idx = index($0, "=")
            if (idx > 0) {
                key = substr($0, 1, idx - 1)
                rest = substr($0, idx + 1)
                gsub(/^[ \t]+|[ \t]+$/, "", key)
                gsub(/^[ \t]+/, "", rest)
                print key "=" rest
            }
        }' "${CFGFILE}" > "${all_params}"

    # сборка нового переупорядоченного body
    # сначала поля из списка FIELDS в строгом порядке
    > "${body}"
    for field in $FIELDS; do
        [ "$field" = "NL" ] && echo "" >> "${body}" && continue;
        line=$(grep "^${field}=" "${all_params}")
        if [ -n "$line" ]; then
            echo "$line" >> "${body}"
        else
            echo "${field}=" >> "${body}"
        fi
    done

    # добавление остальных полей, которых НЕ БЫЛО в списке FIELDS
    echo -e "\n#---\n" >> "${body}"
    while read -r line; do
        [ -z "$line" ] && continue
        case "$line" in
            \#*|"") continue ;;
        esac

        key="${line%%=*}"
        is_main=0
        for main_field in $FIELDS; do
            if [ "$key" = "$main_field" ]; then
                is_main=1
                break
            fi
        done

        if [ $is_main -eq 0 ]; then
            echo "$line" >> "${body}"
        fi
    done < "${all_params}"

    # обновление body из данных html-формы (decoded_data)
    echo "$DECODED_DATA" | tr '&' '\n' | while read -r pair; do
        [ -z "$pair" ] && continue
        key="${pair%%=*}"
        value="${pair#*=}"

        [ -z "$key" ] && continue
        [ "$key" = "action" ] && continue

        if [ "$key" = "proto_ver" ]; then
            if [ -z "$value" ]; then
                value="1"
            fi
        fi

        if grep -q "^${key}=" "${body}"; then
            if grep "^${key}=" "${body}" | grep -q "#"; then
                sed "s|^\(${key}=\)[^#]*\(.*\)|\1${value}\2|" "${body}" > "${body}.tmp"
            else
                sed "s|^\(${key}=\).*|\1${value}|" "${body}" > "${body}.tmp"
            fi
            mv "${body}.tmp" "${body}"
        else
            # если поля нет в body, но это валидный параметр — дописывается
            if [ "$MODE" = "ATLAS" ]; then
                case "$key" in
                    host1|port11|port12|host2|port21|port22|host3|port31|port32|wits_port|proto_ver)
                        echo "${key}=${value}" >> "${body}" ;;
                esac
            else
                case "$key" in
                    ads_cmd_port|ads_data_port|ss_cmd_port|ss_dats_port|dtr_cmd_port|dtr_data_port|wits_port|SystemUnits|Decimal)
                        echo "${key}=${value}" >> "${body}" ;;
                esac
            fi
        fi
    done

    # выравнивание комментариев (24 символа)
    awk -F= '
        NF == 0 || $0 == "" { print ""; next }
        /^[[:space:]]*#/ { print; next }
        {
            if (NF < 2) { print; next }
            idx = index($0, "#")
            if (idx > 0) {
                rest = substr($0, idx)
                idx_in_val = index($2, "#")
                val = substr($2, 1, idx_in_val - 1)
                rest = "        " rest
            } else {
                val = $2
                rest = ""
            }
            gsub(/^[ \t]+|[ \t]+$/, "", val)
            gsub(/^[ \t]+|[ \t]+$/, "", $1)
            left = $1 "=" val
            if (length(left) < 24) {
                printf "%-24s%s\n", left, rest
            } else {
                print left rest
            }
        }' "${body}" > "${body}.clean"
    mv "${body}.clean" "${body}"

    # сборка итогового файла и обновление даты 
    cat "${head}" "${body}" > "${CFGFILE}.new"
    echo "" >> "${CFGFILE}.new"
    cat "${tail}" >> "${CFGFILE}.new"

    current_date="$(date +%c)"
    awk -v d="# Updated: ${current_date}" '
    NR==1 {
        if ($0 ~ /^# *Updated:/) { print d; next } 
        else { print d; print $0; next }
    } 
    {print}' "${CFGFILE}.new" > "${CFGFILE}"

    # удаление временных файлов
    rm -f "${head}" "${body}" "${tail}" "${all_params}" "${CFGFILE}.new" >/dev/null 2>&1

    echo "Content-Type: text/plain"
    echo ""
    echo "SUCCESS"
}

api_save_adc_config()
{
    read -n "${CONTENT_LENGTH}" POST_DATA
    REF=$(echo "$POST_DATA" | grep -oE 'ref=[^&]+' | cut -d= -f2 | sed 's/%2C/./; s/,/./')

    cp -v "${CFGFILE}" "${CFGFILE}.bak" >/dev/null 2>&1
    if grep -q "^adc_ref=" "${CFGFILE}"; then
        sed "s/^adc_ref=.*/adc_ref=${REF}/" -i "${CFGFILE}"
    else
        echo "adc_ref=${REF}" >> "${CFGFILE}"
    fi

    echo "Content-Type: text/plain"
    echo ""
    echo "SUCCESS"
}

api_save_wits_config()
{
    read -n "${CONTENT_LENGTH}" POST_DATA

    WELLID=$(echo    "$POST_DATA" | grep -oE 'wits_wellid=[^&]+'  | cut -d= -f2 | sed 's/\+/_/g; s/%3A/_/g; s/%2C/_/g; s/,/_/g; s/\./_/g')
    RECID=$(echo     "$POST_DATA" | grep -oE 'wits_recid=[^&]+'   | cut -d= -f2)
    PS1_CODE=$(echo  "$POST_DATA" | grep -oE 'ps1_code=[^&]+'     | cut -d= -f2)
    PS2_CODE=$(echo  "$POST_DATA" | grep -oE 'ps2_code=[^&]+'     | cut -d= -f2)
    HKLD_CODE=$(echo "$POST_DATA" | grep -oE 'hkld_code=[^&]+'    | cut -d= -f2)
    ENC1_CODE=$(echo "$POST_DATA" | grep -oE 'enc1_code=[^&]+'    | cut -d= -f2)
    ENC2_CODE=$(echo "$POST_DATA" | grep -oE 'enc2_code=[^&]+'    | cut -d= -f2)


    local head="${WITSCFGFILE}.head"
    awk '/^#/ && !done { print; next } { done=1 }' "${WITSCFGFILE}" > "${head}"

    mv "$head" ${WITSCFGFILE}.new
    printf "rec01=%s\n"       "$WELLID"    >> ${WITSCFGFILE}.new
    printf "rec03=%s\n"       "$RECID"     >> ${WITSCFGFILE}.new
    printf "pressure1=%02d\n" "$PS1_CODE"  >> ${WITSCFGFILE}.new
    printf "pressure2=%02d\n" "$PS2_CODE"  >> ${WITSCFGFILE}.new
    printf "hookload=%02d\n"  "$HKLD_CODE" >> ${WITSCFGFILE}.new
    printf "encoder1=%02d\n"  "$ENC1_CODE" >> ${WITSCFGFILE}.new
    printf "encoder2=%02d\n"  "$ENC2_CODE" >> ${WITSCFGFILE}.new

    local current_date="$(date +%c)"
    awk -v d="# Updated: ${current_date}" '
    NR==1 {
        if ($0 ~ /^# *Updated:/) { print d; next } 
        else { print d; print $0; next }
    } 
    {print}' "${WITSCFGFILE}.new" > "${WITSCFGFILE}"

    rm -f "${WITSCFGFILE}.new" >/dev/null 2>&1

    echo "Content-Type: text/plain"
    echo ""
    echo "SUCCESS"
}

get_archive_format()
{
    TARGET_FILE="$1"

    if [ ! -f "$TARGET_FILE" ]; then
        echo "file not found"
        return
    fi

    # Читаются строго первые 8 байт. Опция -n 8 гарантирует,
    # что hexdump закроет файл сразу после прочтения.
    HEX=$(hexdump -n 8 -e '8/1 "%02x"' "$TARGET_FILE" 2>/dev/null)

    # # Запасной вариант, если hexdump вырезан из BusyBox
    # if [ -z "$HEX" ]; then
    #     HEX=$(od -A n -t x1 -N 8 "$TARGET_FILE" 2>/dev/null | tr -d ' \n')
    # fi

    case "$HEX" in
        504b0304*)      echo "zip"      ;;
        1f8b08*)        echo "tar.gz"   ;;
        425a68*)        echo "tar.bz2"  ;;
        377abcaf271c*)  echo "7z"       ;;
        526172211a07*)  echo "rar"      ;;
        *)              echo "unkn"     ;;
    esac
}

keep_last_files() 
{
    local MAX=$1
    local WORKDIR="$2"
    local PATTERN="$3"

    cmd="ls -rt1 $WORKDIR | grep -E \"^${PATTERN}\" | head -n -${MAX}"
    FILES=$(eval "$cmd")
    #log "FILES: $FILES"
    for file in $FILES; do
       rm -rf "$WORKDIR/$file" >/dev/null 2>&1
    done
    NUM=$(echo -n "$FILES" | wc -w)
    #log "$NUM"
    return $NUM
}


mount_uboot()
{
    # монтирование раздела загрузки
    local DIR="$1"
    if ! mount | grep "$DIR" >/dev/null 2>&1; then
        log "MOUNT:   $DIR"
        local TEXT=$(mount $DIR 2>&1)
        if [ $? -ne 0 ]; then
            msg="ERR_MOUNT_FAILED"
            echo "${msg}"
            log "$TEXT"
            log -e "${msg}\n"
            return 1
        fi
    fi
    return 0
}

umount_uboot()
{
    # демонтирование раздела загрузки
    local DIR="$1"
    if mount | grep "$DIR" >/dev/null 2>&1; then
        log "UMOUNT:  $DIR"
        TEXT="$(umount $DIR 2>&1)"
        if [ $? -ne 0 ]; then
            msg="ERR_UMOUNT_FAILED"
            echo "${msg}"
            log "$TEXT"
            log -e "${msg}\n"
            return 1
        fi
    fi
    return 0
}

save_binary()
{
    local FILENAME="$1"
    local TARGETFILE="$2"

    # имя временного файлв (с mime-заголовками и прочим)
    local RAWFILE="${STASHDIR}/${FILENAME}.raw"
    log "RAWFILE: $RAWFILE"

    # имя файла 'очищенного'
    TARGETFILE="${STASHDIR}/${TARGETFILE}.zip"

    # Читается бинарное тело POST-запроса заданной длины из стандартного ввода (stdin)
    log "LENGTH:  $(printf "%8d" $CONTENT_LENGTH)"
    head -c "$CONTENT_LENGTH" > "$RAWFILE"
    if [ ! -f "$RAWFILE" ]; then
        echo "ERR_FILE_NOT_SAVED"
        log "ERROR: $RAWFILE NOT SAVED"
        rm -f "$RAWFILE" >/dev/null 2>&1
        return 1
    fi

    local RAWFILE_SIZE=$(wc -c < "$RAWFILE")
    # ищется смещение первой пустой строки (конец заголовка)
    # переводится в десятичный вид
    local HEADER_SIZE=$(head -c 512 "$RAWFILE" | hexdump -v -e '/1 "%02x "' | awk '{
        idx = index($0, "0d 0a 0d 0a")
        if (idx > 0) {
            print (idx - 1) / 3 + 4
            exit
        }
    }')

    local BOUNDARY="${CONTENT_TYPE#*boundary=}"
    local BOUNDARY_LEN=$(printf "%s" "$BOUNDARY" | wc -c)
    local TAIL_SIZE=$((BOUNDARY_LEN + 8))
    local PAYLOAD_SIZE=$((RAWFILE_SIZE - HEADER_SIZE - TAIL_SIZE))
    local SKIP_LEN=$((HEADER_SIZE + 1))

    log "SIZE:    $(printf "%8d" $RAWFILE_SIZE)"
    log "HEADER:  $(printf "%8d" $HEADER_SIZE)"
    log "TAIL:    $(printf "%8d" $TAIL_SIZE)"
    log "PAYLOAD: $(printf "%8d" $PAYLOAD_SIZE)"

    tail -c +"${SKIP_LEN}" "${RAWFILE}" | head -c -"${TAIL_SIZE}" > "$TARGETFILE"
    log "SAVED:   $TARGETFILE"

    local CALCULATED_HASH=$(sha256sum -b "$TARGETFILE" | awk '{print $1}')
    log -n "HASH:    $CALCULATED_HASH - "
    if [ "$CALCULATED_HASH" != "$EXPECTED_HASH" ]; then
        msg="ERR_HASH_MISMATCH"
        echo "{msg}"
        log "WRONG"
        log -e "${msg}\n"
        rm -f "$RAWFILE" >/dev/null 2>&1
       return 1
    fi
    log "OK"
    rm -f "$RAWFILE" >/dev/null 2>&1
    SAVED_FILENAME="$TARGETFILE"
    return 0
}

update_app()
{
    local cmd msg TEXT
    UNPACK_DIR="$1"

    # проверка содержимого обновления
    TARGET_NAME=""
    if test -f "${UNPACK_DIR}/esz7"; then
        TARGET_NAME="esz7"
        SAMPLE=".serno_atlas"
    elif test -f "${UNPACK_DIR}/esz7-term"; then
        TARGET_NAME="esz7-term"
        SAMPLE="Firmware Vers:"
    fi

    if [ -z "${TARGET_NAME}" ]; then
        msg="ERR_UPDATE_NAME_WRONG"
        echo "${msg}"
        log -e "${msg}\n"
        return 1
    fi
    TARGET_FILE="${BINDIR}/${TARGET_NAME}"

    # контроль правильности файла
    NUM="$(strings "${UNPACK_DIR}/${TARGET_NAME}" | grep "${SAMPLE}" | wc -l)"
    if [ "$NUM" -ne 1 ]; then
        msg="ERR_UPDATE_CONTENT_WRONG"
        echo "${msg}"
        log -e "${msg} - signatures not found\n"
        return 1
    fi

    # сохранение предыдущей версии
    if [ -f "$TARGET_FILE" ]; then
        local DATE=$(date "+%Y%m%d-%H%M%S")
        BACKUPDIR="${STASHDIR}/${TARGET_NAME}-${DATE}"
        log "BACKUP:  $TARGET_FILE -> $BACKUPDIR"
        mkdir -p $BACKUPDIR >/dev/null 2>&1
        cmd="cp -f $TARGET_FILE $BACKUPDIR/ 2>&1"
        TEXT=$(eval "$cmd")
        if [ $? -ne 0 ]; then
            msg="ERR_BACKUP_FAILED"
            echo "${msg}"
            log "BACKUP:  $cmd"
            log "$TEXT"
            log -e "${msg}\n"
            return 1
        fi
        [ ! -z "$TEXT" ] && log "$TEXT"
    fi

    # удаление более 5-ти бэкапов
    keep_last_files 5 "${STASHDIR}" "${TARGET_NAME}-[0-9]{8}-[0-9]{4}"
    local NUM="$?"
    [ $NUM -ne 0 ] && log "BACKUP:  ${NUM} OLD RECORDS REMOVED"

    sync

    # замена текущей прошивки
    cmd="cp -fv ${UNPACK_DIR}/${TARGET_NAME} ${TARGET_FILE} 2>&1"
    TEXT=$(eval ${cmd})
    if [ $? -ne 0 ]; then
        msg="ERR_UPDATE_FAILED"
        echo "${msg}"
        log "UDPATE: $cmd"
        log "$TEXT"
        log -e "${msg}\n"
        return 1
    fi
    log "UPGRADE: $TEXT"

    TEXT=$(chmod -v 500 ${TARGET_FILE})
    log "$TEXT"
    echo "SUCCESS"
    return 0
}

update_wcp()
{
    local cmd msg local TEXT
    local UNPACK_DIR="$1"

    # проверка содержимого обновления
    local list="cgi-bin/esz7/control cgi-bin/esz7/VERSION favicon.ico index.html sha256.min.js logo-64.png"
    for f in $list ; do
        if ! test -f "${UNPACK_DIR}/${f}"; then
            msg="ERR_UPDATE_CONTENT_WRONG"
            echo "${msg}"
            log "NOT FOUND: ${UNPACK_DIR}/${f}"
            log "$(ls -la ${UNPACK_DIR})"
            log -e "${msg}\n"
            return 1
        fi
    done

    # сохранение предыдущей версии
    if [ -d "${WWWDIR}" ]; then
        local DATE=$(date "+%Y%m%d-%H%M%S")
        BACKUPDIR="${STASHDIR}/www-${DATE}"
        log "BACKUP:  $WWWDIR -> $BACKUPDIR"
        mkdir -p $BACKUPDIR >/dev/null 2>&1
        cmd="cp -rf $WWWDIR/* $BACKUPDIR 2>&1"
        TEXT=$(eval ${cmd})
        if [ $? -ne 0 ]; then
            msg="ERR_BACKUP_FAILED"
            echo "${msg}"
            log "BACKUP:  $cmd"
            log "$TEXT"
            log -e "${msg}\n"
            return 1
        fi
        [ ! -z "$TEXT" ] && log "$TEXT"
    fi
    sync

    # удаление более 5-ти бэкапов
    keep_last_files 5 "${STASHDIR}" "www-[0-9]{8}-[0-9]{4}"
    local NUM="$?"
    [ $NUM -ne 0 ] && log "BACKUP:  ${NUM} OLD RECORDS REMOVED"

    # замена текущей версии
    [ ! -d "${WWWDIR}" ] && log "$(mkdir -p ${WWWDIR} 2>&1)"
    rm -rfv ${WWWDIR}\* >/dev/null 2>&1
    log "UDGRADE: ${UNPACK_DIR} -> ${WWWDIR}"
    cmd="cp -rf ${UNPACK_DIR}/* ${WWWDIR} 2>&1"
    TEXT=$(eval ${cmd})
    if [ $? -ne 0 ]; then
        msg="ERR_UPDATE_FAILED"
        echo "${msg}"
        log "UDPATE: $cmd"
        log "$TEXT"
        log -e "${msg}\n"
        return 1
    fi
    [ ! -z "$TEXT" ] && log "$TEXT"

    find ${WWWDIR} -type f -exec chmod -v 600 {} \; >/dev/null 2>&1
    find ${WWWDIR} -type d -exec chmod -v 700 {} \; >/dev/null 2>&1
    log "$(chmod -v 0700 ${WWWDIR}/cgi-bin/esz7/control 2>&1)"
    echo "SUCCESS"
    return 0
}

update_firmware()
{
    local cmd msg local TEXT
    local UNPACK_DIR="$1"

    # проверка содержимого обновления
    local list="system.dtb uImage.bin uRootfs.image.gz boot.scr.mmc.bin boot.scr.qspi.bin boot.scr.sd.bin"
    for f in $list ; do
        if ! test -f "${UNPACK_DIR}/${f}"; then
            msg="ERR_UPDATE_CONTENT_WRONG"
            echo "${msg}"
            log "NOT FOUND: ${UNPACK_DIR}/${f}"
            log "$(ls -la ${UNPACK_DIR})"
            log -e "${msg}\n"
            return 1
        fi
    done

    local UBOOTDIR="/mnt/uboot"
    mount_uboot "$UBOOTDIR"
    [ $? -ne 0 ] && return 1

    # сохранение предыдущей версии
    local DATE=$(date "+%Y%m%d-%H%M%S")

    BACKUPDIR="${STASHDIR}/uboot-${DATE}"
    log "BACKUP:  $UBOOTDIR -> $BACKUPDIR"
    mkdir -p $BACKUPDIR >/dev/null 2>&1
    cmd="cp -rf ${UBOOTDIR}/* ${BACKUPDIR} 2>&1"
    TEXT=$(eval ${cmd})
    if [ $? -ne 0 ]; then
        msg="ERR_BACKUP_FAILED"
        echo "${msg}"
        log "BACKUP:  $cmd"
        log "$TEXT"
        log -e "${msg}\n"
        return 1
    fi
    [ ! -z "$TEXT" ] && log "$TEXT"
    sync

    # удаление более 5-ти бэкапов
    keep_last_files 5 "${STASHDIR}" "uboot-[0-9]{8}-[0-9]{4}"
    local NUM="$?"
    [ $NUM -ne 0 ] && log "BACKUP:  ${NUM} OLD RECORDS REMOVED"

    # замена текущей версии
    rm -rfv ${WWWDIR}\* >/dev/null 2>&1
    log "UDGRADE: $UNPACK_DIR -> $UBOOTDIR"
    cmd="cp -rf ${UNPACK_DIR}/* ${UBOOTDIR} 2>&1"
    TEXT=$(eval ${cmd})
    if [ $? -ne 0 ]; then
        msg="ERR_UPDATE_FAILED"
        echo "${msg}"
        log "UDPATE:  $cmd"
        log "$TEXT"
        log -e "${msg}\n"
        return 1
    fi
    [ ! -z "$TEXT" ] && log "$TEXT"
    sync

    # демонтирование раздела загрузки
    umount_uboot "$UBOOTDIR"
    [ $? -ne 0 ] && return 1
    log "REBOOT:  REQUIRED"

    echo "SUCCESS_FIRMWARE"
    return 0
}


#-----------------------------------------------------------
# Main()
#
# API РОУТЕР ДЛЯ AJAX
# Этот блок обрабатывает фоновые запросы и сразу завершает скрипт через exit 0
#

if echo "$QUERY_STRING" | grep -q "api_get_status"; then
    api_get_status
    exit 0
fi

if echo "$QUERY_STRING" | grep -q "api_get_versions"; then
    api_get_versions
    exit 0
fi

if echo "$QUERY_STRING" | grep -q "api_get_telemetry"; then
    api_get_telemetry
    exit 0
fi

if echo "$QUERY_STRING" | grep -q "api_get_protocol"; then
    api_get_protocol
    exit 0
fi

if echo "$QUERY_STRING" | grep -q "api_save_setup"; then
    api_save_setup
    exit 0
fi

if echo "$QUERY_STRING" | grep -q "api_get_setup"; then
    api_get_setup
    exit 0
fi

if echo "$QUERY_STRING" | grep -q "api_get_config_files"; then
    echo "Content-Type: text/plain; charset=UTF-8"
    echo ""
    cat "${CFGFILE}" 2>/dev/null
    exit 0
fi

if echo "$QUERY_STRING" | grep -q "api_get_adc_config"; then

    REF=$(cat "${CFGFILE}" 2>/dev/null | grep "adc_ref")
    [ -z "$REF" ] && REF="adc_ref=2.5"
    IFS='=' read -r key ref <<EOF
${REF}
EOF

    if [ -r "${TELEMETRYFILE}" ]; then
        SCALE=$(cat "${TELEMETRYFILE}" 2>/dev/null | grep "adcref")
        if [ ! -z "$SCALE" ]; then
            IFS=' ' read -r key val scale <<EOF
${SCALE}
EOF
            set -- $scale
            scale="$1"
        fi
    fi


    echo "Content-type: application/json"
    echo "Cache-Control: no-cache"
    echo ""
    echo ""
    echo "{"
    echo "  \"ref\": \"$ref\","
    echo "  \"scale\": \"$scale\""
    echo "}"
    exit 0
fi

if echo "$QUERY_STRING" | grep -q "api_get_wits_config"; then
    if [ ! -r ${WITSCFGFILE} ]; then
        current_date="$(date +%c)"
        cat > ${WITSCFGFILE} << EOF
# Created: ${current_date}
#
rec01=The Well
rec03=151
pressure1=
pressure2=
hookload=
encoder1=
encoder2=

EOF
    fi

    echo "Content-Type: text/plain; charset=UTF-8"
    echo ""
    cat "${WITSCFGFILE}" 2>/dev/null
    exit 0
fi


if echo "$QUERY_STRING" | grep -q "api_action_start"; then
    if ! "ps a | grep -E '(/| )esz7$' | grep -v grep" ; then
        ${BINDIR}/esz7-ctrl start >/dev/null 2>&1
    fi
    echo "Content-Type: text/plain"
    echo ""
    if ! "ps a | grep -E '(/| )esz7$' | grep -v grep" ; then
        echo "RUN"
    else
        echo "WAIT"
    fi
    exit 0
fi

if echo "$QUERY_STRING" | grep -q "api_action_restart"; then
    ${BINDIR}/esz7-ctrl restart >/dev/null 2>&1
    echo "Content-Type: text/plain"
    echo ""
    echo "RESTART"
    exit 0
fi

if echo "$QUERY_STRING" | grep -q "api_action_stop"; then
    ${BINDIR}/esz7-ctrl stop >/dev/null 2>&1
    echo "Content-Type: text/plain"
    echo ""
    echo "STOP"
    exit 0
fi

if echo "$QUERY_STRING" | grep -q "api_action_reboot"; then
    echo "Content-Type: text/plain"
    echo ""
    echo "REBOOTING"
    (sleep 1; reboot) &
    exit 0
fi

if echo "$QUERY_STRING" | grep -q "api_save_config"; then
    api_save_config
    exit 0
fi

if echo "$QUERY_STRING" | grep -q "api_save_adc_config"; then
    api_save_adc_config
    exit 0
fi

if echo "$QUERY_STRING" | grep -q "api_save_wits_config"; then
    api_save_wits_config
    exit 0
fi

if echo "$QUERY_STRING" | grep -q "set_time"; then
    set_system_time
    exit 0
fi

if echo "$QUERY_STRING" | grep -q "api_app_status"; then
    echo "Content-type: text/plain; charset=utf-8"
    echo ""
    STR=$(${BINDIR}/esz7-ctrl status 2>/dev/null)
    if [ ! -z "$STR" ]; then
        echo "RUNNING"
    else
        echo "STOPPED"
    fi
    exit 0
fi

if [ ! -z "$QUERY_STRING" ]; then
    UPLOAD_APP=$(echo "$QUERY_STRING" | grep "action=update_app")
    [ -z "${UPLOAD_APP}" ] && UPLOAD_WCP=$(echo "$QUERY_STRING" | grep "action=update_wcp")
    [ -z "${UPLOAD_WCP}" ] && UPLOAD_FMW=$(echo "$QUERY_STRING" | grep "action=update_firmware")
fi

if [ ! -z "${UPLOAD_APP}" ] || [ ! -z "${UPLOAD_WCP}" ] || [ ! -z "${UPLOAD_FMW}" ]; then

    LOG_FILE_UPDATE="/var/log/update.log"
    if [ ! -z "${UPLOAD_APP}" ]; then 
        LOG_FILE_UPDATE="/var/log/update_app.log"
    elif [ ! -z "${UPLOAD_WCP}" ]; then 
        LOG_FILE_UPDATE="/var/log/update_wcp.log"
    elif [ ! -z "${UPLOAD_FMW}" ]; then 
        LOG_FILE_UPDATE="/var/log/update_firmware.log"
    fi
    LOG_FILE_MAX_SIZE=$((1024 * 1024))
    get_system_time
    log -e "\n${DATE}"

    echo "Content-Type: text/html; charset=UTF-8"
    echo ""

    # проверка остановки текущего процесса

    STR="$(ps a | grep -E '(/| )esz7$' | awk '{print $1}')"
    if [ ! -z "$STR" ]; then
        echo "ERR_APP_NOT_STOP"
        exit 0
    fi

    UPLOADED_FILE_MAX_SIZE=$((1024 * 1024 * 50))
    if [ -z "$CONTENT_LENGTH" ] || [ "$CONTENT_LENGTH" -le 0 ]; then
        echo "ERR_EMPTY_CONTENT"
        exit 0
    fi
    if [ "$CONTENT_LENGTH" -gt "$UPLOADED_FILE_MAX_SIZE" ]; then
        echo "ERR_CONTENT_TOO_MUCH_SIZE"
        exit 0
    fi

    HASH=$(echo "$QUERY_STRING" | sed -n "s/.*expected_hash=\([^&]*\).*/\1/p")
    EXPECTED_HASH=$(echo "$HASH" | tr 'A-Z' 'a-z' | sed 's/[^a-f0-9]//g')
    if [ ${#EXPECTED_HASH} -ne 64 ]; then
        echo "ERR_BAD_EXPECTED_HASH"
        exit 0
    fi

    FNAME=$(echo "$QUERY_STRING" | sed -n "s/.*fn=\([^&]*\).*/\1/p")
    EXT="" ; [ "${FNAME%.*}" != "${FNAME}" ] && EXT="${FNAME##*.}"

    TARGETNAME = "a5ebaca"
    if [ ! -z "${UPLOAD_APP}" ]; then 
        STR=$(echo "$FNAME" | grep esz7-term)
        if [ ! -z "$STR" ]; then
            TARGETNAME="esz7-term"
        else
            STR=$(echo "$FNAME" | grep esz7)
            if [ ! -z "$STR" ]; then
                TARGETNAME="esz7"
            fi
        fi
    elif [ ! -z "${UPLOAD_WCP}" ]; then 
        TARGETNAME="w3controlpanel"
    elif [ ! -z "${UPLOAD_FMW}" ]; then 
        TARGETNAME="firmware"
    fi

    log "UPDATE:  ${FNAME}"

    STASHDIR="${BINDIR}/updates"
    mkdir -p "$STASHDIR"

    save_binary ${FNAME} ${TARGETNAME}
    [ $? -ne 0 ] && exit 0

    # проверка типа файла обновления
    FMT=$(get_archive_format "${SAVED_FILENAME}")
    if [ "$FMT" != "zip" ]; then
        msg="ERR_ARCH_FORMAT_WRONG"
        echo "${msg}"
        log "EXT:${EXT} FORMAT:${FMT} - BAD FORMAT"
        log -e "${msg}\n"
        exit 0
    fi

    if [ "$EXT" != "zip" ]; then
        msg"ERR_ARCH_EXT_WRONG"
        echo "${msg}"
        log -e "${msg}\n"
        exit 0
    fi

    # распаковка обновления
    UNPACK_DIR="${STASHDIR}/unpacked"
    # ls "$UNPACK_DIR" -tlp | grep '/$'  | head -n 1
    [ -d "$UNPACK_DIR" ] && rm -rf "$UNPACK_DIR" >/dev/null 2>&1
    log "UNPACK:  $SAVED_FILENAME"
    cmd="unzip -o -d ${UNPACK_DIR} ${SAVED_FILENAME} 2>&1"
    TEXT=$(eval ${cmd})
    if [ $? -ne 0 ]; then
        msg="ERR_UNPACK_FAILED"
        echo "${msg}"
        log "UNPACK:  $cmd"
        log "$TEXT"
        log -e "${msg}\n"
        rm -rf "${UNPACK_DIR}" >/dev/null 2>&1
        exit 0
    fi

    DIRNAME=$(ls ${UNPACK_DIR}/ -t1p | grep '/$'  | head -n 1 | sed 's/ /_/g')
    if [ ! -d "${UNPACK_DIR}/${DIRNAME}" ]; then
        msg="ERR_UNPACK_FAILED"
        echo "${msg}"
        log "NOT FOUND: ${UNPACK_DIR}/${DIRNAME}"
        log -e "${msg}\n"
        rm -rf "${UNPACK_DIR}" >/dev/null 2>&1
        exit 0
    fi
    log "READY:   ${SAVED_FILENAME}:${DIRNAME} -> ${UNPACK_DIR}"

    cmd="mv -f ${UNPACK_DIR}/${DIRNAME}/* ${UNPACK_DIR}/ >/dev/null 2>&1"
    TEXT=$(eval ${cmd})
    if [ $? -ne 0 ]; then
        msg="ERR_UNPACK_FAILED"
        echo "${msg}"
        log "UNPACK:  $cmd"
        log "$TEXT"
        log -e "${msg}\n"
        rm -rf ${UNPACK_DIR} >/dev/null 2>&1
        exit 0
    fi
    [ ! -z "$TEXT" ] && log "$TEXT"
    rm -rf ${UNPACK_DIR}/${DIRNAME} >/dev/null 2>&1

    if [ ! -z "${UPLOAD_APP}" ]; then
        update_app "${UNPACK_DIR}"
    elif [ ! -z "${UPLOAD_WCP}" ]; then
        update_wcp "${UNPACK_DIR}"
    elif [ ! -z "${UPLOAD_FMW}" ]; then
        update_firmware "${UNPACK_DIR}"
    fi

    if [ -d "${UNPACK_DIR}" ]; then
        rm -rf "${UNPACK_DIR}" >/dev/null 2>&1
    fi

    exit 0
fi

if [ ! -z "$QUERY_STRING" ]; then
    echo "Content-type: text/plain; charset=utf-8"
    echo ""
    echo "ERR_500"
    exit 0
fi

