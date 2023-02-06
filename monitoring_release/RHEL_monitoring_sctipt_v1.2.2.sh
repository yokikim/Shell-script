#!/bin/bash

####VARS####

## 컬러와 스타일을 사용하기 위한 변수들
BOLD_VIOLET="\033[23;1;38;5;104m"
RESET_ANSI=$"\033[0m"
BOLD_YELLOW="\033[1;3;38;5;228m"
MAKE_BOLD="\033[1m"
MAKE_ITALIC="\033[3m"
MAKE_BOLD_ITALIC="\033[1;3m"
PRINT_FINE="\033[1;32mFINE\033[22;0m"
PRINT_ATTENTION="\033[3;1;38;5;197mATTENTION\033[23;22;0m"
HIGHLIGHT_HOSTNAME="\033[1;38;5;104m$HOSTNAME\033[22;0m"
BOLD_PUPLE="\033[1;38;5;135m"
BOLD_RED="\033[1;38;5;197m"

## 로그 내용 중 조회 월을 가리기 위한 변수들
MONTH1=$(date +%b)
MONTH2=$(date -d "1month ago" +%b)
MONTH3=$(date -d "2month ago" +%b)

## 로그용 임시파일을 위한 변수
TMP_DATE=$(date +%Y-%m-%d-%H-%M-%S-%N)
TEMP_LOG_FILE1=$(mktemp /tmp/tmplog-1-$TMP_DATE-XXXXXXXXXXXXXX)


#### FUNCTIONS ####

## 출력을 위한 함수들

function FUNC_PRINT_ATTENTION {
## 첫번째 항목에는 점검항목, 두번째 항목에는 설명
	printf "\033[3;1;38;5;197mATTENTION\033[23;22;0m:\033[1m${1}\033[22m: ${2}"
}
function FUNC_INDENT {
	printf "\t└── "
}

function FUNC_PRINT_UNDERLINE {
	printf "\033[4m${@}\033[24m\n"
}

## 각 함수 모듈당 타이틀
function TITLE_MONITORING {
FUNC_PRINT_UNDERLINE "\n\033[1;9m                      \033[29;3;38;5;228m$1 Check\033[23;39;9m                      \033[0m\n"
}

function TITLE {
	## 스크립트 시작 타이틀
	printf "====================================================================\n"
	printf "                  $BOLD_VIOLET STARTING $BOLD_YELLOW MONITORING SCRIPT$RESET_ANSI\n"
	printf "====================================================================\n"
}
###################

function SERVICE {
	## RHEL 버전별 서비스 실행 여부 확인 함수 
	if [ 1 == $(cat /etc/redhat-release | grep "Santiago" | wc -l) ] ; then
		service $1 status 2>/dev/null
		SERVICEVAL=$(service $1 status | egrep -w "running|operational" | wc -l)
	else
		systemctl status --no-pager $1 2>/dev/null | egrep --color=never "\.service - |Active:"
		SERVICEVAL=$(systemctl is-active $1 | egrep -w "active" | wc -l)
	fi
}

#####################
## NTP확인을 위한 함수 정의


function NTP_RESULT {
	## NTP 서비스 점검 결과만을 위한 함수
	## 첫번째 인자는 동기화중 서버 확인(별표), 두번째 인자는 동기화가 안 되고 있는 서버 확인(물음표), 세번째 인자는 서비스 종류
	if [ $1 == 0 ] || [ $2 -ge 1 ] ; then 
		FUNC_PRINT_ATTENTION $3 "No sync or Unusable timeserver\n"
	elif [ $1 -ge 1 ] || [ $2 == 0 ] ; then
		printf "$3 sync ${PRINT_FINE}\n"
	fi
}	

function MODULE_CHRONYD {
	## Chronyd 확인을 위한 변수 모듈
	SERVICE chronyd
	echo -e " "
	chronyc sources
	echo -e " "
	CHRONY_CHK_STAR=$(chronyc sources | egrep "^\^\*" | wc -l)
	CHRONY_CHK_QUESTION=$(chronyc sources | egrep "^\^\?" | wc -l)
	NTP_RESULT $CHRONY_CHK_STAR $CHRONY_CHK_QUESTION chronyd
}

