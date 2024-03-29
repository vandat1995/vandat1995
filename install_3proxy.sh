#!/bin/sh

echo "ulimit -n 188898" >> /root/.bashrc 
sysctl -p

random() {
	tr </dev/urandom -dc A-Za-z0-9 | head -c5
	echo
}

array=(1 2 3 4 5 6 7 8 9 0 a b c d e f)
gen64() {
	ip64() {
		echo "${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}${array[$RANDOM % 16]}"
	}
	echo "$1:$(ip64):$(ip64):$(ip64):$(ip64)"
}
install_3proxy() {
    echo "installing 3proxy"
    URL="https://github.com/z3APA3A/3proxy/archive/3proxy-0.8.6.tar.gz"
    wget -qO- $URL | bsdtar -xvf-
    cd 3proxy-3proxy-0.8.6
    make -f Makefile.Linux
    mkdir -p /usr/local/etc/3proxy/{bin,logs,stat}
    cp src/3proxy /usr/local/etc/3proxy/bin/
    cp ./scripts/rc.d/proxy.sh /etc/init.d/3proxy
    chmod +x /etc/init.d/3proxy
    chkconfig 3proxy on
    cd $WORKDIR
}

gen_3proxy() {
    cat <<EOF
nserver 8.8.8.8
nserver 1.1.1.1
maxconn 6000
nscache 65536
timeouts 1 5 30 60 180 1800 15 60
setgid 65535
setuid 65535
flush
auth strong

users $(awk -F "/" 'BEGIN{ORS="";} {print $1 ":CL:" $2 " "}' ${WORKDATA})

$(awk -F "/" '{print "auth strong iponly\n" \
"allow " $1 "\n" \
"allow $/usr/local/etc/3proxy/whitelist.txt" "\n" \
"proxy -6 -n -a -p" $4 " -i" $3 " -e"$5"\n" \
"flush\n"}' ${WORKDATA})
EOF
}
fix_initd() {
    cat <<EOF
#!/bin/sh

case "$1" in
   start)
       echo Starting 3Proxy

       /usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg

       RETVAL=$?
       echo
       [ $RETVAL ]
       ;;

   stop)
       echo Stopping 3Proxy
       pkill -f '3proxy'
       RETVAL=$?
       echo
       [ $RETVAL ]
       ;;

   restart|reload)
       echo Reloading 3Proxy
       pkill -f '3proxy'
       /usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
       ;;
   *)
       echo Usage: $0 "{start|stop|restart}"
       exit 1
esac
exit 0
EOF
}

gen_proxy_file_for_user() {
    cat >proxy.txt <<EOF
$(awk -F "/" '{print $3 ":" $4 ":" $1 ":" $2 }' ${WORKDATA})
EOF
}

upload_proxy() {
    local PASS=$(random)
    zip --password $PASS proxy.zip proxy.txt
    URL=$(curl -s --upload-file proxy.zip https://transfer.sh/proxy.zip)

    echo "Proxy is ready! Format IP:PORT:LOGIN:PASS"
    echo "Download zip archive from: ${URL}"
    echo "Password: ${PASS}"

}
gen_data() {
    seq $FIRST_PORT $LAST_PORT | while read port; do
        echo "usr$(random)/pass$(random)/$IP4/$port/$(gen64 $IP6)"
    done
}

gen_iptables() {
    cat <<EOF
    $(awk -F "/" '{print "iptables -I INPUT -p tcp --dport " $4 "  -m state --state NEW -j ACCEPT"}' ${WORKDATA}) 
EOF
}

gen_ifconfig() {
    cat <<EOF
$(awk -F "/" '{print "ifconfig eth0 inet6 add " $5 "/64"}' ${WORKDATA})
EOF
}
echo "installing apps"
yum -y install gcc net-tools bsdtar zip supervisor >/dev/null

install_3proxy
sed -i "s/minfds=.*/minfds=20240/g" /etc/supervisord.conf 
sed -i "s/minprocs=.*/minprocs=2001/g" /etc/supervisord.conf 
#create supervisord config for 3 proxy
cat <<EOF > /etc/supervisord.d/service.ini 
[program:3proxy]
command=/usr/local/etc/3proxy/bin/3proxy /usr/local/etc/3proxy/3proxy.cfg
autostart=true
startsecs=10
autorestart=true
exitcodes=1
EOF
systemctl enable supervisord
echo "working folder = /home/proxy-installer"
WORKDIR="/home/proxy-installer"
WORKDATA="${WORKDIR}/data.txt"
mkdir $WORKDIR && cd $_

IP4=$(curl -4 -s icanhazip.com)
IP6=$(curl -6 -s icanhazip.com | cut -f1-4 -d':')

echo "Internal ip = ${IP4}. Exteranl sub for ip6 = ${IP6}"

echo "How many proxy do you want to create? Example 500: "

COUNT=1000
FIRST_PORT=10000
LAST_PORT=$((FIRST_PORT + COUNT))

gen_data >$WORKDIR/data.txt
gen_iptables >$WORKDIR/boot_iptables.sh
gen_ifconfig >$WORKDIR/boot_ifconfig.sh
chmod +x ${WORKDIR}/boot_*.sh /etc/rc.local

gen_3proxy >/usr/local/etc/3proxy/3proxy.cfg
echo "* 127.0.0.1 * *" > /usr/local/etc/3proxy/whitelist.txt

cat >>/etc/rc.local <<EOF
bash ${WORKDIR}/boot_iptables.sh
bash ${WORKDIR}/boot_ifconfig.sh
ulimit -n 188898

EOF

bash /etc/rc.local

#fix_initd > /etc/init.d/3proxy

gen_proxy_file_for_user

upload_proxy
systemctl start supervisord
