#!/bin/bash
# A script to list version numbers of critical development tools

# If you have tools installed in other directories, adjust PATH here AND
# in ~lfs/.bashrc (section 4.4) as well.

LC_ALL=C 
PATH=/usr/bin:/bin

[ "$(whoami)" = "root" ] || echo "Please run this as root" && exit $? &>/dev/null

bail() { echo "FATAL: $1"; exit 1; }
grep --version > /dev/null 2> /dev/null || bail "grep does not work"
sed '' /dev/null || bail "sed does not work"
sort   /dev/null || bail "sort does not work"

ver_check()
{
   if ! type -p $2 &>/dev/null
   then 
     echo "ERROR: Cannot find $2 ($1)"; return 1; 
   fi
   v=$($2 --version 2>&1 | grep -E -o '[0-9]+\.[0-9\.]+[a-z]*' | head -n1)
   if printf '%s\n' $3 $v | sort --version-sort --check &>/dev/null
   then 
     printf "OK:    %-9s %-6s >= $3\n" "$1" "$v"; return 0;
   else 
     printf "ERROR: %-9s is TOO OLD ($3 or later required)\n" "$1"; 
     return 1; 
   fi
}

ver_kernel()
{
   kver=$(uname -r | grep -E -o '^[0-9\.]+')
   if printf '%s\n' $1 $kver | sort --version-sort --check &>/dev/null
   then 
     printf "OK:    Linux Kernel $kver >= $1\n"; return 0;
   else 
     printf "ERROR: Linux Kernel ($kver) is TOO OLD ($1 or later required)\n" "$kver"; 
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

if mount | grep -q 'devpts on /dev/pts' && [ -e /dev/ptmx ]
then echo "OK:    Linux Kernel supports UNIX 98 PTY";
else echo "ERROR: Linux Kernel does NOT support UNIX 98 PTY"; fi

alias_check() {
   if $1 --version 2>&1 | grep -qi $2
   then printf "OK:    %-4s is $2\n" "$1";
   else printf "ERROR: %-4s is NOT $2\n" "$1"; fi
}
echo "Aliases:"
alias_check awk GNU
alias_check yacc Bison
alias_check sh Bash

echo "Compiler check:"
if printf "int main(){}" | g++ -x c++ -
then echo "OK:    g++ works";
else echo "ERROR: g++ does NOT work"; fi
rm -f a.out

if [ "$(nproc)" = "" ]; then
   echo "ERROR: nproc is not available or it produces empty output"
else
   echo "OK: nproc reports $(nproc) logical cores are available"
fi

echo -e "\nCheck that your host OS has the correct packages needed."
read -p "Are you sure you wanna continue? (y/n)? " yn

if [[ "$yn" != "y" ]]; then
    exit 1
else
    echo -e "Continuing..."
    sudo pacman -S arch-install-scripts
fi

lsblk
read -p "Enter the disk to install on (e.g., /dev/sda): " disk

# Determine disk prefix
if [[ "$disk" == /dev/nvme* ]]; then
    disk_prefix="p"
else
    disk_prefix=""
fi

# Get partition sizes from user input
read -p "Enter the size for the boot partition (e.g., +512M): " boot_size
read -p "Enter the size for the swap partition (e.g., +4G): " swap_size
read -p "Enter the size for the root partition (e.g., +30G): " root_size

(
echo o # Create a new empty GPT partition table
echo n # New partition for boot
echo p # Primary
echo 1 # Partition number
echo   # First sector (Accept default: will start at the beginning of the disk)
echo +"$boot_size" # Size of the boot partition
echo n # New partition for swap
echo p # Primary
echo 2 # Partition number
echo   # First sector (Accept default)
echo +"$swap_size" # Size of the swap partition
echo n # New partition for root
echo p # Primary
echo 3 # Partition number
echo   # First sector (Accept default)
echo +"$root_size" # Size of the root partition
echo w # Write the partition table
) | fdisk "$disk"

mkfs.vfat -F 32 "$disk$disk_prefix"1 || { echo "Failed to format boot partition" && exit 1; }
mkfs -v -t ext4 "$disk$disk_prefix"3 || { echo "Failed to format root partition" && exit 1; }
mkswap "$disk$disk_prefix"2 || { echo "Failed to format swap partition" && exit 1; }

echo "Partitioning complete!"

export LFS=/mnt/lfs
echo "export LFS=/mnt/lfs" > $HOME/.bashrc

if [[ "$LFS" == "/mnt/lfs" ]]; then
    echo "Variable LFS is setup"
else
    echo "Error: LFS is not set to /mnt/lfs, it is set to $LFS"
    exit 1
fi

mkdir -pv $LFS
mount -v -t ext4 "$disk$disk_prefix"3 $LFS
mount --mkdir /dev/efi_system_partition /mnt/boot
swapon -v "$disk$disk_prefix"2 || { echo "Failed to enable swap partition" && exit 1; }

echo "Mounting complete!"

mkdir -v $LFS/sources
chmod -v a+wt $LFS/sources

wget --input-file=wget-list-sysv --continue --directory-prefix=$LFS/sources
chown root:root $LFS/sources/*

wget https://www.linuxfromscratch.org/lfs/view/stable/md5sums
mv md5sums $LFS/sources/md5sums

mkdir -pv $LFS/{etc,var} $LFS/usr/{bin,lib,sbin}

for i in bin lib sbin; do
  ln -sv usr/$i $LFS/$i
done

case $(uname -m) in
  x86_64) mkdir -pv $LFS/lib64 ;;
esac

mkdir -pv $LFS/tools

groupadd lfs
useradd -s /bin/bash -g lfs -m -k /dev/null lfs

passwd lfs

chown -v lfs $LFS/{usr{,/*},lib,var,etc,bin,sbin,tools}
case $(uname -m) in
  x86_64) chown -v lfs $LFS/lib64 ;;
esac

su - lfs -c "chmod +x ./Setup.sh && ./Setup.sh"
