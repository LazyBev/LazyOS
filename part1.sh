#!/bin/bash

set -eau
# A script to list version numbers of critical development tools

# If you have tools installed in other directories, adjust PATH here AND
# in ~lfs/.bashrc (section 4.4) as well.

# Error handling
trap 'echo "An error occurred. Exiting..."; exit 1;' ERR

#Variables
export LFS=/mnt/lfs
export LFS_TGT=$(uname -m)-lfs-linux-gnu
export LC_ALL=C 
export PATH=/usr/bin:/bin

if [ "$(whoami)" = "root" ]; then
    :
else
    echo "Please run this as root"
    exit 1 &>/dev/null
fi

bail() { echo "FATAL: $1"; exit 1; }

# Variable to track errors
errors_occurred=0

# Host OS requirement check
grep --version > /dev/null 2> /dev/null || { bail "grep does not work"; errors_occurred=1; }
sed '' /dev/null || { bail "sed does not work"; errors_occurred=1; }
sort /dev/null || { bail "sort does not work"; errors_occurred=1; }

ver_check() {
	if ! type -p "$2" &>/dev/null; then 
    	echo "ERROR: Cannot find $2 ($1)"; 
    	errors_occurred=1
     return 1; 
	fi
	v=$("$2" --version 2>&1 | grep -E -o '[0-9]+\.[0-9\.]+[a-z]*' | head -n1)
	if printf '%s\n' "$3" "$v" | sort --version-sort --check &>/dev/null; then 
    	printf "OK:    %-9s %-6s >= $3\n" "$1" "$v"; 
    	return 0;
	else 
    	printf "ERROR: %-9s is TOO OLD ($3 or later required)\n" "$1"; 
     	errors_occurred=1
     	return 1; 
   	fi
}

ver_kernel() {
   	kver=$(uname -r | grep -E -o '^[0-9\.]+')
   	if printf '%s\n' "$1" "$kver" | sort --version-sort --check &>/dev/null; then 
     	printf "OK:    Linux Kernel $kver >= $1\n"; 
     	return 0;
   	else 
     	printf "ERROR: Linux Kernel ($kver) is TOO OLD ($1 or later required)\n"; 
     	errors_occurred=1
     	return 1; 
   	fi
}

# Coreutils first because --version-sort needs Coreutils >= 7.0
ver_check Coreutils      sort     8.1 || bail "Coreutils too old, stop"
ver_check Bash           bash     3.2
ver_check Binutils       ld       2.13.1
ver_check Bison          bison    2.7
ver_check Diffutils      diff     2.8.1
ver_check Findutils      find     4.2.31
ver_check Gawk           gawk     4.0.1
ver_check GCC            gcc      5.2
ver_check "GCC (C++)"    g++      5.2
ver_check Grep           grep     2.5.1a
ver_check Gzip           gzip     1.3.12
ver_check M4             m4       1.4.10
ver_check Make           make     4.0
ver_check Patch          patch    2.5.4
ver_check Perl           perl     5.8.8
ver_check Python         python3  3.4
ver_check Sed            sed      4.1.5
ver_check Tar            tar      1.22
ver_check Texinfo        texi2any 5.0
ver_check Xz             xz       5.0.0
ver_kernel 4.19

if mount | grep -q 'devpts on /dev/pts' && [ -e /dev/ptmx ]; then 
	echo "OK:    Linux Kernel supports UNIX 98 PTY";
else 
	echo "ERROR: Linux Kernel does NOT support UNIX 98 PTY"; 
	errors_occurred=1
fi

alias_check() {
	if "$1" --version 2>&1 | grep -qi "$2"; then 
    	printf "OK:    %-4s is $2\n" "$1";
	else 
    	printf "ERROR: %-4s is NOT $2\n" "$1"; 
    	errors_occurred=1
	fi
}

echo "Aliases:"
alias_check awk GNU
alias_check yacc Bison
alias_check sh Bash

echo "Compiler check:"
if printf "int main(){}" | g++ -x c++ -; then 
	echo "OK:    g++ works";
else 
	echo "ERROR: g++ does NOT work"; 
	errors_occurred=1
fi
rm -f a.out

