#!/bin/bash

EXT_IF="eth0"
EXT_IP=""
CERT_EMAIL_TO=""
while [[ ! ${EXT_IP} =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]]; do
    echo Please enter Public IP addr.
    read EXT_IP
done

yum -y install epel-release
yum -y install openvpn easy-rsa mailx
cd /etc/openvpn && mkdir -p easy-rsa/keys
cat <<EOF > server.conf
local 0.0.0.0
mssfix 1400
port 443
proto tcp
dev tun
ca easy-rsa/keys/ca.crt
cert easy-rsa/keys/server.crt
key easy-rsa/keys/server.key  # This file should be kept secret
dh easy-rsa/keys/dh2048.pem
tls-auth easy-rsa/keys/ta.key 0
#plugin /usr/lib64/openvpn/plugins/openvpn-plugin-auth-pam.so login
#client-cert-not-required
#username-as-common-name
server 10.8.0.0 255.255.255.0
push "redirect-gateway bypass-dhcp"
push "dhcp-option DNS 8.8.8.8"
push "dhcp-option DNS 8.8.4.4"
duplicate-cn
#cipher BF-CBC        # Blowfish (default)
tls-cipher TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384
cipher AES-256-CBC
auth SHA512
reneg-sec 600
tls-version-min 1.2
max-clients 10
user openvpn
group openvpn
persist-key
persist-tun
keepalive 15 180
status openvpn-status.log
log         openvpn.log
verb 4
EOF

cd easy-rsa
cp -rf /usr/share/easy-rsa/3.0/* /etc/openvpn/easy-rsa/
cat <<EOF >> vars
export KEY_COUNTRY="US"
export KEY_PROVINCE="NY"
export KEY_CITY="New York City"
export KEY_ORG="DigitalOcean"
export KEY_EMAIL="admin@example.com"
export KEY_OU="Community"
export KEY_NAME="server"
export KEY_OU=server
export KEY_CN=localhost.localdomain
EOF

cp -r /usr/share/easy-rsa/3.0/openssl-1.0.cnf /etc/openvpn/easy-rsa/openssl.cnf
source ./vars
./easyrsa init-pki
./easyrsa build-ca nopass
./easyrsa build-server-full server nopass
./easyrsa gen-dh
./easyrsa build-client-full client nopass
openvpn --genkey --secret keys/ta.key

cp -ra pki/issued/client.crt keys/
cp -ra pki/ca.crt keys/
cp -ra pki/private/client.key keys/
cp -ra pki/issued/server.crt keys/
cp -ra pki/private/server.key keys/
cp -ra pki/dh.pem keys/dh2048.pem

systemctl enable openvpn@server.service
systemctl start openvpn@server.service

echo "net.ipv4.ip_forward = 1" >> /etc/sysctl.conf
sysctl -p

systemctl disable firewalld
systemctl stop firewalld
systemctl enable iptables.service
systemctl start iptables.service

iptables -t nat -A POSTROUTING -s 10.8.0.0/24 -o ${EXT_IF} -j MASQUERADE
iptables -I INPUT 1 -p tcp -m tcp --dport 443 -m state --state NEW -j ACCEPT
iptables -I FORWARD 1 -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables -I FORWARD 1 -s 10.8.0.0/24 -i tun0 -o ${EXT_IF} -j ACCEPT
#firewall-cmd --zone=`firewall-cmd --get-zone-of-interface=${EXT_IF}` --add-service=https
#firewall-cmd --zone=`firewall-cmd --get-zone-of-interface=${EXT_IF}` --add-service=https --permanent
#firewall-cmd --direct --add-rule ipv4 nat POSTROUTING 0 -o ${EXT_IF} -j MASQUERADE
#firewall-cmd --direct --add-rule ipv4 filter FORWARD 0 -i tun* -o ${EXT_IF} -j ACCEPT
#firewall-cmd --direct --add-rule ipv4 filter FORWARD 0 -i ${EXT_IF} -o tun* -m state --state RELATED,ESTABLISHED -j ACCEPT
iptables-save > /etc/sysconfig/iptables


cd /etc/openvpn/client/
cat <<EOF > client.conf
client
mssfix 1400
dev tun
proto tcp
remote ${EXT_IP} 443
resolv-retry infinite
nobind
persist-key
persist-tun
comp-lzo
verb 3
tls-cipher TLS-ECDHE-RSA-WITH-AES-256-GCM-SHA384
cipher AES-256-CBC
auth SHA512
key-direction 1
EOF

echo "<ca>" >> client.conf
cat /etc/openvpn/easy-rsa/keys/ca.crt >> client.conf
echo "</ca>" >> client.conf
echo "<cert>" >> client.conf
cat /etc/openvpn/easy-rsa/keys/client.crt >> client.conf
echo "</cert>" >> client.conf
echo "<key>" >> client.conf
cat /etc/openvpn/easy-rsa/keys/client.key >> client.conf
echo "</key>" >> client.conf
echo "<tls-auth>" >> client.conf
cat /etc/openvpn/easy-rsa/keys/ta.key >> client.conf
echo "</tls-auth>" >> client.conf


cp client.conf client.ovpn
if ![ -z $CERT_EMAIL_TO ]; then 
echo "Openvpn Config attached" | mail -a client.ovpn -s "Openvpn Config" ${CERT_EMAIL_TO};
fi