function MODULE_NTPD {
	## Ntpd 확인을 위한 변수 모듈
	SERVICE ntpd
	echo -e " "
	ntpq -p
	echo -e " "
	NTPD_CHK_STAR=$(ntpq -p | egrep "^\*" | wc -l)
	NTPD_CHK_QUESTION=$(ntpq -p | egrep "^\?" | wc -l)
	NTP_RESULT $NTPD_CHK_STAR $NTPD_CHK_QUESTION ntpd	
}

function NTP_TYPE {
	## 어떤 NTP 서비스를 쓰는지 확인하는 세 버전상 공통된 방법이 없어 각각 서비스당 if문을 돌리기로 함.
	## 이 과정중에 서비스 활성여부 출력은 각 NTP 서비스 점검 모듚 함수에서 다시 시키면 되므로 출력을 null로 보냄
	NTP_TYPE_CHRNYD=0
	NTP_TYPE_NTPD=0
	SERVICE chronyd > /dev/null
	if [ $SERVICEVAL == 1 ] ; then
		NTP_TYPE_CHRNYD="chronyd"
	fi
	SERVICE ntpd > /dev/null
	if [ $SERVICEVAL == 1 ] ; then
		NTP_TYPE_NTPD="ntpd"
	fi
}


function NTP_CHECK {
	## NTP 확인용 메인 모듈 함수
	TITLE_MONITORING "NTP"
	## 어떤 NTP 서비스를 쓰는지 확인
	NTP_TYPE

	if [ $NTP_TYPE_CHRNYD == "chronyd" ] ; then
		MODULE_CHRONYD
	fi
	if [ $NTP_TYPE_NTPD == "ntpd" ] ; then
		MODULE_NTPD
	fi
	if [ $NTP_TYPE_CHRNYD == 0 ] && [ $NTP_TYPE_NTPD == 0 ] ; then
		FUNC_PRINT_ATTENTION "NTP_SERVICE" "NO NTP Client Service\n"
	fi
}

######################
## 로그 조회를 위한 함수 설정

function FILTER1 {
	## 로그 내용 중 필터할 내용 정하기
	cat /var/log/messages* | egrep "^$MONTH1|^$MONTH2|^$MONTH3" | egrep -i 'warn|err|crit|fatal|down|fail|alert|abort' \
	| egrep -vi "\<info\>|\<notice\>|interrupt|override|preferred|team will not be maintained|ip6|ipv6ll|Reached target Shutdown" 
}

function READ_LOG_MORE {
	## more에서 backward나 vi를 실행시키기 위해 로그조회용 임시파일을 만듦
	FILTER1 > $TEMP_LOG_FILE1
	more $TEMP_LOG_FILE1	
}


###########################
#                                                      #
## 메인 모니터링 모듈 함수들 시작   #
#                                                      #
###########################

function BASE_INFORMATION {

TITLE_MONITORING "Basic Information"

	## 하이버바이저 여부 확인
	if [ $(virt-what | wc -w ) -gt 0 ] ; then
		virt=1
		printf "${HIGHLIGHT_HOSTNAME} is ${MAKE_BOLD}$( virt-what | tr "\n" " " ) VM${RESET_ANSI}\n"
	else
		virt=0
		printf "${HIGHLIGHT_HOSTNAME} is ${MAKE_BOLD}Physical server${RESET_ANSI}\n"
	fi

	## OS 버전 확인
	printf "${HIGHLIGHT_HOSTNAME} is using ${MAKE_BOLD}$(cat /etc/redhat-release)${RESET_ANSI}\n"
}

###########################