if [ "$(nproc)" = "" ]; then
	echo "ERROR: nproc is not available or it produces empty output"; 
	errors_occurred=1
else
	echo "OK: nproc reports $(nproc) logical cores are available"
fi

echo -e "Checking if requirements meet on your host OS..."
sleep 2

# Exit with status based on errors encountered
if [ $errors_occurred -ne 0 ]; then
	echo "Host OS does nto meet requirements to start installation"
	exit 1
fi

sudo pacman -S arch-install-scripts

lsblk
read -p "Enter the disk to install on (e.g., /dev/sda): " disk

# Determine disk prefix
if [[ "$disk" == /dev/nvme* ]]; then
    disk_prefix="p"
else
    disk_prefix=""
fi

# Wipe the disk and partition
echo "Wiping $disk and creating partitions..."
wipefs -af "$disk"

disk_size=$(lsblk -b -n -d -o SIZE "$disk" | awk '{print int($1 / 1024 / 1024)}')
boot_size=1024
root_size=$((disk_size - boot_size))

echo "Auto-partitioning: /boot=${boot_size}MiB, /root=${root_size}MiB"
parted "$disk" mklabel gpt
parted "$disk" mkpart primary fat32 1MiB "${boot_size}MiB"
parted "$disk" set 1 boot on
parted "$disk" mkpart primary ext4 "$((boot_size))MiB" "$((disk_size - boot_size))MiB"

export bootP="/dev/${disk}${disk_prefix}1"
export rootP="/dev/${disk}${disk_prefix}2"

mkfs.vfat -F 32 "$bootP" || { echo "Failed to format boot partition" && exit 1; }
mkfs.ext4 "$rootp" || { echo "Failed to format root partition" && exit 1; }

if [[ "$LFS" == "/mnt/lfs" ]]; then
	echo "Variable LFS is setup"
else
    echo "Error: LFS is not set to /mnt/lfs, it is set to $LFS"
    exit 1
fi

echo -e "Mounting disk..."
sleep 2

mkdir -pv "$LFS"
mount -v -t ext4 "$rootp" "$LFS"
mount --mkdir -v -t vfat "$bootP" /boot/efi
swapon -v "$swapP" || { echo "Failed to enable swap partition" && exit 1; }

echo -e "Adding entry to /etc/fstab"
sleep 2

# Get the UUID of the partition
UUID=$(sudo blkid"$rootp" | awk -F' ' '/UUID=/{for(i=1;i<=NF;i++) if($i ~ /^UUID=/) print substr($i, 7, length($i)-7)}')

# Check if UUID was found
if [ -z "$UUID" ]; then
	echo "Error: UUID not found for $rootp"
	exit 1
fi

# Add entry to /etc/fstab
echo -e "\n# $rootp\nUUID=$UUID /mnt/lfs  $fstype  defaults  1  1" | sudo tee -a /etc/fstab

echo -e "Setting up base system..."
sleep 2

mkdir -v $LFS/sources
ls $LFS
chmod -v a+wt $LFS/sources

wget --input-file=$HOME/LazyOS/wget-list-sysv --continue --directory-prefix=$LFS/sources
chown root:root $LFS/sources/*

wget https://www.linuxfromscratch.org/lfs/view/stable/md5sums
mv md5sums $LFS/sources/

pushd $LFS/sources
    md5sum -c md5sums
popd

mkdir -pv $LFS/{etc,var} $LFS/usr/{bin,lib,sbin}

for i in bin lib sbin; do
	ln -sv usr/$i $LFS/$i
done

case $(uname -m) in
	x86_64) mkdir -pv $LFS/lib64 ;;
esac

mkdir -pv $LFS/tools
ls $LFS

groupadd lfs
useradd -s /bin/bash -g lfs -m -s /bin/bash -k /dev/null lfs
usermod -aG root lfs
passwd lfs

chown -v lfs $LFS/{usr{,/*},lib,var,etc,bin,sbin,tools}
case $(uname -m) in
	x86_64) chown -v lfs $LFS/lib64 ;;
esac

su - lfs -c "cd /home/lazybev/LazyOS && chmod +x ./part2.sh && ./part2.sh"
