exec > >(tee /var/log/vvii.log|logger -t vvii -s 2>/dev/console) 2>&1
set -e -x
# Apt-install various things necessary for virtualbox guest additions, chef, puppet
# etc., and remove optional things to trim down the machine.
apt-get -y update
apt-get -y upgrade
apt-get -y install linux-headers-$(uname -r) #chef-server-webui puppet
apt-get clean

# Install Ruby from source in /opt so that users of Vagrant
# can install their own Rubies using packages or however.
# We must install the 1.8.x series since Puppet doesn't support
# Ruby 1.9 yet.
wget http://ftp.ruby-lang.org/pub/ruby/1.8/ruby-1.8.7-p334.tar.gz
tar xvzf ruby-1.8.7-p334.tar.gz
cd ruby-1.8.7-p334
./configure --prefix=/opt/ruby
make
make install
cd ..
rm -rf ruby-1.8.7-p334*

# Install RubyGems 1.7.2
wget http://production.cf.rubygems.org/rubygems/rubygems-1.7.2.tgz
tar xzf rubygems-1.7.2.tgz
cd rubygems-1.7.2
/opt/ruby/bin/ruby setup.rb
cd ..
rm -rf rubygems-1.7.2*

# Installing chef & Puppet
/opt/ruby/bin/gem install chef --no-ri --no-rdoc
/opt/ruby/bin/gem install puppet --no-ri --no-rdoc

# Add /opt/ruby/bin to the global path as the last resort so
# Ruby, RubyGems, and Chef/Puppet are visible
echo 'PATH=$PATH:/opt/ruby/bin/'> /etc/profile.d/vagrantruby.sh

# # update rubygems to 1.3.7
# gem install rubygems-update
# /var/lib/gems/1.8/bin/update_rubygems
# gem update --system 1.3.7
# # FATAL: Gem::InstallError: gem_package[transmission-simple] (transmission::default line 31)
# # had an error: multi_json requires RubyGems version >= 1.3.6
# gem install multi_json # fail when done in chef-solo, but not here FIXME

# Setup sudo to allow no-password sudo for "admin"
cp /etc/sudoers /etc/sudoers.orig
sed -i -e '/Defaults\s\+env_reset/a Defaults\texempt_group=admin' /etc/sudoers
sed -i -e 's/%admin ALL=(ALL) ALL/%admin ALL=NOPASSWD:ALL/g' /etc/sudoers

# Installing vagrant keys
mkdir /home/vagrant/.ssh
chmod 700 /home/vagrant/.ssh
cd /home/vagrant/.ssh
wget --no-check-certificate 'http://github.com/mitchellh/vagrant/raw/master/keys/vagrant.pub' -O authorized_keys
chmod 600 /home/vagrant/.ssh/authorized_keys
chown -R vagrant /home/vagrant/.ssh

# Installing the virtualbox guest additions
VBOX_VERSION=$(cat /home/vagrant/.vbox_version)
cd /tmp
wget http://download.virtualbox.org/virtualbox/$VBOX_VERSION/VBoxGuestAdditions_$VBOX_VERSION.iso
mount -o loop VBoxGuestAdditions_$VBOX_VERSION.iso /mnt
sh /mnt/VBoxLinuxAdditions.run
umount /mnt

rm VBoxGuestAdditions_$VBOX_VERSION.iso

# Remove kernel-headers used for building VBoxGuestAdditions, since they aren't needed anymore
apt-get -y remove linux-headers-$(uname -r)
apt-get -y autoremove

# Zero out the free space to save space in the final image:
dd if=/dev/zero of=/EMPTY bs=1M || true # exit code for dd is non-zero when disk fills
rm -f /EMPTY

# Removing leftover leases and persistent rules
echo "cleaning up dhcp leases"
rm -rf /var/lib/dhcp3/*

# Make sure Udev doesn't block our network
# http://6.ptmc.org/?p=164
echo "cleaning up udev rules"
rm -rf /etc/udev/rules.d/70-persistent-net.rules
mkdir /etc/udev/rules.d/70-persistent-net.rules
rm -rf /dev/.udev/
rm -rf /lib/udev/rules.d/75-persistent-net-generator.rules

echo "Adding a 2 sec delay to the interface eth0 up, to make the dhclient happy"
echo "Adding a a static setup with nat for the brige interface for 172.16.123.123 network"
cat <<EOF >> /etc/network/interfaces
pre-up sleep 2

auto eth1
iface eth1 inet static
	address 172.16.123.123
	netmask 255.255.255.0
	up sleep 5; echo 1 > /proc/sys/net/ipv4/ip_forward ; iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE ; service dnsmasq restart 
EOF

exit
