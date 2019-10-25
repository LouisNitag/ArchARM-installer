#!/usr/bin/fish

function usage
	echo "./install.fish /dev/device"
	echo "Dependencies: wget parted bsdtar sed"
end

function info
	set_color 555
	echo "[Info]" $argv
	set_color normal
end

function warning
	set_color FF8025
	echo "[Warning]" $argv
	set_color normal
end

function error
	set_color FF0000
	echo "[Error]" $argv
	echo "Aborting."
	set_color normal
	exit 1
end

function read_confirm
  while true
    read -l -P "$argv" confirm

    switch $confirm
      case Y y
        return 0
      case '' N n
        return 1
    end
  end
end

if [ ! $argv[1] ]
	echo "[Error] No device selected"
	usage
	exit
else
	set device $argv[1]
end


# Get some information
read -P "Target > " -c "ArchLinuxARM-rpi-3-latest" target
set user (eval echo ~$SUDO_USER)
read -P "Hostname > " hname
echo "Enter root password"
set rootpwd (openssl passwd -6)
if [ $status != 0 ]
	error "Passwords do not match"
end
read -P "Default user > " rpi_user
echo "Enter default user password"
set rpi_userpwd (openssl passwd -6)
if [ $status != 0 ]
	error "Passwords do not match"
end
set root_login (read_confirm "Permit SSH root login? [y/N] ")


# Prepare ArchARM archive

info "Checking validity of current ArchLinux image file"
if [ -f ./$target.tar.gz ]
	if test (md5sum $target.tar.gz) = (wget -qO- "http://os.archlinuxarm.org/os/$target.tar.gz.md5")
		info "Already have most recent version of ArchLinux. Skipping download"
	else
		info "Old image found. Dowloading most recent version of ArchLinux"
		rm -f ./$target.tar.gz
		wget -q --show-progress "http://os.archlinuxarm.org/os/$target.tar.gz"
	end
else
	info "Downloading most recent version of ArchLinux"
	wget -q --show-progress "http://os.archlinuxarm.org/os/$target.tar.gz"
end


# Prepare the environnement
if [ -d ./boot ]
	info "Delete old boot folder"
	rm -rf ./boot
end
if [ -d ./root ]
	info "Delete old root folder"
	rm -rf ./root
end
info "Create boot and root folders"
mkdir ./boot ./root


# Partition the card
info "Prepare the card"

info "Create partition table"
parted $device --script -- mklabel msdos
info "Create boot partition"
parted $device --script -- mkpart primary fat32 1 128
info "Create root partition"
parted $device --script -- mkpart primary ext4 128 100%
info "Set boot flag"
parted $device --script -- set 1 boot on
info "Print partition table"
parted $device --script print


# Get devices
set tmp (ls $device*)
set devices $tmp[2..3]


# Format partition
info "Formating boot partition"
mkfs.vfat -F32 $devices[1] > /dev/null
info "Formating root partition"
mkfs.ext4 -F $devices[2] > /dev/null

info "Mount boot directory"
sudo mount "$devices[1]" ./boot
info "Mount root directory"
sudo mount "$devices[2]" ./root


# Extract Files
info "Extract files from image"
bsdtar -xpf ./$target.tar.gz -C ./root
info "Sync the drive"
sync
info "Move boot files"
mv -f ./root/boot/* ./boot


# User configuration

# Change hostname
echo $hname > ./root/etc/hostname

# Change root password
if [ $rootpwd != "<NULL>" ]
	info "Change root password"
	sed -i -E s,root:[^:]+:,root:$rootpwd:, ./root/etc/shadow
else
	set_color "#FF8025"
	warning "root password has not been changed. Default is root"
	set_color "#FF8025"
end

# Create default user
if [ $rpi_user ]
	info "Create default user"
	sed -i -E "s/alarm/$rpi_user/g" ./root/etc/group
	sed -i -E "s/alarm/$rpi_user/g" ./root/etc/gshadow
	sed -i -E "s/alarm/$rpi_user/g" ./root/etc/passwd
	sed -i -E "s/alarm/$rpi_user/g" ./root/etc/shadow
	mv ./root/home/alarm ./root/home/$rpi_user
	# Change default user password
else
	warning "Default user has not been changed. Default is alarm"
	set rpi_user alarm
end

# Change default password
if [ $rpi_userpwd != "<NULL>" ]
	info "Change $rpi_user password"
	sed -i -E s,$rpi_user:[^:]+:,$rpi_user:$rpi_userpwd:, ./root/etc/shadow
else
	set_color "#FF8025"
	warning "$rpi_user password has not been changed. Default is alarm"
	set_color "#FF8025"
end

info "Copy SSH public key(s) into $rpi_user's authorized_keys"
mkdir ./root/home/$rpi_user/.ssh
cat $user/.ssh/*.pub >> ./root/home/$rpi_user/.ssh/authorized_keys

if [ root_login = 0 ]
	info "Copy SSH public key(s) into root's authorized_keys"
	mkdir ./root/root/.ssh
	cat $user/.ssh/*.pub >> ./root/root/.ssh/authorized_keys
end

# Copy ssh config
info "Copy SSH default config"
cp ./assets/sshd_config ./root/etc/ssh/sshd_config

# Add users allowed to SSH
if [ root_login = 0 ]
	warning "root will have ability to login through SSH"
	set allowed_users $allowed_users root
end
set allowed_users $allowed_users $rpi_user
echo "AllowUsers $allowed_users" >> ./root/etc/ssh/sshd_config

# Enable ssh
info "Enabling ssh"
touch ./boot/ssh


# Copy install script
info "Copy install script"
cp ./assets/install.sh ./root/root/


# Unmount
info "Umount drives"
umount ./boot ./root

# Delete old folders
rm -rf ./boot ./root

echo "All is done. Don't forget to run as root ~/install.sh when logging on the Pi ;)"