function NIC_CHECK {

	TITLE_MONITORING "NIC error"
	
	## NIC 리스트 가져오기
	NICLS=$(sed -n '3,$p' /proc/net/dev | sed '/\slo\:/d' |awk '{print $1}' | tr ":" " ")

	## NIC당 확인 시작
	for i in $NICLS ; do
		## NIC당 각 항목 통계 수집
		TXDROP=$(cat /sys/class/net/$i/statistics/tx_dropped)
		TXCOLL=$(cat /sys/class/net/$i/statistics/collisions)
		TXERR=$(cat /sys/class/net/$i/statistics/tx_errors)
		RXDROP=$(cat /sys/class/net/$i/statistics/rx_dropped)
		RXERR=$(cat /sys/class/net/$i/statistics/rx_errors)
		## 각 항목당 정상여부 확인
		if [ $TXDROP != 0 ] ; then
			TXDROP_RESULT=$(echo -e "TXDROP: $TXDROP $PRINT_ATTENTION")
		else
			TXDROP_RESULT=$(echo -e "TXDROP: $TXDROP $PRINT_FINE")
		fi
		if [ $TXCOLL != 0 ] ; then 
			TXCOLL_RESULT=$(echo -e "TXCOLL: $TXCOLL $PRINT_ATTENTION")
		else 
			TXCOLL_RESULT=$(echo -e "TXCOLL: $TXCOLL $PRINT_FINE")
		fi
		if [ $TXERR != 0 ] ; then 
			TXERR_RESULT=$(echo -e "TXERR: $TXERR $PRINT_ATTENTION")
		else 
			TXERR_RESULT=$(echo -e "TXERR: $TXERR $PRINT_FINE")
		fi
		if [ $RXDROP != 0 ] ; then 
			RXDROP_RESULT=$(echo -e "RXDROP: $RXDROP $PRINT_ATTENTION")
		else 
			RXDROP_RESULT=$(echo -e "RXDROP: $RXDROP $PRINT_FINE")
		fi
		if [ $RXERR != 0 ] ; then 
			RXERR_RESULT=$(echo -e "RXERR: $RXERR $PRINT_ATTENTION")
		else 
			RXERR_RESULT=$(echo -e "RXERR: $RXERR $PRINT_FINE")
		fi
		##수집 결과 출력
		printf "${MAKE_BOLD}%-10b${RESET_ANSI}:" $i
		## printf는 \n을 붙이지 않는 이상 같은 줄바꿈하지 않고 계속 출력하므로 이를 이용하였다.
		printf "%b %d %-9b|" $TXDROP_RESULT $TXCOLL_RESULT $TXERR_RESULT $RXDROP_RESULT $RXERR_RESULT
		printf "\n"

		## NIC에 이상이 발생하면 ethtool을 통해 몇몇 정보를 출력
		if [ 0 != $TXDROP ] || [ 0 != $TXCOLL ] || [ 0 != $TXERR ] || [ 0 != $RXDROP ]|| [ 0 != $RXERR ]; then
			printf "\t"
			FUNC_INDENT
			echo -e "${MAKE_ITALIC}Search ${RESET_ANSI}${MAKE_BOLD}$i${RESET_ANSI}${MAKE_ITALIC} HW state${RESET_ANSI}" 
			ethtool $i |egrep -v "Supports auto-negotiation|Advertised auto-negotiation" | egrep -iw "Duplex|[^a-z]*Auto-negotiation|MDI-X|Link detected" | awk '{print "\t""\t",$0}'
		fi
	done
}

##############################

