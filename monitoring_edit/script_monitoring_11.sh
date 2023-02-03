#!/bin/bash

####VARS####

## define vars for color/sytle
BOLD_VIOLET="\033[23;1;38;5;104m"
RESET_ANSI=$"\033[0m"
BOLD_YELLOW="\033[1;3;38;5;228m"
MAKE_BOLD="\033[1m"
MAKE_ITALIC="\033[3m"
MAKE_BOLD_ITALIC="\033[1;3m"
PRINT_FINE="\033[1;32mFINE\033[22;0m"
PRINT_ATTENTION="\033[3;1;31mATTENTION\033[23;22;0m"
HIGHLIGHT_HOSTNAME="\033[1m$HOSTNAME\033[22m"

## define vars for log
MONTH1=$(date +%b)
MONTH2=$(date -d "1month ago" +%b)
MONTH3=$(date -d "2month ago" +%b)

## defind vars for logtempfile
TMP_DATE=$(date +%Y-%m-%d-%H-%M-%S-%N)
TEMP_LOG_FILE1=$(mktemp /tmp/tmplog-1-$TMP_DATE-XXXXXXXXXXXXXX)


#### FUNCTIONS ####

## 출력을 위한 함수들

# function FUNC_PRINT_BOLD {
	# printf "\033[1m;${1}\033[22m"
# }

# function FUNC_PRINT_FINE {
# ## 첫번째 항목에는 점검항목
	# printf "\033[1m${1}\033[22m is \033[1;32mFINE\033[22;0m\n"
# }

function FUNC_PRINT_ATTENTION {
## 첫번째 항목에는 점검항목, 두번째 항목에는 설명
	printf "\033[3;1;31mATTENTION\033[23;22;0m:\033[1m${1}\033[22m: ${2}"
}
function FUNC_INDENT {
	printf "\t└── "
}
function FUNC_PRINT_UNDERLINE {
	printf "\033[4m"$@"\033[24m"
}

###################

## define function for title
function TITLE_MONITORING {
echo -e "\n\e[1m------------\e[3;33m$1 Check\e[23;39m------------\e[0m\n"
}

function TITLE {

printf "====================================================================\n"
printf "                  $BOLD_VIOLET STARTING $BOLD_YELLOW MONITORING SCRIPT$RESET_ANSI\n"
printf "====================================================================\n"

}
###################

function SERVICE {
## 
	if [ 1 == $(cat /etc/redhat-release | grep "Santiago" | wc -l) ] ; then
		service $1 status 2>/dev/null
		SERVICEVAL=$(service $1 status | egrep -w "running|operational" | wc -l)
	else
		systemctl status --no-pager $1 2>/dev/null | egrep --color=never "\.service - |Active:"
		SERVICEVAL=$(systemctl is-active $1 | egrep -w "active" | wc -l)
	fi
}

##########################################
## define function for NTP Checking


function NTP_RESULT {
# 첫번째 인자는 동기화중 서버 확인(별표), 두번째 인자는 동기화가 안 되고 있는 서버 확인(물음표), 세번째 인자는 서비스 종류
	if [ $1 -ge 1 ] ; then
		printf "$3 sync ${PRINT_FINE}\n"
	elif [ $1 == 0 ] ; then
		printf FUNC_PRINT_ATTENTION $3 "no sync\n"
	fi
	
	if [ $2 == 0 ] ; then
		printf "no unusable server ${PRINT_FINE}\n"
	elif [ $2 -ge 1 ] ; then
		FUNC_PRINT_ATTENTION $3 "unusable timeserver\n"
	fi
}

function MODULE_CHRONYD {
## check chronyd with modularized script
	echo -e " "
	chronyc sources
	echo -e " "
	CHRONY_CHK_STAR=$(chronyc sources | egrep "^\^\*" | wc -l)
	CHRONY_CHK_QUESTION=$(chronyc sources | egrep "^\^\?" | wc -l)
	NTP_RESULT $CHRONY_CHK_STAR $CHRONY_CHK_QUESTION chronyd
}

