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
    echo "Running as root..."
else
    echo "Please run this as root..."
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

wget https://download.savannah.gnu.org/releases/acl/acl-2.3.2.tar.xz --directory-prefix=$LFS/sources
wget https://download.savannah.gnu.org/releases/attr/attr-2.5.2.tar.gz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/autoconf/autoconf-2.72.tar.xz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/automake/automake-1.17.tar.xz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/bash/bash-5.2.32.tar.gz --directory-prefix=$LFS/sources
wget https://github.com/gavinhoward/bc/releases/download/6.7.6/bc-6.7.6.tar.xz --directory-prefix=$LFS/sources
wget https://sourceware.org/pub/binutils/releases/binutils-2.43.1.tar.xz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/bison/bison-3.8.2.tar.xz --directory-prefix=$LFS/sources
wget https://www.sourceware.org/pub/bzip2/bzip2-1.0.8.tar.gz --directory-prefix=$LFS/sources
wget https://github.com/libcheck/check/releases/download/0.15.2/check-0.15.2.tar.gz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/coreutils/coreutils-9.5.tar.xz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/dejagnu/dejagnu-1.6.3.tar.gz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/diffutils/diffutils-3.10.tar.xz --directory-prefix=$LFS/sources
wget https://downloads.sourceforge.net/project/e2fsprogs/e2fsprogs/v1.47.1/e2fsprogs-1.47.1.tar.gz --directory-prefix=$LFS/sources
wget https://sourceware.org/ftp/elfutils/0.191/elfutils-0.191.tar.bz2 --directory-prefix=$LFS/sources
wget https://prdownloads.sourceforge.net/expat/expat-2.6.2.tar.xz --directory-prefix=$LFS/sources
wget https://prdownloads.sourceforge.net/expect/expect5.45.4.tar.gz --directory-prefix=$LFS/sources
wget https://astron.com/pub/file/file-5.45.tar.gz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/findutils/findutils-4.10.0.tar.xz --directory-prefix=$LFS/sources
wget https://github.com/westes/flex/releases/download/v2.6.4/flex-2.6.4.tar.gz --directory-prefix=$LFS/sources
wget https://pypi.org/packages/source/f/flit-core/flit_core-3.9.0.tar.gz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/gawk/gawk-5.3.0.tar.xz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/gcc/gcc-14.2.0/gcc-14.2.0.tar.xz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/gdbm/gdbm-1.24.tar.gz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/gettext/gettext-0.22.5.tar.xz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/glibc/glibc-2.40.tar.xz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/gmp/gmp-6.3.0.tar.xz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/gperf/gperf-3.1.tar.gz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/grep/grep-3.11.tar.xz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/groff/groff-1.23.0.tar.gz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/grub/grub-2.12.tar.xz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/gzip/gzip-1.13.tar.xz --directory-prefix=$LFS/sources
wget https://github.com/Mic92/iana-etc/releases/download/20240806/iana-etc-20240806.tar.gz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/inetutils/inetutils-2.5.tar.xz --directory-prefix=$LFS/sources
wget https://launchpad.net/intltool/trunk/0.51.0/+download/intltool-0.51.0.tar.gz --directory-prefix=$LFS/sources
wget https://www.kernel.org/pub/linux/utils/net/iproute2/iproute2-6.10.0.tar.xz --directory-prefix=$LFS/sources
wget https://pypi.org/packages/source/J/Jinja2/jinja2-3.1.4.tar.gz --directory-prefix=$LFS/sources
wget https://www.kernel.org/pub/linux/utils/kbd/kbd-2.6.4.tar.xz --directory-prefix=$LFS/sources
wget https://www.kernel.org/pub/linux/utils/kernel/kmod/kmod-33.tar.xz --directory-prefix=$LFS/sources
wget https://www.greenwoodsoftware.com/less/less-661.tar.gz --directory-prefix=$LFS/sources
wget https://www.linuxfromscratch.org/lfs/downloads/12.2/lfs-bootscripts-20240825.tar.xz --directory-prefix=$LFS/sources
wget https://www.kernel.org/pub/linux/libs/security/linux-privs/libcap2/libcap-2.70.tar.xz --directory-prefix=$LFS/sources
wget https://github.com/libffi/libffi/releases/download/v3.4.6/libffi-3.4.6.tar.gz --directory-prefix=$LFS/sources
wget https://download.savannah.gnu.org/releases/libpipeline/libpipeline-1.5.7.tar.gz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/libtool/libtool-2.4.7.tar.xz --directory-prefix=$LFS/sources
wget https://github.com/besser82/libxcrypt/releases/download/v4.4.36/libxcrypt-4.4.36.tar.xz --directory-prefix=$LFS/sources
wget https://www.kernel.org/pub/linux/kernel/v6.x/linux-6.10.5.tar.xz --directory-prefix=$LFS/sources
wget https://github.com/lz4/lz4/releases/download/v1.10.0/lz4-1.10.0.tar.gz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/m4/m4-1.4.19.tar.xz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/make/make-4.4.1.tar.gz --directory-prefix=$LFS/sources
wget https://download.savannah.gnu.org/releases/man-db/man-db-2.12.1.tar.xz --directory-prefix=$LFS/sources
wget https://www.kernel.org/pub/linux/docs/man-pages/man-pages-6.9.1.tar.xz --directory-prefix=$LFS/sources
wget https://pypi.org/packages/source/M/MarkupSafe/MarkupSafe-2.1.5.tar.gz --directory-prefix=$LFS/sources
wget https://github.com/mesonbuild/meson/releases/download/1.5.1/meson-1.5.1.tar.gz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/mpc/mpc-1.3.1.tar.gz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/mpfr/mpfr-4.2.1.tar.xz --directory-prefix=$LFS/sources
wget https://invisible-mirror.net/archives/ncurses/ncurses-6.5.tar.gz --directory-prefix=$LFS/sources
wget https://github.com/ninja-build/ninja/archive/v1.12.1/ninja-1.12.1.tar.gz --directory-prefix=$LFS/sources
wget https://www.openssl.org/source/openssl-3.3.1.tar.gz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/patch/patch-2.7.6.tar.xz --directory-prefix=$LFS/sources
wget https://www.cpan.org/src/5.0/perl-5.40.0.tar.xz --directory-prefix=$LFS/sources
wget https://distfiles.ariadne.space/pkgconf/pkgconf-2.3.0.tar.xz --directory-prefix=$LFS/sources
wget https://sourceforge.net/projects/procps-ng/files/Production/procps-ng-4.0.4.tar.xz --directory-prefix=$LFS/sources
wget https://sourceforge.net/projects/psmisc/files/psmisc/psmisc-23.7.tar.xz --directory-prefix=$LFS/sources
wget https://www.python.org/ftp/python/3.12.5/Python-3.12.5.tar.xz --directory-prefix=$LFS/sources
wget https://www.python.org/ftp/python/doc/3.12.5/python-3.12.5-docs-html.tar.bz2 --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/readline/readline-8.2.13.tar.gz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/sed/sed-4.9.tar.xz --directory-prefix=$LFS/sources
wget https://pypi.org/packages/source/s/setuptools/setuptools-72.2.0.tar.gz --directory-prefix=$LFS/sources
wget https://github.com/shadow-maint/shadow/releases/download/4.16.0/shadow-4.16.0.tar.xz --directory-prefix=$LFS/sources
wget https://github.com/troglobit/sysklogd/releases/download/v2.6.1/sysklogd-2.6.1.tar.gz --directory-prefix=$LFS/sources
wget https://github.com/systemd/systemd/archive/v256.4/systemd-256.4.tar.gz --directory-prefix=$LFS/sources
wget https://anduin.linuxfromscratch.org/LFS/systemd-man-pages-256.4.tar.xz --directory-prefix=$LFS/sources
wget https://github.com/slicer69/sysvinit/releases/download/3.10/sysvinit-3.10.tar.xz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/tar/tar-1.35.tar.xz --directory-prefix=$LFS/sources
wget https://downloads.sourceforge.net/tcl/tcl8.6.14-src.tar.gz --directory-prefix=$LFS/sources
wget https://downloads.sourceforge.net/tcl/tcl8.6.14-html.tar.gz --directory-prefix=$LFS/sources
wget https://ftp.gnu.org/gnu/texinfo/texinfo-7.1.tar.xz --directory-prefix=$LFS/sources
wget https://www.iana.org/time-zones/repository/releases/tzdata2024a.tar.gz --directory-prefix=$LFS/sources
wget https://anduin.linuxfromscratch.org/LFS/udev-lfs-20230818.tar.xz --directory-prefix=$LFS/sources
wget https://www.kernel.org/pub/linux/utils/util-linux/v2.40/util-linux-2.40.2.tar.xz --directory-prefix=$LFS/sources
wget https://github.com/vim/vim/archive/v9.1.0660/vim-9.1.0660.tar.gz --directory-prefix=$LFS/sources
wget https://pypi.org/packages/source/w/wheel/wheel-0.44.0.tar.gz --directory-prefix=$LFS/sources
wget https://cpan.metacpan.org/authors/id/T/TO/TODDR/XML-Parser-2.47.tar.gz --directory-prefix=$LFS/sources
wget https://github.com//tukaani-project/xz/releases/download/v5.6.2/xz-5.6.2.tar.xz --directory-prefix=$LFS/sources
wget https://zlib.net/fossils/zlib-1.3.1.tar.gz --directory-prefix=$LFS/sources
wget https://github.com/facebook/zstd/releases/download/v1.5.6/zstd-1.5.6.tar.gz --directory-prefix=$LFS/sources
wget https://www.linuxfromscratch.org/patches/lfs/12.2/bzip2-1.0.8-install_docs-1.patch --directory-prefix=$LFS/sources
wget https://www.linuxfromscratch.org/patches/lfs/12.2/coreutils-9.5-i18n-2.patch --directory-prefix=$LFS/sources
wget https://www.linuxfromscratch.org/patches/lfs/12.2/expect-5.45.4-gcc14-1.patch --directory-prefix=$LFS/sources
wget https://www.linuxfromscratch.org/patches/lfs/12.2/glibc-2.40-fhs-1.patch --directory-prefix=$LFS/sources
wget https://www.linuxfromscratch.org/patches/lfs/12.2/kbd-2.6.4-backspace-1.patch --directory-prefix=$LFS/sources
wget https://www.linuxfromscratch.org/patches/lfs/12.2/sysvinit-3.10-consolidated-1.patch --directory-prefix=$LFS/sources
chown root:root $LFS/sources/*

wget https://www.linuxfromscratch.org/lfs/view/stable/md5sums --directory-prefix=$LFS/sources

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
