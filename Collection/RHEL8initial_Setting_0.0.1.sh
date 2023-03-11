#!/bin/bash

sed -i '/GRUB_CMDLINE_LINUX/s/crashkernel=auto/crashkernel=512M/g'  /etc/default/grub

if [ 0 == $(grep -wc "nmi_watchdog=0" /etc/default/grub) ] ; then
	sed -i '/GRUB_CMDLINE_LINUX/s/"$/ nmi_watchdog=0"/g' /etc/default/grub
elif [ 0 != $(grep -wc "nmi_watchdog=1" /etc/default/grub) ] || [ 0 != $(grep -wc "nmi_watchdog=2" /etc/default/grub) ] ; then
	sed -i '/GRUB_CMDLINE_LINUX/s/\(nmi_watchdog=\)[12]/\10/g' /etc/default/grub
fi

if [ 0 == $(grep -wc "transparent_hugepage=never" /etc/default/grub) ] ; then
	sed -i '/GRUB_CMDLINE_LINUX/s/"$/ transparent_hugepage=never"/g' /etc/default/grub
elif [ 0 != $(grep -wc "transparent_hugepage=always" /etc/default/grub) ] ; then
	sed -i '/GRUB_CMDLINE_LINUX/s/\(transparent_hugepage=\)always/\1never/g' /etc/default/grub
fi


if [ 0 == $(grep -wc "ipv6.disable=1" /etc/default/grub) ] ; then
	sed -i '/GRUB_CMDLINE_LINUX/s/"$/ ipv6.disable=1"/g' /etc/default/grub
elif [ 0 != $(grep -wc "ipv6.disable=0" /etc/default/grub) ] ; then
	sed -i '/GRUB_CMDLINE_LINUX/s/\(ipv6.disable=\)0/\11/g' /etc/default/grub
fi

if [ 0 == $(grep -wc "selinux=0" /etc/default/grub) ] ; then
	sed -i '/GRUB_CMDLINE_LINUX/s/"$/ selinux=0"/g' /etc/default/grub
elif [ 0 != $(grep -wc "selinux=1" /etc/default/grub) ]; then
	sed -i '/GRUB_CMDLINE_LINUX/s/\(selinux=\)1/\10/g' /etc/default/grub
fi



[ -d /sys/firmware/efi ] && grub2-mkconfig -o /boot/efi/EFI/redhat/grub.cfg || grub2-mkconfig -o /boot/grub2/grub.cfg

##### start sysctl conf

cat >> /etc/sysctl.conf << EOF

### Crash and DUMP
EOF

for i in kernel\.sysrq kernel\.panic_on_io_nmi kernel\.panic_on_unrecovered_nmi kernel\.unknown_nmi_panic ; do
	if [ 0 == $(sysctl -b $i) ]; then
		sed -i "s/\(^$i.*\)/#\1/g" /etc/sysctl.conf
		echo "${i} = 1" >> /etc/sysctl.conf
	fi
done

[ 0 != $(grep -c "kernel.core_pattern" /etc/sysctl.conf) ] && sed -i -e 's/^\(kernel\.core_pattern\).*/\1 = /var/crash/core_%e_%p_%h_%u_%t/g' /etc/sysctl.conf || echo 'kernel.core_pattern = /var/crash/core_%e_%p_%h_%u_%t' >> /etc/sysctl.conf

echo "### Process"  >> /etc/sysctl.conf 

[ 120000 != $( awk -F "=" '/kernel\.pid_max/ {printf "%d" , $2}' /etc/sysctl.conf ) ] && sed -i 's/\(kernel\.pid_max\).*/\1 = 120000/g' /etc/sysctl.conf
[ 0 == $(grep -c "kernel.pid_max" /etc/sysctl.conf) ] && echo "kernel.pid_max = 120000" >> /etc/sysctl.conf

echo "### Network" >> /etc/sysctl.conf

[ 0 != $(grep -c "net.ipv4.ip_forward" /etc/sysctl.conf) ] && sed -i 's/^\(net\.ipv4\.ip_forward\).*/\1=0/g' /etc/sysctl.conf || echo "net.ipv4.ip_forward = 0" >> /etc/sysctl.conf

[ 0 != $(grep -c "net.ipv4.conf.default.accept_source_route" /etc/sysctl.conf) ] && sed -i 's/^\(net\.ipv4\.con\f.default\.accept_source_route\).*/\1 = 0/g' /etc/sysctl.conf || echo "net.ipv4.conf.default.accept_source_route = 0" >> /etc/sysctl.conf

[ 8192 != $( awk -F "=" '/net\.core\.somaxconn/ {printf "%d" , $2}' /etc/sysctl.conf ) ] && sed -i 's/\(net\.core\.somaxconn\).*/\1 = 8192/g' /etc/sysctl.conf

[ 0 == $(grep -c "net.core.somaxconn" /etc/sysctl.conf) ] && echo "net.core.somaxconn = 8192" >> /etc/sysctl.conf

[ 8192 != $( awk -F "=" '/net\.core\.somaxconn/ {printf "%d" , $2}' /etc/sysctl.conf ) ] && sed -i 's/\(net\.core\.somaxconn\).*/\1 = 8192/g' /etc/sysctl.conf

[ 0 == $(grep -c "net.core.somaxconn" /etc/sysctl.conf) ] && echo "net.core.somaxconn = 8192" >> /etc/sysctl.conf

[ 8192 != $( awk -F "=" '/net\.ipv4\.tcp_max_syn_backlog/ {printf "%d" , $2}' /etc/sysctl.conf ) ] && sed -i 's/\(net\.ipv4\.tcp_max_syn_backlog\).*/\1 = 8192/g' /etc/sysctl.conf

[ 0 == $(grep -c "net.ipv4.tcp_max_syn_backlog" /etc/sysctl.conf) ] && echo "net.ipv4.tcp_max_syn_backlog = 8192" >> /etc/sysctl.conf


sysctl -p

############

systemctl stop firewalld
systemctl mask firewalld postfix

yum install -y vim bash-completion sysstat yum-utils net-tools lsof bind-utils pciutils tcpdump psmisc nfs-utils psacct strace chrony
sed -i -e 's/^weekly$/monthly/g' -e '/^rotate/s/4$/12/g'  /etc/logrotate.conf
sed -i '/rotate/s/1$/12/g' /etc/logrotate.d/{wtmp,btmp} 
sed -i '/OnCalendar/s/10$/1/g'  /etc/systemd/system/sysstat.service.wants/sysstat-collect.timer 
systemctl daemon-reload
sed -i '/HISTORY/s/28$/90/g' /etc/sysconfig/sysstat
sed -i '/MAILTO/s/root$/""/g' /etc/crontab
[ 0 == $(grep -c "time.bora.net" /etc/chrony.conf) ] && sed -i -e '/^pool/s/^/# /g' -e '/^# Please consider joining/a\server time.bora.net iburst' /etc/chrony.conf
systemctl enable --now chronyd