function MODULE_NTPD {
## check ntpd with modularized script
	echo -e " "
	ntpq -p
	echo -e " "
	NTPD_CHK_STAR=$(ntpq -p | egrep "^\*" | wc -l)
	NTPD_CHK_QUESTION=$(ntpq -p | egrep "^\?" | wc -l)
	NTP_RESULT $NTPD_CHK_STAR $NTPD_CHK_QUESTION ntpd	
}

function NTP_TYPE {
	NTP_TYPE_CHRNYD=0
	NTP_TYPE_NTPD=0
	SERVICE chronyd
	if [ $SERVICEVAL == 1 ] ; then
		NTP_TYPE_CHRNYD="chronyd"
	fi
	SERVICE ntpd
	if [ $SERVICEVAL == 1 ] ; then
		NTP_TYPE_NTPD="ntpd"
	fi
}


function NTP_CHECK {

TITLE_MONITORING "NTP"

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

#############################################################################################
## Variables and function for logs

## define functions for log monitoring

function FILTER1 {
cat /var/log/messages* | egrep "^$MONTH1|^$MONTH2|^$MONTH3" | egrep -i 'warn|err|crit|fatal|down|fail|alert|abort' \
| egrep -vi "\<info\>|\<notice\>|interrupt|override|preferred|team will not be maintained|ip6|ipv6ll|Reached target Shutdown" 
}

function READ_LOG_MORE {
FILTER1 > $TEMP_LOG_FILE1
more $TEMP_LOG_FILE1	
}


############################################
#                                          #
## start main monitoring module functions  #
#                                          #
############################################

function BASE_INFORMATION {

TITLE_MONITORING "Basic Information"

### check hypervisor system
	if [ $(virt-what | wc -w ) -gt 0 ] ; then
		virt=1
		printf "${HIGHLIGHT_HOSTNAME} is ${MAKE_BOLD}$( virt-what | tr "\n" " " ) VM${RESET_ANSI}\n"
	else
		virt=0
		printf "${HIGHLIGHT_HOSTNAME} is ${MAKE_BOLD}Physical server${RESET_ANSI}\n"
	fi

### show system OS version
	printf "${HIGHLIGHT_HOSTNAME} is using ${MAKE_BOLD}$(cat /etc/redhat-release)${RESET_ANSI}\n"
}

##########################################################

function NIC_CHECK {

	TITLE_MONITORING "NIC error"
	
## get list of NIC
#	NICLS=$(sed -n '3,$p' /proc/net/dev | sed '/\slo\:/d' |awk '{print $1}' | tr ":" " ")
#	NICLS=$(ls -l /sys/class/net/ | sed -n '/^l/p' | awk '{ print $9 }' | grep -wv lo)
	NICLS=$(ls -d1 /sys/class/net/*/ | awk -F"/" '{print $5}' | grep -wv lo)

## start check per NIC
	for i in $NICLS ; do
## collect TXDROP or TXCOLL per NIC
		# TXDROP=$(sed 's/|/ /g' /proc/net/dev | awk -v i=$i":" '{if( $1 == i ) print $13}')
		# TXCOLL=$(sed 's/|/ /g' /proc/net/dev | awk  -v i=$i":" '{if( $1 == i ) print $15}')
		# TXERR=$(sed 's/|/ /g' /proc/net/dev | awk  -v i=$i":" '{if( $1 == i ) print $12}')
		# RXDROP=$(sed 's/|/ /g' /proc/net/dev | awk  -v i=$i":" '{if( $1 == i ) print $5}')
		# RXERR=$(sed 's/|/ /g' /proc/net/dev | awk  -v i=$i":" '{if( $1 == i ) print $4}')

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
		
		printf "${MAKE_BOLD}%-10b${RESET_ANSI}: " $i
		
		printf "%b %d %-9b|" $TXDROP_RESULT $TXCOLL_RESULT $TXERR_RESULT $RXDROP_RESULT $RXERR_RESULT

		printf "\n"

## check NIC HW state if had errors
		if [ 0 != $TXDROP ] || [ 0 != $TXCOLL ] || [ 0 != $TXERR ] || [ 0 != $RXDROP ]|| [ 0 != $RXERR ]; then
			echo -e "\t\t└── \e[3mSearch \e[23;1m$i\e[3;22m HW state\e[23m" 
			ethtool $i |egrep -v "Supports auto-negotiation|Advertised auto-negotiation" | egrep -iw "Duplex|[^a-z]*Auto-negotiation|MDI-X|Link detected" | awk '{print "\t""\t",$0}'
		fi
## end per NIC drop or collision check
	done

}

####################################################################################################################

function NIC_REDUNDANCY_CHECK {

	TITLE_MONITORING "NIC bonding/teaming"
	
############BONDING#####

## check bonding device exsist
	if [ -d	/proc/net/bonding ] ; then
## get bonding device list
		BONDDEV=$(ls -1 /proc/net/bonding/)

## check bonding state per master
		for x in $BONDDEV ; do
			echo -e "\n${MAKE_ITALIC}...Reading /proc/net/bonding/${RESET_ANSI}${MAKE_BOLD}$x${RESET_ANSI}\n ↓"
## get bonding slaves per master
			BONDDEVNIC=$(awk -F ": " '/^\<Slave Interface\>/ { print $2 }' /proc/net/bonding/$x)
## check state per slaves
			for y in $BONDDEVNIC ; do
				DOWNCOUNT=$(sed -n "/^Slave Interface: $y/,/^$/p" /proc/net/bonding/$x | awk -F ": " '/Link Failure Count/ {print $2}' ) 
				BOND_LINK=$(sed -n "/^Slave Interface: $y/,/^$/p" /proc/net/bonding/$x | awk -F ": " '/M?I?I? ?Status/ {print $2}')
				cat /proc/net/bonding/$x | egrep -iw "Slave Interface|Link Failure Count|Status" | sed -n "/$y/,/Link Failure Count:/p" | sed -e 's/\(Slave Interface:.*\)/-\1/g' -e 's/\(Link Failure Count:.*\)/     \1/g' -e 's/\([MI ]*Status:.*\)/   \1/g'
				BOND_COUNT=0
				if [ 0 != $DOWNCOUNT ] ; then		
#					echo -e "\t└─── \e[3;1;31mATTENTION\e[23;22;0m:\e[1mBonding\e[22m: $x's slave $y has \e[1m$DOWNCOUNT\e[22m downcount"
					FUNC_INDENT
					FUNC_PRINT_ATTENTION "Bonding" "$DOWNCOUNT Downcount\n" 
					BOND_COUNT=$(($BOND_COUNT + 1))
				fi
				if [ $(echo $BOND_LINK) != "up" ] ; then
#					echo -e "\t└─── \e[3;1;31mATTENTION\e[23;22;0m:\e[1mBonding\e[22m: $x's slave $y was \e[1mDOWN\e[22m"
					FUNC_INDENT
					FUNC_PRINT_ATTENTION "Bonding" "master: $x slave: $y link down\n"
					BOND_COUNT=$(($BOND_COUNT + 1))
				fi
				if [ $BOND_COUNT == 0 ] ; then
					echo -e "\t└── $x's slave $y is ${PRINT_FINE}"
				fi
			done
		done
	else
		echo -e "Bonding not used"
	fi



############TEAMING#####

## check teamd device exsist
	if [ -d /var/run/teamd ] ; then

## get teamd master device list
		TEAMDEV=$(ls -1 /var/run/teamd/*.pid | awk -F . '{ print $1 }' | awk -F / '{ print $5 }')

## check teaming state per master
		for x in $TEAMDEV ; do
			echo -e "\n${MAKE_ITALIC}...Check teamd device${RESET_ANSI} ${MAKE_BOLD}$x${RESET_ANSI}\n ↓"
## get teaming slave per teaming master		
			TEAMDEVNIC=$(teamnl $x port | awk -F ": " '{ print $2 }')
## check state per slaves
			for y in $TEAMDEVNIC ; do
				DOWNCOUNT=$(teamdctl $x state | sed -n "/$y/,/[^a-z]\<down count\>/p" | awk '/down count/ { print $3 }')
				TEAM_LINK=$(teamdctl $x state | sed -n "/$y/,/[^a-z]\<down count\>/p" | awk '/[^a-z]link:/ { print $2 }')
				teamdctl $x state | egrep -v "link watches:|link summary:|instance|name:|runner:|active port: |setup:| runner:|ports:" | sed -n "/$y/,/down count:/p" | sed -e "s/.*$y/-Slave: $y/g" -e 's/[^a-z]*\(link:.*\)/   \1/g' -e 's/[^a-z]*\(down count:.*\)/     \1/g'
				TEAM_COUNT=0
				if [ 0 != $DOWNCOUNT ] ; then
#					echo -e "\t└─── \e[3;1;31mATTENTION\e[23;22;0m:\e[1mTeaming\e[22m: $x 's slave $y has \e[1m$DOWNCOUNT\e[22m downcount"
					FUNC_INDENT
					FUNC_PRINT_ATTENTION "Teaming" "$DOWNCOUNT downcount\n"
					TEAM_COUNT=$(($TEAM_COUNT + 1))
				fi
				if [ $(echo $TEAM_LINK) != "up" ] ; then
#					echo -e "\t└─── \e[3;1;31mATTENTION\e[23;22;0m:\e[1mTeaming\e[22m: $x 's slave $y was \e[1mDOWN\e[22m"
					FUNC_INDENT
					FUNC_PRINT_ATTENTION "Teaming" "$x - $y Linkdown\n"
					TEAM_COUNT=$(($TEAM_COUNT + 1))
				fi
				if [ $TEAM_COUNT == 0 ] ; then
					echo -e "\t└─── $x's slave ${MAKE_BOLD}$y${RESET_ANSI} is ${PRINT_FINE}"
				fi
## end downcount check per NIC
			done
## end whole teamd device check
		done			
## end teamd device exsist
	else
		echo -e "Teaming not used" 
	fi
}
##########################################################################################
function RESOURCE_CHECK {
	

	TITLE_MONITORING "System Resources/Process"
	
## show memory, load average, zombie, swap useage
	free -h 
	echo -e " "
	top -b -n 1 | sed -n '1,3p'
	echo -e " "
	
### CHECK MEMORY ###

## collect data from /proc/meminfo

	MEMTotal=$(awk '/^MemTotal:/ { print $2 }' /proc/meminfo)
	MEMBuffer=$(awk '/^Buffers:/ { print $2 }' /proc/meminfo)
	MEMCache=$(awk '/^Cached:/ { print $2 }' /proc/meminfo)
	MEMFree=$(awk '/^MemFree:/ { print $2 }' /proc/meminfo)
	MEMRslab=$(awk '/^SReclaimable:/ { print $2 }' /proc/meminfo)
	MEMTswap=$(awk '/^SwapTotal:/ { print $2 }' /proc/meminfo)
	MEMFswap=$(awk '/^SwapFree:/ { print $2 }' /proc/meminfo)

## calculate real free space
	if [ 1 == $( grep "Santiago" /etc/redhat-release | wc -l ) ] ; then
		MEMLeave=$(($MEMBuffer + $MEMCache + $MEMFree))
	else	
		MEMLeave=$(($MEMBuffer + $MEMCache + $MEMFree + $MEMRslab))
	fi

## calculate real free space percentage
	MEMCheck=$(echo $MEMLeave $MEMTotal | awk '{printf "%d", $1/$2*100}')

## check real free space percentage is lower then 15
	if [ $(echo $MEMCheck ) -lt 15 ] ; then
#		MEM_RESULT=$(FUNC_PRINT_ATTENTION "Memory" "$MEMCheck% FREE" )
		FUNC_PRINT_ATTENTION "Memory" "$MEMCheck FREE (under 15)\n"
	else
#		MEM_RESULT=$(printf "Memory useage ${PRINT_FINE}: $MEMCheck% FREE")
		printf "Memory: $MEMCheck FREE ${PRINT_FINE}\n"
	fi	
	
### CHECK SWAP ###
	
## calculate swap using percentage from total memory

	MEMUswap=$(echo $MEMTotal $MEMTswap $MEMFswap | awk '{printf "%d", ($2-$3)/$1*100}')

## check swap using percentage is bigger then 3

	if [ $MEMUswap -ge 3 ] ; then
#		SWAP_RESULT=$(FUNC_PRINT_ATTENTION "Swap" "$MEMUswap% USED")
		FUNC_PRINT_ATTENTION "Swap" "$MEMUswap USED (greater equal 3)\n"
	else
#		SWAP_RESULT=$(printf "swap space is \e[1;32mFINE\e[22;0m: $MEMUswap% USED") 
		printf "Swap: $MEMUswap USED ${PRINT_FINE}\n"
	fi

### CHECK ZOMBIE ###

	ZOMBIECOUNT=$(ps -ef | grep -i defunct | grep -v grep | wc -l)
	if [ $ZOMBIECOUNT -gt 0 ] ; then
#		ZOMBIE_RESULT=$(FUNC_PRINT_ATTENTION "Zombie" "$ZOMBIECOUNT")
		FUNC_PRINT_ATTENTION "Zombie" "$ZOMBIECOUNT Zombie\n"
	else
#		ZOMBIE_RESULT=$(printf "Zombies: $ZOMBIECOUNT ${PRINT_FINE}")
		printf "Zombies: $ZOMBIECOUNT ${PRINT_FINE}\n"
	fi

### CHECK CPU IDLE ###

## grep value from top
	CPU_IDLE=$( top -b -n 1 | sed -n '3p' | awk -F , '{ printf "%d",  $4 }' )
#	CPU_IDLE=$( vmstat 1 3 | awk  'NR==5 {print $15}' )
## check CPU idle is OK
	if [ $CPU_IDLE -lt 80 ] ; then
#		IDLE_RESULT=$(FUNC_PRINT_ATTENTION "IDLE CPU" "$CPU_IDLE%")
		FUNC_PRINT_ATTENTION "IDLE CPU" "$CPU_IDLE (under 80)\n"
	else
#		IDLE_RESULT=$(printf "IDLE CPU : %d% ${PRINT_FINE}" $CPU_IDLE)
		printf "IDLE CPU : %d ${PRINT_FINE}\n" $CPU_IDLE
	fi
	
### CHECK UPTIME ###
	
## calculate uptime to human readable
	# UPTIME_VALUE=$(awk '{ \
# year=$1/31536000 ;\
# week=($1%31536000)/604800 ;\
# day=(($1%31536000)%604800)/86400 ;\
# hour=((($1%31536000)%604800)%86400)/3600 ;\
# min=(((($1%31536000)%604800)%86400)%3600)/60 ;\
# sec=(((($1%31536000)%604800)%86400)%3600%60) ;\
# printf "%dy %dw %dd %dh %dm %.2fs\n" , year, week, day, hour, min, sec}' /proc/uptime)

	UPTIME_VALUE=$(awk '{ day = $1/86400 ; hour = ($1%86400)/3600 ; min = (($1%86400)%3600)/60 ; printf "%dd %02d:%02d\n" , day , hour, min}' /proc/uptime)

	UPTIME_SEC=$(awk '{ printf "%d" , $1 }' /proc/uptime )
#	UPTIME_SEC=99999999
## check uptime is over 1 year (60sec*60min*24hours*365days=31536000)
	if [ $UPTIME_SEC -ge 31536000 ] ; then
#		UPTIME_RESULT=$(FUNC_PRINT_ATTENTION "Uptime" "$UPTIME_VALUE" )
		FUNC_PRINT_ATTENTION "Uptime" "$UPTIME_VALUE (over 1y)\n"
	else
#		UPTIME_RESULT=$(printf "Uptime: $UPTIME_VALUE ${PRINT_FINE}")
		printf "Uptime: $UPTIME_VALUE ${PRINT_FINE}\n"
	fi

## print resource check results

#	echo -e "$MEM_RESULT\n$SWAP_RESULT\n$ZOMBIE_RESULT\n$IDLE_RESULT\n$UPTIME_RESULT"

## check each load average is upper then total processors
	
	# SCORE=0
	# for z in $(awk '{ printf "%d\n%d\n%d\n", $1,$2,$3 }' /proc/loadavg) ; do

		# if [ $z -ge $(nproc) ] ; then
			# echo -e "\e[3;1;31mATTENTION\e[23;22;0m:\e[1mLoad average\e[22m: load average is more then cores : $z" 
			# SCORE=$(($SCORE + 1))
		# fi
	# done;

# ## print message if all of load average's are fine 

	# if [ $SCORE == 0 ] ; then
	# echo -e "Load average is \e[1;32mFINE\e[22;0m" 
	# fi
	
	# AVG_COUNT=0
	# for z in $(awk '{ printf "%d\n%d\n%d\n", $1,$2,$3 }' /proc/loadavg) ; do
		# if [ $z -ge $(nproc) ] ; then
			# FUNC_PRINT_ATTENTION "Load Average" "$(awk '{ printf "1min:%d 5min:%d 15min:%d", $1,$2,$3 }' /proc/loadavg) (over $(nproc))\n"
			# AVG_COUNT=$(($AVG_COUNT + 1))
		# fi		
	# done
	# if [ $AVG_COUNT == 0 ] ; then
		# printf "Load Average is ${PRINT_FINE}\n"
	# fi
	
	if [ $(awk '{ printf "%d", $1 }' /proc/loadavg) -ge $(nproc) ] \
	|| [ $(awk '{ printf "%d", $2 }' /proc/loadavg) -ge $(nproc) ] \
	|| [ $(awk '{ printf "%d", $3 }' /proc/loadavg) -ge $(nproc) ] ; then
		FUNC_PRINT_ATTENTION "Load Average" "$(awk '{ printf "1min:%d 5min:%d 15min:%d", $1,$2,$3 }' /proc/loadavg) (over $(nproc))\n"
	else
		printf "Load Average is ${PRINT_FINE}\n"
	fi
}
####################################################
# These modules collected into DISK_CHECK function #
####################################################
function DISK_USEAGE_CHECK {

## Collect diskname 
	DISK_MOUNTPOINT=$(df -P -x devtmpfs -x tmpfs | sed '1d' | awk '{print $6}')
	for i in $DISK_MOUNTPOINT ; do
		DISK_USAGE=$(df $i |  sed '1d' | awk '{printf "%d", $5}')
		if [ $DISK_USAGE -gt 80 ] ; then
			FUNC_PRINT_ATTENTION "Disk usage" "$(df -P $i | sed '1d' | awk '{ printf "FS: %s MOUNTPOINT: %s USE: %d (over 80)" , $1 ,$6, $5}')\n"
#			df -P $i | sed '1d' | awk '{ printf "\t└── \033[3;1;31mATTENTION\033[23;22;0m:\033[1mDiskuseage\033[22m: "$6" disk useage is more then 80 percent\n"}'
		else
			df -P $i | sed '1d' | awk  '{ printf "%s (source: %s) Usage: %d " ,$6, $1, $5}'
			printf "${PRINT_FINE}\n"
		fi
	done
}
###############################
function MULTIPATH_USEAGE_CHECK {

### multipath service running check
SERVICE multipathd
MULTIPATH_SERV=$SERVICEVAL

## multipath package check
if [ $(rpm -qa | grep device-mapper-multipath | wc -l) -gt 0 ] ; then
	echo -e "Multipath package Found" 
	MULTIPATH_PKG=1
fi

## multipath config file check
if [ -f /etc/multipath.conf ] ; then
	echo -e "Multipath config file Found" 
	MULTIPATH_CFG=1
fi

## Three check point about using multipath service
if [ $MULTIPATH_SERV == 1 ] && [ $MULTIPATH_PKG == 1 ] && [ $MULTIPATH_CFG == 1 ] ; then
	echo -e "$HOSTNAME is using multipath service" 
## value for grabbing alias name list
	MULTIPATH_ALIAS=$(multipath -l -v1)
## value for check multipath link fault
	MULTIPATH_CHK=$(multipath -ll | egrep -i "failed|faulty|offline" | wc -l)
## Check multipath link
	if [ $MULTIPATH_CHK -gt 0 ] ; then
## showing multipath alias list and faild link
		multipath -ll | egrep -wi "^$MULTIPATH_ALIAS|failed|faulty|offline"
#		echo -e "\t└─── \e[3;1;31mATTENTION\e[23;22;0m:\e[1mMultipath\e[22m: link down occured" 
		FUNC_INDENT
		FUNC_PRINT_ATTENTION "Multipath" "link down\n"
	elif [ 0 == $(multipath -ll | wc -l) ] ; then
#		echo -e "\t└─── \e[3;1;31mATTENTION\e[23;22;0m:\e[1mMultipath\e[22m: $HOSTNAME must edit multipath.conf file OR login to iscsi node first"
		FUNC_INDENT
		FUNC_PRINT_ATTENTION "Multipath" "Check wwid in multipath.conf OR login to iscsi node\n"
	else
		echo -e "Multipath is ${PRINT_FINE}" 
	fi
else
	echo -e "multipath not using now"
fi
}
#############################################################################
function MOUNT_CHECK {

## get mountpoint list from /etc/fstab
	FSTAB_LIST=$(sed -n '/^[^#].*/p' /etc/fstab | awk '{if($3 != "swap" && $3 != "tmpfs" && $3 != "devpts" && $3 != "sysfs" && $3 != "proc" ) print $2}')
## match each "/etc/fstab"'s list (except swap) with /proc/mounts
## using grep -w options to exactly match "root" directory, not all directory
for i in $FSTAB_LIST ; do
	MOUNTCHK=$(grep -w $i /proc/mounts | wc -l)
	if [ $MOUNTCHK == 0 ] ; then
		sed -n '/^[^#].*/p' /etc/fstab | awk -v i=$i '{ if ( $2 == i ) {print "\033[4m"$0"\033[24m"} }'
#		FUNC_PRINT_UNDERLINE $(sed -n '/^[^#].*/p' /etc/fstab | awk -v i=$i '{ if ( $2 == i ) {print $0} }')
#		echo -e "\t└── \e[3;1;31mATTENTION\e[23;22;0m:\e[1mfstab\e[22m: mountpoint $i didn't mounted yet" 
		FUNC_INDENT
		FUNC_PRINT_ATTENTION "fstab" "mountpoint $i didn't mounted yet\n"
	else
		echo -e "Mountpoint $i is ${PRINT_FINE}" 
	fi
done
}
#############################################################################
function DISK_CHECK {
## for collapse disk check module functions
TITLE_MONITORING "Disk-Related"
echo -e "${MAKE_ITALIC}Check ${MAKE_BOLD_ITALIC}Disk usage${RESET_ANSI}...\n"
DISK_USEAGE_CHECK
echo -e "\n${MAKE_ITALIC}Check ${MAKE_BOLD_ITALIC}Mountpoints${RESET_ANSI}...\n"
MOUNT_CHECK
echo -e "\n${MAKE_ITALIC}Check ${MAKE_BOLD_ITALIC}Multipath${RESET_ANSI}...\n"
MULTIPATH_USEAGE_CHECK
}
#############################################################################

#############################################################################
function KDUMP_CHECK {
	TITLE_MONITORING "Kdump"
	SERVICE kdump
	echo -e " "
	if [ 1 == $SERVICEVAL ] ; then
		echo -e "Kdump service is ${PRINT_FINE}"
	else
		FUNC_PRINT_ATTENTION "Kdump" "Kdump service didn't active\n"
#		echo -e "\e[3;1;31mATTENTION\e[23;22;0m:\e[1mKdump\e[22m: Kdump service didn't active"
	fi
}

## end main monitoring module
####################################################

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


### log monitoring function and variable

## filter /var/log/messages

TITLE_MONITORING "Log"

read -s -n1 -p "(Press Enter to Continue)"
READ_LOG_MORE

# LOOP_CONTROL=1

# while [ $LOOP_CONTROL != 0 ]  ; do


# cat  << EOF

# ##################################################
# #                Choose Action                   #       
# ##################################################
# #Press "1|yes|y" to Read log                     #
# #Press "2|no|n" to Print monitoring script again #
# #Press "0" to Break loop                         #
# ##################################################
# EOF
# read LOOP_CONTROL

# case $LOOP_CONTROL in
	# 0)
		# break
		# ;;
	# 1|"yes"|"YES"|"y"|"Y")
		# READ_LOG_MORE
		# ;;
	# 2|"no"|"NO"|"n"|"N"|"nope"|"NOPE")
		# MAIN_LOOP
		# ;;
	# *)
		# continue
		# ;;
# esac
# done





