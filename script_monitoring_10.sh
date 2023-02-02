#!/bin/bash
############################################################################################
function TITLE {
BOLD_VIOLET=$(echo -e "\033[23;1;38;5;104m")
RESET_ASCII=$(echo -e "\033[0m")
BOLD_YELLOW=$(echo -e "\033[1;3;38;5;228m") 
cat << EOF
====================================================================
                    ${BOLD_VIOLET}STARTING ${BOLD_YELLOW}MONITORING SCRIPT${RESET_ASCII}
====================================================================
EOF
}
############################################################################################

## define function for server RHEL versions
function SERVICE {
## print service status each rhel version and
## useing SERVICEVAL is return value for distinguish active or inactive
	if [ 1 == $(cat /etc/redhat-release | grep "Santiago" | wc -l) ] ; then
		service $1 status 2>/dev/null
		SERVICEVAL=$(service $1 status | egrep -w "running|operational" | wc -l)
	else
		systemctl status --no-pager $1 2>/dev/null | egrep --color=never "\.service - |Active:"
		SERVICEVAL=$(systemctl is-active $1 | egrep -w "active" | wc -l)
	fi
}

## define function for title
function TITLE_MONITORING {
echo -e "\n\e[1m------------\e[3;33m$1 Check\e[23;39m------------\e[0m\n"
}

##########################################
## define function for NTP Checking

function NTP_RESULT {
## only for NTP check to make this script Modularization
	if [ $1 -ge 1 ] ; then
		echo -e "$2 sync works \e[1;32mFINE\e[22;0m"
	elif [ $1 == 0 ] ; then
		echo -e "\t└─── \e[3;1;31mATTENTION\e[23;22;0m:\e[1m$2\e[22m: $2 ntp server not syncing now"
	fi
}

function CHRONYD {
## check chronyd with modularized script
	echo -e " "
	chronyc sources
	echo -e " "
	CHRONYCHK=$(chronyc sources | egrep "^\^\*" | wc -l)
	NTP_RESULT $CHRONYCHK chronyd
}

function NTPD {
## check ntpd with modularized script
	echo -e " "
	ntpq -p
	echo -e " "
	NTPDCHK=$(ntpq -p | egrep "^\*" | wc -l)
	NTP_RESULT $NTPDCHK ntpd	
}

#############################################################################################
## Variables and function for logs

## define vars for log
MONTH1=$(date +%b) ; MONTH2=$(date -d "1month ago" +%b) ; MONTH3=$(date -d "2month ago" +%b)

## defind vars for logtempfile
TMP_DATE=$(date +%Y-%m-%d-%H-%M-%S-%N)
TEMP_LOG_FILE1=$(mktemp tmplog-1-$TMP_DATE-thisisdummyfileandwillremovesoon-XXXXXXXXXXXXXX)

## define functions for log monitoring

function FILTER1 {
cat /var/log/messages* | egrep "^$MONTH1|^$MONTH2|^$MONTH3" | egrep -i 'warn|err|crit|fatal|down|fail|alert|abort' \
| egrep -vi "\<info\>|\<notice\>|interrupt|override|preferred|team will not be maintained|ip6|ipv6ll|failure 1|Reached target Shutdown" 
}

function READ_LOG_MORE {
FILTER1 > ./$TEMP_LOG_FILE1
more ./$TEMP_LOG_FILE1	
}


#########################################################
#                                                       #
## start main monitoring module functions               #
#                                                       #
#########################################################

function BASE_INFORMATION {

TITLE_MONITORING "Basic Information"

### check hypervisor system
	if [ $(virt-what | wc -w ) -gt 0 ] ; then
		virt=1
		echo -e "$HOSTNAME is \e[1m$( virt-what | tr "\n" " " ) VM\e[22m"
	else
		virt=0
		echo -e "$HOSTNAME is \e[1mphysical server\e[22m"
	fi

### show system OS version
	echo -e "$HOSTNAME is using \e[1m$(cat /etc/redhat-release)\e[22m"
}