function NIC_REDUNDANCY_CHECK {

	TITLE_MONITORING "NIC bonding/teaming"
	
############BONDING#####

	## 본딩 디바이스 존재시 시작
	if [ -d	/proc/net/bonding ] ; then
		## 본딩 디바이스 리스트 수집
		BONDDEV=$(ls -1 /proc/net/bonding/)

		## Master당 점검 시작
		for x in $BONDDEV ; do
			echo -e "\n${MAKE_ITALIC}...Reading /proc/net/bonding/${RESET_ANSI}${MAKE_BOLD}$x${RESET_ANSI}\n ↓"
			## Master당 Slave 리스트 얻기
			BONDDEVNIC=$(awk -F ": " '/^\<Slave Interface\>/ { print $2 }' /proc/net/bonding/$x)
			## 각 Slave당 각 항목 점검
			for y in $BONDDEVNIC ; do
				## Slave의 Downcount 수집
				DOWNCOUNT=$(sed -n "/^Slave Interface: $y/,/^$/p" /proc/net/bonding/$x | awk -F ": " '/Link Failure Count/ {print $2}' ) 
				## Slave의 Link 상태 수집
				BOND_LINK=$(sed -n "/^Slave Interface: $y/,/^$/p" /proc/net/bonding/$x | awk -F ": " '/M?I?I? ?Status/ {print $2}')
				## 각 Slave당 몇몇 항목 출력
				cat /proc/net/bonding/$x | egrep -iw "Slave Interface|Link Failure Count|Status" | sed -n "/$y/,/Link Failure Count:/p" | sed -e 's/\(Slave Interface:.*\)/-\1/g' -e 's/\(Link Failure Count:.*\)/     \1/g' -e 's/\([MI ]*Status:.*\)/   \1/g'
				## Slave에 아무 이상 없을시 FINE메세지 출력
				BOND_COUNT=0
				## Slave에 Downcount 발생시 에러메세지 출력
				if [ 0 != $DOWNCOUNT ] ; then		
					FUNC_INDENT
					FUNC_PRINT_ATTENTION "Bonding" "$DOWNCOUNT Downcount\n" 
					BOND_COUNT=$(($BOND_COUNT + 1))
				fi
				## Slave에 Linkdown 발생시 에러메세지 출력
				if [ $(echo $BOND_LINK) != "up" ] ; then
					FUNC_INDENT
					FUNC_PRINT_ATTENTION "Bonding" "master: $x slave: $y link down\n"
					BOND_COUNT=$(($BOND_COUNT + 1))
				fi
				## Slave에 아무 이상 없을시 FINE메세지 출력
				if [ $BOND_COUNT == 0 ] ; then
					echo -e "\t└── $x's slave $y is ${PRINT_FINE}"
				fi
			done
		done
	else
		FUNC_PRINT_UNDERLINE "Bonding ${BOLD_VIOLET}not used${RESET_ANSI}"
	fi



############TEAMING#####

	## Teaming 디바이스 존재 여부 확인
	if [ -d /var/run/teamd ] ; then

		## Teaming 마스터 디바이스 
		TEAMDEV=$(ls -1 /var/run/teamd/*.pid | awk -F . '{ print $1 }' | awk -F / '{ print $5 }')

		## Master당 점검 착수
		for x in $TEAMDEV ; do
			echo -e "\n${MAKE_ITALIC}...Check teamd device${RESET_ANSI} ${MAKE_BOLD}$x${RESET_ANSI}\n ↓"
			## Masater당 Slave 디바이스 조회	
			TEAMDEVNIC=$(teamnl $x port | awk -F ": " '{ print $2 }')
			## Slave당 항목 점검
			for y in $TEAMDEVNIC ; do
				## Slave당 Downcount 점검
				DOWNCOUNT=$(teamdctl $x state | sed -n "/$y/,/[^a-z]\<down count\>/p" | awk '/down count/ { print $3 }')
				TEAM_LINK=$(teamdctl $x state | sed -n "/$y/,/[^a-z]\<down count\>/p" | awk '/[^a-z]link:/ { print $2 }')
				teamdctl $x state | egrep -v "link watches:|link summary:|instance|name:|runner:|active port: |setup:| runner:|ports:" | sed -n "/$y/,/down count:/p" | sed -e "s/.*$y/-Slave: $y/g" -e 's/[^a-z]*\(link:.*\)/   \1/g' -e 's/[^a-z]*\(down count:.*\)/     \1/g'
				TEAM_COUNT=0
				if [ 0 != $DOWNCOUNT ] ; then
					FUNC_INDENT
					FUNC_PRINT_ATTENTION "Teaming" "$DOWNCOUNT downcount\n"
					TEAM_COUNT=$(($TEAM_COUNT + 1))
				fi
				if [ $(echo $TEAM_LINK) != "up" ] ; then
					FUNC_INDENT
					FUNC_PRINT_ATTENTION "Teaming" "$x - $y Linkdown\n"
					TEAM_COUNT=$(($TEAM_COUNT + 1))
				fi
				if [ $TEAM_COUNT == 0 ] ; then
					echo -e "\t└─── $x's slave ${BOLD_PUPLE}$y${RESET_ANSI} is ${PRINT_FINE}"
				fi
			done
		done			
	else
		FUNC_PRINT_UNDERLINE "Teaming ${BOLD_VIOLET}not used${RESET_ANSI}" 
	fi
}
#######################
function RESOURCE_CHECK {
	

	TITLE_MONITORING "System Resources/Process"
	
	## 시스템 상황 요약 출력
	## free 출력물에 부분적으로 색 입히기
	if [ 1 == $(grep "Santiago" /etc/redhat-release | wc -l) ] ; then
		free -h | awk -v BOLD_ORANGE="\033[1;38;5;208m" -v RESET_ANSI="\033[0m" \
		'{if(NR == 3)sub($3,BOLD_ORANGE$3RESET_ANSI)} ;
		{if(NR == 2)sub($2,BOLD_ORANGE$2RESET_ANSI)} ;
		{if(NR == 4)sub($3,BOLD_ORANGE$3RESET_ANSI)} ;
		{print $0}'
	else
		free -h | awk -v BOLD_ORANGE="\033[1;38;5;208m" -v RESET_ANSI="\033[0m" \
		'{if(NR == 2)sub($3,BOLD_ORANGE$3RESET_ANSI)} ;
		{if(NR == 2)sub($2,BOLD_ORANGE$2RESET_ANSI)} ;
		{if(NR == 3)sub($3,BOLD_ORANGE$3RESET_ANSI)} ;
		{print $0}'
	fi
	echo -e " "
	# top 요약부분 중 몇몇 부분에 색을 입혀 출력
	if [ 1 == $(grep "Santiago" /etc/redhat-release | wc -l) ] ; then
		top -b -n 1 | sed -n '1,3p' | awk -v BOLD_ORANGE="\033[1;38;5;208m" -v RESET_ANSI="\033[0m" \
		'{if(NR==1) {gsub(/[0-9]?[0-9] min/,BOLD_ORANGE"&"RESET_ANSI)}};
		{if(NR==1) {gsub(/[0-9]?[0-9] hour/,BOLD_ORANGE"&"RESET_ANSI)}};
		{if(NR==1) {gsub(/[0-9]?[0-9]+ days/,BOLD_ORANGE"&"RESET_ANSI)}};
		{if(NR==1) {gsub(/[^-] [0-9]?[0-9]:[0-9][0-9]/,BOLD_ORANGE"&"RESET_ANSI)}};
		{if(NR==1) {gsub(/[0-9]\.[0-9][0-9]/,BOLD_ORANGE"&"RESET_ANSI)}};
		{if(NR==2) {gsub(/[0-9] zombie/,BOLD_ORANGE"&"RESET_ANSI)}};
		{if(NR==3) {gsub(/[0-9]?[0-9]?[0-9]\.[0-9]%id/,BOLD_ORANGE"&"RESET_ANSI)}};
		{print $0}'

	else
		top -b -n 1 | sed -n '1,3p' | awk -v BOLD_ORANGE="\033[1;38;5;208m" -v RESET_ANSI="\033[0m" \
		'{if(NR==1) {gsub(/[0-9]?[0-9] min/,BOLD_ORANGE"&"RESET_ANSI)}};
		{if(NR==1) {gsub(/[0-9]?[0-9] hour/,BOLD_ORANGE"&"RESET_ANSI)}};
		{if(NR==1) {gsub(/[0-9]?[0-9]+ days/,BOLD_ORANGE"&"RESET_ANSI)}};
		{if(NR==1) {gsub(/[^-] [0-9]?[0-9]:[0-9][0-9]/,BOLD_ORANGE"&"RESET_ANSI)}};
		{if(NR==1) {gsub(/[0-9]\.[0-9][0-9]/,BOLD_ORANGE"&"RESET_ANSI)}};
		{if(NR==2) {gsub(/[0-9] zombie/,BOLD_ORANGE"&"RESET_ANSI)}};
		{if(NR==3) {gsub(/[0-9]?[0-9]?[0-9]\.[0-9] id/,BOLD_ORANGE"&"RESET_ANSI)}};
		{print $0}'
	fi
	echo -e " "
	
	### CHECK MEMORY ###

	## /proc/meminfo로부터 정보 수집
	MEMTotal=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
	MEMBuffer=$(awk '/^Buffers:/ { print $2 }' /proc/meminfo)
	MEMCache=$(awk '/^Cached:/ { print $2 }' /proc/meminfo)
	MEMFree=$(awk '/^MemFree:/ { print $2 }' /proc/meminfo)
	MEMRslab=$(awk '/^SReclaimable:/ { print $2 }' /proc/meminfo)
	MEMTswap=$(awk '/^SwapTotal:/ { print $2 }' /proc/meminfo)
	MEMFswap=$(awk '/^SwapFree:/ { print $2 }' /proc/meminfo)

	## 실질 여유공간 계산
	if [ 1 == $( grep "Santiago" /etc/redhat-release | wc -l ) ] ; then
		MEMLeave=$(($MEMBuffer + $MEMCache + $MEMFree))
	else	
		MEMLeave=$(($MEMBuffer + $MEMCache + $MEMFree + $MEMRslab))
	fi

	## 실질 여유공간율 계산
	MEMCheck=$(echo $MEMLeave $MEMTotal | awk '{printf "%d", $1/$2*100}')

	## 실질 여유공간율이 15 미만일시 경고 출력
	if [ $(echo $MEMCheck ) -lt 15 ] ; then
		FUNC_PRINT_ATTENTION "Memory" "$MEMCheck FREE (under 15)\n"
	else
		printf "Memory: $MEMCheck FREE ${PRINT_FINE}\n"
	fi	
	
	### CHECK SWAP ###
	
	## 총 메모리양 대비 스왑 사용율 계산
	MEMUswap=$(echo $MEMTotal $MEMTswap $MEMFswap | awk '{printf "%d", ($2-$3)/$1*100}')

	## 스왑 사용율이 3을 넘어갈때 경고 메세지 출력
	if [ $MEMUswap -ge 3 ] ; then
		FUNC_PRINT_ATTENTION "Swap" "$MEMUswap USED (greater equal 3)\n"
	else
		printf "Swap: $MEMUswap USED ${PRINT_FINE}\n"
	fi

	### CHECK ZOMBIE ###

	ZOMBIECOUNT=$(ps -ef | grep -i defunct | grep -v grep | wc -l)
	if [ $ZOMBIECOUNT -gt 0 ] ; then
		FUNC_PRINT_ATTENTION "Zombie" "$ZOMBIECOUNT Zombie\n"
	else
		printf "Zombies: $ZOMBIECOUNT ${PRINT_FINE}\n"
	fi

	### CHECK CPU IDLE ###

	## top 배치모드로부터 idle값 추출
	## 부팅시부터가 아닌 현재 변동률을 빨리 잡아야 하기 때문
	CPU_IDLE=$( top -b -n 1 | sed -n '3p' | awk -F , '{ printf "%d",  $4 }' )
	## CPU idle이 80 미만일시 경고메세지 출력
	if [ $CPU_IDLE -lt 80 ] ; then
		FUNC_PRINT_ATTENTION "IDLE CPU" "$CPU_IDLE (under 80)\n"
	else
		printf "IDLE CPU : %d ${PRINT_FINE}\n" $CPU_IDLE
	fi
	
	### CHECK UPTIME ###
	
	## 출력에 쓰일 값을 별도로 계산
	UPTIME_VALUE=$(awk '{ day = $1/86400 ; hour = ($1%86400)/3600 ; min = (($1%86400)%3600)/60 ; printf "%dd %02d:%02d\n" , day , hour, min}' /proc/uptime)
	## uptime 정상 판정 여부에 쓰일 변수
	UPTIME_SEC=$(awk '{ printf "%d" , $1 }' /proc/uptime )
	
	## 1년을 초단위 기준으로 초과하지 않았는지 확인 (60sec*60min*24hours*365days=31536000)
	if [ $UPTIME_SEC -ge 31536000 ] ; then
		FUNC_PRINT_ATTENTION "Uptime" "$UPTIME_VALUE (over 1y)\n"
	else
		printf "Uptime: $UPTIME_VALUE ${PRINT_FINE}\n"
	fi

	## /proc/loadavg 내 세 값중 한 값이 코어 개수를 초과하면 경고문을 출력하고 아니면 정상 메세지를 출력하기
	if [ $(awk '{ printf "%d", $1 }' /proc/loadavg) -ge $(nproc) ] \
	|| [ $(awk '{ printf "%d", $2 }' /proc/loadavg) -ge $(nproc) ] \
	|| [ $(awk '{ printf "%d", $3 }' /proc/loadavg) -ge $(nproc) ] ; then
		FUNC_PRINT_ATTENTION "Load Average" "$(awk '{ printf "1min:%d 5min:%d 15min:%d", $1,$2,$3 }' /proc/loadavg) (over $(nproc))\n"
	else
		printf "Load Average is ${PRINT_FINE}\n"
	fi
}
####################################################
# DISK_CHECK 함수 아래로 들어가는 모듈 함수들                                   #
####################################################
function DISK_USEAGE_CHECK {

	## 디스크 마운트포인트 수집
	DISK_MOUNTPOINT=$(df -P -x devtmpfs -x tmpfs -x iso9660 | sed '1d' | awk '{print $6}')
	for i in $DISK_MOUNTPOINT ; do
		## 마운트 포인트 기준으로 디스크 사용량 수집
		DISK_USAGE=$(df $i |  sed '1d' | awk '{printf "%d", $5}')
		## 디스크 사용량이 80퍼를 넘어가면 경고 메세지를 출력한다
		## source도 다시 추출해야 했기 때문에 df로부터 pipe를 넘겼다.
		if [ $DISK_USAGE -gt 80 ] ; then
			FUNC_PRINT_ATTENTION "Disk usage" "$(df -P $i | sed '1d' | awk '{ printf "%s (source: %s) Usage: %d(over 80)" , $6 ,$1, $5}')\n"
		else
			## printf 특성상 마지막에 줄바꿈 기호를 넣지 않는 한 한줄로 출력된다.
			df -P $i | sed '1d' | awk  '{ printf "%s (source: %s) Usage: %d " ,$6, $1, $5}'
			printf "${PRINT_FINE}\n"
		fi
	done
}
###############################
function MULTIPATH_USEAGE_CHECK {

	### multipath 서비스 구동 여부 확인
	SERVICE multipathd
	MULTIPATH_SERV=$SERVICEVAL

	## multipath 패키지 확인
	if [ $(rpm -qa | grep device-mapper-multipath | wc -l) -gt 0 ] ; then
		echo -e "Multipath package Found" 
		MULTIPATH_PKG=1
	fi

	## multipath 설정 파일 확인
	if [ -f /etc/multipath.conf ] ; then
		echo -e "Multipath config file Found" 
		MULTIPATH_CFG=1
	fi

	## 서비스 사용여부를 확인하기 위한 세가지 요소 확인
	if [ $MULTIPATH_SERV == 1 ] && [ $MULTIPATH_PKG == 1 ] && [ $MULTIPATH_CFG == 1 ] ; then
		echo -e "$HOSTNAME is using multipath service" 
		## 출력을 위한 멀티패스 디바이스 alias 이름 집계
		MULTIPATH_ALIAS=$(multipath -l -v1)
		## 링크가 떨어진 멀티패스 링크 확인
		MULTIPATH_CHK=$(multipath -ll | egrep -i "failed|faulty|offline" | wc -l)
		## multiapth 링크 확인
		if [ $MULTIPATH_CHK -gt 0 ] ; then
			## multipath alias 이름 표시 및 faild link 표시
			multipath -ll | egrep -wi "^$MULTIPATH_ALIAS|failed|faulty|offline"
			FUNC_INDENT
			FUNC_PRINT_ATTENTION "Multipath" "link down\n"
		elif [ 0 == $(multipath -ll | grep "dm-" | wc -l) ] ; then
			FUNC_INDENT
			FUNC_PRINT_ATTENTION "Multipath" "Check wwid in multipath.conf OR login to iscsi node\n"
		else
			echo -e "Multipath is ${PRINT_FINE}" 
		fi
	else
		echo -e "multipath not using now"
	fi
}
####################
function MOUNT_CHECK {

	## /etc/fstab 으로부터 mountpoint 리스트 얻기
	FSTAB_LIST=$(sed -n '/^[^#].*/p' /etc/fstab | awk '{if($3 != "swap" && $3 != "tmpfs" && $3 != "devpts" && $3 != "sysfs" && $3 != "proc" ) print $2}')
	## /etc/fstab의 마운트 리스트를 /proc/mounts내 마운트 포인트와 비교하기
	## grep -w 옵션으로 root 디렉토리와 정확히 매치하는 정보를 뽑아내었다.
	for i in $FSTAB_LIST ; do
		MOUNTCHK=$(grep -w $i /proc/mounts | wc -l)
		if [ $MOUNTCHK == 0 ] ; then
			sed -n '/^[^#].*/p' /etc/fstab | awk -v i=$i '{ if ( $2 == i ) {print "\033[4m"$0"\033[24m"} }'
			FUNC_INDENT
			FUNC_PRINT_ATTENTION "fstab" "mountpoint $i didn't mounted yet\n"
		else
			echo -e "Mountpoint $i is ${PRINT_FINE}" 
		fi
	done
}
##################
function DISK_CHECK {
	## 세가지 디스크 점검 모듈 함수들을 하나로 묶었다.
	TITLE_MONITORING "Disk-Related"
	FUNC_PRINT_UNDERLINE "${MAKE_ITALIC}Check ${MAKE_BOLD_ITALIC}Disk usage${RESET_ANSI}...\n"
	DISK_USEAGE_CHECK
	FUNC_PRINT_UNDERLINE "\n${MAKE_ITALIC}Check ${MAKE_BOLD_ITALIC}Mountpoints${RESET_ANSI}...\n"
	MOUNT_CHECK
	FUNC_PRINT_UNDERLINE "\n${MAKE_ITALIC}Check ${MAKE_BOLD_ITALIC}Multipath${RESET_ANSI}...\n"
	MULTIPATH_USEAGE_CHECK
}
####################
function KDUMP_CHECK {
	TITLE_MONITORING "Kdump"
	SERVICE kdump
	echo -e " "
	if [ 1 == $SERVICEVAL ] ; then
		echo -e "Kdump service is ${PRINT_FINE}"
	else
		FUNC_PRINT_ATTENTION "Kdump" "Kdump service didn't active\n"
	fi
}
## 메인 모니터링 모듈의 끝
###################

function MAIN_LOOP {

	BASE_INFORMATION
	NIC_CHECK
	NIC_REDUNDANCY_CHECK
	RESOURCE_CHECK
	DISK_CHECK
	NTP_CHECK
	KDUMP_CHECK

}

TITLE
MAIN_LOOP


TITLE_MONITORING "Log"

read -s -n1 -p "(Press Enter to Continue)"
READ_LOG_MORE


