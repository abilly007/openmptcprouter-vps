#!/bin/sh
SHADOWSOCKS_PASS=${SHADOWSOCKS_PASS:-$(head -c 32 /dev/urandom | base64 -w0)}
GLORYTUN_PASS=${GLORYTUN_PASS:-$(od  -vN "32" -An -tx1 /dev/urandom | tr '[:lower:]' '[:upper:]' | tr -d " \n")}
#NBCPU=${NBCPU:-$(nproc --all | tr -d "\n")}
NBCPU=${NBCPU:-$(grep -c '^processor' /proc/cpuinfo | tr -d "\n")}
OBFS=${OBFS:-no}
MLVPN=${MLVPN:-no}
OPENVPN=${OPENVPN:-no}
INTERFACE=${INTERFACE:-$(ip -o -4 route show to default | awk '{print $5}' | tr -d "\n")}
CENTOS_VERSION=$(sed -r 's/.* ([0-9]+)\..*/\1/' /etc/centos-release)

set -e
umask 0022
update="0"
if [ $CENTOS_VERSION -ne 7 ]; then
	echo "This script only work with CentOS Linux 7.x"
	exit 1
fi
# Fix old string...
if grep --quiet 'OpenMPCTProuter VPS' /etc/motd ; then
	sed -i 's/OpenMPCTProuter/OpenMPTCProuter/g' /etc/motd
fi
if grep --quiet 'OpenMPTCProuter VPS' /etc/motd ; then
	update="1"
fi
# Install mptcp kernel
if [ ! -f "/etc/yum.repos.d/bintray-cpaasch-rpm.repo" ]; then
	cat > /etc/yum.repos.d/bintray-cpaasch-rpm.repo <<-EOF
	#bintray-cpaasch-rpm - packages by cpaasch from Bintray
	[bintray-cpaasch-rpm]
	name=bintray-cpaasch-rpm
	baseurl=https://dl.bintray.com/cpaasch/rpm
	gpgcheck=0
	repo_gpgcheck=0
	enabled=1
	priority=1
	EOF
fi
#
if ! dmesg | grep MPTCP ; then
    # 
    yum -y install kernel-4.14.24.mptcp
	#
	grub2-set-default "CentOS Linux (4.14.24.mptcp) 7 (Core)" 
fi

#install shadowsocks-libev
yum install epel-release -y
yum install git gcc gettext autoconf libtool automake make pcre-devel asciidoc xmlto c-ares-devel libev-devel libsodium-devel mbedtls-devel -y

cd /tmp
rm -rf /tmp/shadowsocks-libev-nocrypto
git clone https://github.com/abilly007/shadowsocks-libev-nocrypto.git
cd shadowsocks-libev-nocrypto
./configure
make && make install

# Get shadowsocks optimization
wget -O /etc/sysctl.d/90-shadowsocks.conf https://www.openmptcprouter.com/server/shadowsocks.conf

# Install shadowsocks config and add a shadowsocks by CPU
if [ "$update" = "0" ]; then
        mkdir -p /etc/shadowsocks-libev
	wget -O /etc/shadowsocks-libev/config.json https://www.openmptcprouter.com/server/config.json
	SHADOWSOCKS_PASS_JSON=$(echo $SHADOWSOCKS_PASS | sed 's/+/-/g; s/\//_/g;')
	sed -i "s:MySecretKey:$SHADOWSOCKS_PASS_JSON:g" /etc/shadowsocks-libev/config.json
fi
sed -i 's:aes-256-cfb:chacha20:g' /etc/shadowsocks-libev/config.json
# Rename bzImage to vmlinuz, needed when custom kernel was used
if [ ! -f "/etc/systemd/system/shadowsocks-libev-server@config.service" ]; then
     cat > /etc/systemd/system/shadowsocks-libev-server@config.service <<-EOF
	[Unit] 
	Description=Shadowsocks-libev-server
	[Service] 
	TimeoutStartSec=0 
	ExecStart=/usr/local/bin/ss-server -c /etc/shadowsocks-libev/config.json 
	[Install] 
	WantedBy=multi-user.target
	EOF
fi
systemctl enable shadowsocks-libev-server@config.service
if [ $NBCPU -gt 1 ]; then
	for i in $NBCPU; do
		ln -fs /etc/shadowsocks-libev/config.json /etc/shadowsocks-libev/config$i.json
		systemctl enable shadowsocks-libev-server@config$i.service
	done
fi
# Add OpenMPTCProuter VPS script version to /etc/motd
if grep --quiet 'OpenMPTCProuter VPS' /etc/motd; then
	sed -i 's:< OpenMPTCProuter VPS [0-9]*\.[0-9]* >:< OpenMPCTProuter VPS 0.3 >:' /etc/motd
else
	echo '< OpenMPTCProuter VPS 0.3 >' >> /etc/motd
fi

if [ "$update" = "0" ]; then
	# Display important info
	echo '===================================================================================='
	echo 'OpenMPTCProuter VPS is now configured !'
	echo '===================================================================================='
	echo '  /!\ You need to reboot to enable MPTCP, shadowsocks, glorytun and shorewall /!\'
	echo '------------------------------------------------------------------------------------'
	echo ' After reboot, check with uname -a that the kernel name contain mptcp.'
	echo ' Else, you may have to modify GRUB_DEFAULT in /etc/defaut/grub'
	echo '===================================================================================='
	
else
	echo '===================================================================================='
	echo 'OpenMPTCProuter VPS is now updated !'
	echo 'Keys are not changed, shorewall rules files preserved'
	echo '===================================================================================='
	echo 'Restarting systemd network...'
fi