##########################################################

function NIC_CHECK {

	TITLE_MONITORING "NIC error"
	
## get list of NIC
	NICLS=$(sed -n '3,$p' /proc/net/dev | sed '/\slo\:/d' |awk '{print $1}' | tr ":" " ")

## start check per NIC
	for i in $NICLS ; do
## collect TXDROP or TXCOLL per NIC
		TXDROP=$(awk -v i=$i":" '{if( $1 == i ) print $12}' /proc/net/dev)
### WARNING!! this is redefining value for drop test #####################################################################
#		TXDROP=$(awk '{if( $1 == "ens256:" ) gsub (0,255,$12); print $0}' /proc/net/dev | awk -v i=$i":" '{if( $1 == i ) print $12}')
########################################################################################################################
		TXCOLL=$(awk  -v i=$i":" '{if( $1 == i ) print $14}' /proc/net/dev)
### WARNING!! this is redefining value for collision test#################################################################
#		TXCOLL=$(awk '{if( $1 == "ens161:" ) gsub (0,255,$14); print $0}' /proc/net/dev | awk -v i=$i":" '{if( $1 == i ) print $14}')
########################################################################################################################
## Print TX drop/coll per NIC
		if [ $TXDROP != 0 ] ; then
			TXDROP_RESULT=$(echo -e "\e[3;1;31mATTENTION\e[23;22;0m")
		else
			TXDROP_RESULT=$(echo -e "\e[1;32mFINE\e[22;0m")
		fi
		
		if [ $TXCOLL != 0 ] ; then 
			TXCOLL_RESULT=$(echo -e "\e[3;1;31mATTENTION\e[23;22;0m")
		else 
			TXCOLL_RESULT=$(echo -e "\e[1;32mFINE\e[22;0m")
		fi

		printf "%-10b: TXDROP : %d %b TXCOLL : %d %b\n" $i $TXDROP $TXDROP_RESULT $TXCOLL $TXCOLL_RESULT

## check NIC HW state if had errors
		if [ 0 != $TXDROP ] || [ 0 != $TXCOLL ] ; then
			echo -e "\t\t└── \e[3mSearch \e[23;1m$i\e[3;22m HW state\e[23m" 
			ethtool $i | egrep -iw "Duplex|Auto-negotiation|MDI-X|Link detected" | awk '{print "\t""\t",$0}'
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
			echo -e "\n\e[3m...Reading /proc/net/bonding/$x\e[23m\n ↓"
## get bonding slaves per master
			BONDDEVNIC=$(awk -F ": " '/^\<Slave Interface\>/ { print $2 }' /proc/net/bonding/$x)
## check state per slaves
			for y in $BONDDEVNIC ; do
				DOWNCOUNT=$(sed -n "/^Slave Interface: $y/,/^$/p" /proc/net/bonding/$x | awk -F ": " '/Link Failure Count/ {print $2}' ) 
				BOND_LINK=$(sed -n "/^Slave Interface: $y/,/^$/p" /proc/net/bonding/$x | awk -F ": " '/M?I?I? ?Status/ {print $2}')
				cat /proc/net/bonding/$x | egrep -iw "Slave Interface|Link Failure Count|Status" | sed -n "/$y/,/Link Failure Count:/p" | sed -e 's/\(Slave Interface:.*\)/\1/g' -e 's/\(Link Failure Count:.*\)/    \1/g' -e 's/\([MI ]*Status:.*\)/  \1/g'
				BOND_COUNT=0
				if [ 0 != $DOWNCOUNT ] ; then		
					echo -e "\t└─── \e[3;1;31mATTENTION\e[23;22;0m:\e[1mBonding\e[22m: $x's slave $y has \e[1m$DOWNCOUNT\e[22m downcount"
					BOND_COUNT=$(($BOND_COUNT + 1))
				fi
				if [ $(echo $BOND_LINK) != "up" ] ; then
					echo -e "\t└─── \e[3;1;31mATTENTION\e[23;22;0m:\e[1mBonding\e[22m: $x's slave $y was \e[1mDOWN\e[22m"
					BOND_COUNT=$(($BOND_COUNT + 1))
				fi
				if [ $BOND_COUNT == 0 ] ; then
					echo -e "\t└── $x's slave $y is \e[1;32mFINE\e[22;0m"
				fi
## end downcount check per NICs
			done
## end checking whole bonding dev
		done
## end checking bonding exsist
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
			echo -e "\n\e[3m...Check teamd device $x state\e[23m\n ↓"
## get teaming slave per teaming master		
			TEAMDEVNIC=$(teamnl $x port | awk -F ": " '{ print $2 }')
## check state per slaves
			for y in $TEAMDEVNIC ; do
				DOWNCOUNT=$(teamdctl $x state | sed -n "/$y/,/[^a-z]\<down count\>/p" | awk '/down count/ { print $3 }')
				TEAM_LINK=$(teamdctl $x state | sed -n "/$y/,/[^a-z]\<down count\>/p" | awk '/[^a-z]link:/ { print $2 }')
				teamdctl $x state | egrep -v "link watches:|link summary:|instance|name:|runner:|active port: |setup:| runner:|ports:" | sed -n "/$y/,/down count:/p"
				TEAM_COUNT=0
				if [ 0 != $DOWNCOUNT ] ; then
					echo -e "\t└─── \e[3;1;31mATTENTION\e[23;22;0m:\e[1mTeaming\e[22m: $x 's slave $y has \e[1m$DOWNCOUNT\e[22m downcount"
					TEAM_COUNT=$(($TEAM_COUNT + 1))
				fi
				if [ $(echo $TEAM_LINK) != "up" ] ; then
					echo -e "\t└─── \e[3;1;31mATTENTION\e[23;22;0m:\e[1mTeaming\e[22m: $x 's slave $y was \e[1mDOWN\e[22m"
					TEAM_COUNT=$(($TEAM_COUNT + 1))
				fi
				if [ $TEAM_COUNT == 0 ] ; then
					echo -e "\t└─── $x's slave $y is \e[1;32mFINE\e[22;0m"
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
	

	TITLE_MONITORING "System Resources"
	
## show memory, load average, zombie, swap useage
	free -h 
	echo -e " "
	top -b -n 1 | sed -n '1,3p'
	echo -e " "
	
### CHECK MEMORY ###

## collect parameter from /proc/meminfo
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

### WARNING!!! This line for test this script#####################
# 	MEMLeave=20
##################################################################


## calculate real free space percentage
	MEMCheck=$(echo $MEMLeave $MEMTotal | awk '{printf "%d", $1/$2*100}')

## check real free space percentage is lower then 15
	if [ $(echo $MEMCheck ) -lt 15 ] ; then
		MEM_RESULT=$(echo -e "\e[3;1;31mATTENTION\e[23;22;0m:\e[1mMemory\e[22m: $MEMCheck% FREE" )
	else
		MEM_RESULT=$(echo -e "Memory useage is \e[1;32mFINE\e[22;0m: $MEMCheck% FREE")
	fi	
	
### CHECK SWAP ###
	
## calculate swap using percentage from total memory

	MEMUswap=$(echo $MEMTotal $MEMTswap $MEMFswap | awk '{printf "%d", ($2-$3)/$1*100}')

## check swap using percentage is bigger then 3

	if [ $MEMUswap -ge 3 ] ; then
		SWAP_RESULT=$(echo -e "\e[3;1;31mATTENTION\e[23;22;0m:\e[1mSwap\e[22m: $MEMUswap% USED")
	else
		SWAP_RESULT=$(echo -e "swap space is \e[1;32mFINE\e[22;0m: $MEMUswap% USED") 
	fi

### CHECK ZOMBIE ###

	ZOMBIECOUNT=$(ps -ef | grep -i defunct | grep -v grep | wc -l)
	if [ $ZOMBIECOUNT -gt 0 ] ; then
		ZOMBIE_RESULT=$(echo -e "\e[3;1;31mATTENTION\e[23;22;0m:\e[1mZombie\e[22m: $ZOMBIECOUNT")
	else
		ZOMBIE_RESULT=$(echo -e "no zombies(\e[1;32mFINE\e[22;0m): $ZOMBIECOUNT")
	fi

### CHECK CPU IDLE ###

## grep value from top
	CPU_IDLE=$( top -b -n 1 | sed -n '3p' | awk -F , '{ printf "%d",  $4 }' )
## check CPU idle is OK
	if [ $CPU_IDLE -lt 80 ] ; then
		IDLE_RESULT=$(echo -e "\e[3;1;31mATTENTION\e[23;22;0m:\e[1mIdle\e[22m: $CPU_IDLE%")
	else
		IDLE_RESULT=$(echo -e "Idle CPU's are \e[1;32mFINE\e[22;0m: $CPU_IDLE%")
	fi
	
### CHECK UPTIME ###
	
## calculate uptime to human readable
	UPTIME_VALUE=$(awk '{ \
year=$1/31536000 ;\
week=($1%31536000)/604800 ;\
day=(($1%31536000)%604800)/86400 ;\
hour=((($1%31536000)%604800)%86400)/3600 ;\
min=(((($1%31536000)%604800)%86400)%3600)/60 ;\
sec=(((($1%31536000)%604800)%86400)%3600%60) ;\
printf "%dy %dw %dd %dh %dm %.2fs\n" , year, week, day, hour, min, sec}' /proc/uptime)

## check uptime is over 1 year (60sec*60min*24hours*365days=31536000)
	if [ $(awk '{ printf "%d\n" , $1 }' /proc/uptime ) -ge 31536000 ] ; then
		UPTIME_RESULT=$(echo -e "\e[3;1;31mATTENTION\e[23;22;0m:\e[1mUptime\e[22m: $UPTIME_VALUE" )
	else
		UPTIME_RESULT=$(echo -e "uptime is \e[1;32mFINE\e[22;0m": $UPTIME_VALUE)
	fi

## print resource check results

	echo -e "$MEM_RESULT\n$SWAP_RESULT\n$ZOMBIE_RESULT\n$IDLE_RESULT\n$UPTIME_RESULT"

## check each load average is upper then total processors
	
	SCORE=0
	for z in $(awk '{ printf "%d\n%d\n%d\n", $1,$2,$3 }' /proc/loadavg) ; do

		if [ $z -ge $(nproc) ] ; then
			echo -e "\e[3;1;31mATTENTION\e[23;22;0m:\e[1mLoad average\e[22m: load average is more then cores : $z" 
			SCORE=$(($SCORE + 1))
		fi
	done;

## print message if all of load average's are fine 

	if [ $SCORE == 0 ] ; then
	echo -e "Load average is \e[1;32mFINE\e[22;0m" 
	fi



}
####################################################
# These modules collected into DISK_CHECK function #
####################################################
function DISK_USEAGE_CHECK {

## Collect diskname 
	DISK_MOUNTPOINT=$(df -P -x devtmpfs -x tmpfs | sed '1d' | awk '{print $6}')
	for i in $DISK_MOUNTPOINT ; do
		DISK_WARN=$(df $i |  sed '1d' | awk '{printf "%d", $5}')
		if [ $DISK_WARN -gt 80 ] ; then
			df -P -x devtmpfs -x tmpfs $i | sed '1d' | awk '{ print "FS :",$1,"MOUNTPOINT :",$6,"USE% :",$5 }'
			df -P -x devtmpfs -x tmpfs $i | sed '1d' | awk '{ printf "\t└── \033[3;1;31mATTENTION\033[23;22;0m:\033[1mDiskuseage\033[22m: "$6" disk useage is more then 80 percent\n"}'
		else
			df -P -x devtmpfs -x tmpfs $i | sed '1d' | awk '{ print $6,"(source:",$1")","disk useage is \033[1;32mFINE\033[22;0m"}'
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
	MULTIPATH_CHK=$(multipath -ll | egrep -i "failed|faulty" | wc -l)
## Check multipath link
	if [ $MULTIPATH_CHK -gt 0 ] ; then
## showing multipath alias list and faild link
		multipath -ll | egrep -wi "^$MULTIPATH_ALIAS|failed|faulty"
		echo -e "\t└─── \e[3;1;31mATTENTION\e[23;22;0m:\e[1mMultipath\e[22m: link down occured" 
	elif [ 0 == $(multipath -ll | wc -l) ] ; then
		echo -e "\t└─── \e[3;1;31mATTENTION\e[23;22;0m:\e[1mMultipath\e[22m: $HOSTNAME must edit multipath.conf file OR login to iscsi node first"
	else
		echo -e "Multipath is \e[1;32mFINE\e[22;0m" 
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
		echo -e "\t└── \e[3;1;31mATTENTION\e[23;22;0m:\e[1mfstab\e[22m: mountpoint $i didn't mounted yet" 
	else
		echo -e "Mountpoint $i is \e[1;32mFINE\e[22;0m" 
	fi
done
}
#############################################################################
function DISK_CHECK {
## for collapse disk check module functions
TITLE_MONITORING "Disk-Related"

DISK_USEAGE_CHECK
echo -e "\n\e[3mCheck Mountpoints...\e[23m\n"
MOUNT_CHECK
echo -e "\n\e[3mCheck Multipath...\e[23m\n"
MULTIPATH_USEAGE_CHECK
}
#############################################################################
function NTP_CHECK {
TITLE_MONITORING "NTP"

## use score var to check if none of running ntp services
SCORE=0
## use predefined function to check ntp service running and syncronization server well
## check chronyd first
SERVICE chronyd
if [ 1 == $SERVICEVAL ] ; then
	CHRONYD
else
	SCORE=$(($SCORE + 1))	
fi
## check ntpd next
SERVICE ntpd
if [ 1 == $SERVICEVAL ] ; then
	NTPD
else
	SCORE=$(($SCORE + 1))	
fi
## message if no running ntp client service
if [ 2 == $SCORE ] ; then
	echo -e "\t└─── \e[3;1;31mATTENTION\e[23;22;0m:\e[1mNTP Sync\e[22m: no NTP service"
fi
}
#############################################################################
function KDUMP_CHECK {
	TITLE_MONITORING "Kdump"
	SERVICE kdump
	echo -e " "
	if [ 1 == $SERVICEVAL ] ; then
		echo -e "Kdump service is \e[1;32mFINE\e[22;0m"
	else
		echo -e "\e[3;1;31mATTENTION\e[23;22;0m:\e[1mKdump\e[22m: Kdump service didn't active"
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

read -s -n1 -p "(Press Enter to Continue)" NULL_DUMMY_VAR
READ_LOG_MORE

LOOP_CONTROL=1

while [ $LOOP_CONTROL != 0 ]  ; do


cat  << EOF

##################################################
#                Choose Action                   #       
##################################################
#Press "1|yes|y" to Read log                     #
#Press "2|no|n" to Print monitoring script again #
#Press "0" to Break loop                         #
##################################################
EOF
read LOOP_CONTROL

case $LOOP_CONTROL in
	0)
		break
		;;
	1|"yes"|"YES"|"y"|"Y")
		READ_LOG_MORE
		;;
	2|"no"|"NO"|"n"|"N"|"nope"|"NOPE")
		MAIN_LOOP
		;;
	*)
		continue
		;;
esac
done



yes | rm -f ./$TEMP_LOG_FILE1

