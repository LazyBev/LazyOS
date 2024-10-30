#!/bin/bash

set -eau

#Variables
export LFS=/mnt/lfs
export LFS_TGT=$(uname -m)-lfs-linux-gnu
export LC_ALL=C 
export PATH=/usr/bin:/bin

cat > ~/.bash_profile << "EOF"
exec env -i HOME=$HOME TERM=$TERM PS1='\u:\w\$ ' /bin/bash
EOF

cat > ~/.bashrc << "EOF"
set +h
umask 022
export MAKEFLAGS=-j$(nproc)
export LFS=/mnt/lfs
export LC_ALL=POSIX
export LFS_TGT=$(uname -m)-lfs-linux-gnu
PATH=/usr/bin
if [ ! -L /bin ]; then PATH=/bin:$PATH; fi
PATH=$LFS/tools/bin:$PATH
CONFIG_SITE=$LFS/usr/share/config.site
export LFS LC_ALL LFS_TGT PATH CONFIG_SITE
EOF

su root -c "[ ! -e /etc/bash.bashrc ] || mv -v /etc/bash.bashrc /etc/bash.bashrc.NOUSE"

source ~/.bash_profile
cd $LFS/sources 

# Binutils
tar -xJf binutils*.tar.xz && cd binutils*/ 
mkdir -v build && cd build
../configure --prefix=$LFS/tools \
             --with-sysroot=$LFS \
             --target=$LFS_TGT   \
             --disable-nls       \
             --enable-gprofng=no \
             --disable-werror    \
             --enable-new-dtags  \
             --enable-default-hash-style=gnu
make -j$(nproc) && make install
cd $LFS/sources

# Gcc
tar -xJf gcc*.tar.xz && cd gcc*/
tar -xJf ../mpfr-4.2.1.tar.xz && mv -v mpfr-4.2.1 mpfr
tar -xJf ../gmp-6.3.0.tar.xz && mv -v gmp-6.3.0 gmp
tar -xzf ../mpc-1.3.1.tar.gz && mv -v mpc-1.3.1 mpc

case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
 ;;
esac

mkdir -v build && cd build
../configure                  \
    --target=$LFS_TGT         \
    --prefix=$LFS/tools       \
    --with-glibc-version=2.40 \
    --with-sysroot=$LFS       \
    --with-newlib             \
    --without-headers         \
    --enable-default-pie      \
    --enable-default-ssp      \
    --disable-nls             \
    --disable-shared          \
    --disable-multilib        \
    --disable-threads         \
    --disable-libatomic       \
    --disable-libgomp         \
    --disable-libquadmath     \
    --disable-libssp          \
    --disable-libvtv          \
    --disable-libstdcxx       \
    --enable-languages=c,c++
make -j$(nproc) && make install
cd .. && cat gcc/limitx.h gcc/glimits.h gcc/limity.h > \
  `dirname $($LFS_TGT-gcc -print-libgcc-file-name)`/include/limits.h
cd $LFS/sources 


# Libstdc++
tar -xJf gcc*.tar.xz && cd gcc*/
mkdir -v build && cd build
../libstdc++-v3/configure           \
    --host=$LFS_TGT                 \
    --build=$(../config.guess)      \
    --prefix=/usr                   \
    --disable-multilib              \
    --disable-nls                   \
    --disable-libstdcxx-pch         \
    --with-gxx-include-dir=/tools/$LFS_TGT/include/c++/14.2.0
make -j$(nproc) && make DESTDIR=$LFS install
rm -v $LFS/usr/lib/lib{stdc++{,exp,fs},supc++}.la
cd $LFS/sources 

# Linux kernel
tar -xJf linux*.tar.xz && cd linux*/
make mrproper && make headers
find usr/include -type f ! -name '*.h' -delete
cp -rv usr/include $LFS/usr
cd $LFS/sources 

# Glibc
tar -xJf glibc*.tar.xz && cd glibc*/

case $(uname -m) in
    i?86)   ln -sfv ld-linux.so.2 $LFS/lib/ld-lsb.so.3
    ;;
    x86_64) ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64
            ln -sfv ../lib/ld-linux-x86-64.so.2 $LFS/lib64/ld-lsb-x86-64.so.3
    ;;
esac

patch -Np1 -i ../glibc-2.40-fhs-1.patch
mkdir -v build && cd build
echo "rootsbindir=/usr/sbin" > configparms
../configure                             \
      --prefix=/usr                      \
      --host=$LFS_TGT                    \
      --build=$(../scripts/config.guess) \
      --enable-kernel=4.19               \
      --with-headers=$LFS/usr/include    \
      --disable-nscd                     \
      libc_cv_slibdir=/usr/lib
make -j$(nproc) && make DESTDIR=$LFS install

sed '/RTLDLIST=/s@/usr@@g' -i $LFS/usr/bin/ldd
echo 'int main(){}' | $LFS_TGT-gcc -xc -
readelf -l a.out | grep ld-linux
rm -v a.out
cd $LFS/sources 

# M4
tar -xJf m4*.tar.xz && cd m4*/
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make -j$(nproc) && make DESTDIR=$LFS install
cd $LFS/sources

# Ncurses
tar -xJf ncurses*.tar.xz && cd ncurses*/
sed -i s/mawk// configure
mkdir -v build
pushd build
    ../configure
    make -C include
    make -C progs tic
popd
./configure --prefix=/usr                \
            --host=$LFS_TGT              \
            --build=$(./config.guess)    \
            --mandir=/usr/share/man      \
            --with-manpage-format=normal \
            --with-shared                \
            --without-normal             \
            --with-cxx-shared            \
            --without-debug              \
            --without-ada                \
            --disable-stripping
make -j$(nproc) && make DESTDIR=$LFS TIC_PATH=$(pwd)/build/progs/tic install
ln -sv libncursesw.so $LFS/usr/lib/libncurses.so
sed -e 's/^#if.*XOPEN.*$/#if 1/' -i $LFS/usr/include/curses.h
cd $LFS/sources

# Bash
tar -xzf bash*.tar.gz && cd bash*/
./configure --prefix=/usr                      \
            --build=$(sh support/config.guess) \
            --host=$LFS_TGT                    \
            --without-bash-malloc              \
            bash_cv_strtold_broken=no
make -j$(nproc) && make DESTDIR=$LFS install
ln -sv bash $LFS/bin/sh
cd $LFS/sources

# Coreutils
tar -xJf coreutils*.tar.xz && cd coreutils*/
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess) \
            --enable-install-program=hostname \
            --enable-no-install-program=kill,uptime
make -j$(nproc) && make DESTDIR=$LFS install
mv -v $LFS/usr/bin/chroot $LFS/usr/sbin
mkdir -pv $LFS/usr/share/man/man8
mv -v $LFS/usr/share/man/man1/chroot.1 $LFS/usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/' $LFS/usr/share/man/man8/chroot.8
cd $LFS/sources

# Diffutils
tar -xJf diffutils*.tar.xz && cd diffutils*/
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make -j$(nproc) && make DESTDIR=$LFS install
cd $LFS/sources

# File
tar -xzf file*.tar.gz && cd file*/
mkdir build
pushd build
    ../configure --disable-bzlib      \
                 --disable-libseccomp \
                 --disable-xzlib      \
                 --disable-zlib
    make
popd
./configure --prefix=/usr --host=$LFS_TGT --build=$(./config.guess)
make -j$(nproc) FILE_COMPILE=$(pwd)/build/src/file && make DESTDIR=$LFS install
rm -v $LFS/usr/lib/libmagic.la
cd $LFS/sources

# Findutils
tar -xJf findutils*.tar.xz && cd findutils*/
./configure --prefix=/usr                   \
            --localstatedir=/var/lib/locate \
            --host=$LFS_TGT                 \
            --build=$(build-aux/config.guess)
make -j$(nproc) && make DESTDIR=$LFS install
cd $LFS/sources

# Gawk
tar -xJf gawk*.tar.xz && cd gawk*/
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make -j$(nproc) && make DESTDIR=$LFS install
cd $LFS/sources

# Grep
tar -xJf grep*.tar.xz && cd grep*/
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make -j$(nproc) && make DESTDIR=$LFS install
cd $LFS/sources

# Gzip
tar -xJf gzip*.tar.xz && cd gzip*/
./configure --prefix=/usr --host=$LFS_TGT
make -j$(nproc) && make DESTDIR=$LFS install
cd $LFS/sources

# Make
tar -xzf make*.tar.gz && cd make*/
./configure --prefix=/usr   \
            --without-guile \
            --host=$LFS_TGT \
            --build=$(build-aux/config.guess)
make -j$(nproc) && make DESTDIR=$LFS install
cd $LFS/sources

# Patch
tar -xJf patch*.tar.xz && cd patch*/
./configure
make -j$(nproc) && make DESTDIR=$LFS install
cd $LFS/sources

# Sed
tar -xJf sed*.tar.xz && cd sed*/
./configure --prefix=/usr   \
            --host=$LFS_TGT \
            --build=$(./build-aux/config.guess)
make -j$(nproc) && make DESTDIR=$LFS install
cd $LFS/sources

# Tar
tar -xJf tar*.tar.xz && cd tar*/
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess)
make -j$(nproc) && make DESTDIR=$LFS install
cd $LFS/sources

# Xz
tar -xJf xz*.tar.xz && cd xz*/
./configure --prefix=/usr                     \
            --host=$LFS_TGT                   \
            --build=$(build-aux/config.guess) \
            --disable-static                  \
            --docdir=/usr/share/doc/xz-5.6.2
make -j$(nproc) && make DESTDIR=$LFS install
rm -v $LFS/usr/lib/liblzma.la
cd $LFS/sources

# Binutils pass 2
tar -xJf binutils*.tar.xz && cd binutils*/
sed '6009s/$add_dir//' -i ltmain.sh
mkdir -v build && cd build
../configure --prefix=/usr              \
             --build=$(../config.guess) \
             --host=$LFS_TGT            \
             --disable-nls              \
             --enable-shared            \
             --enable-gprofng=no        \
             --disable-werror           \
             --enable-64-bit-bfd        \
             --enable-new-dtags         \
             --enable-default-hash-style=gnu
make -j$(nproc) && make install
rm -v $LFS/usr/lib/lib{bfd,ctf,ctf-nobfd,opcodes,sframe}.{a,la}
cd $LFS/sources

# Gcc pass 2
tar -xJf gcc*.tar.xz && cd gcc*/
tar -xJf ../mpfr-4.2.1.tar.xz && mv -v mpfr-4.2.1 mpfr
tar -xJf ../gmp-6.3.0.tar.xz && mv -v gmp-6.3.0 gmp
tar -xzf ../mpc-1.3.1.tar.gz && mv -v mpc-1.3.1 mpc

case $(uname -m) in
  x86_64)
    sed -e '/m64=/s/lib64/lib/' \
        -i.orig gcc/config/i386/t-linux64
  ;;
esac

sed '/thread_header =/s/@.*@/gthr-posix.h/' -i libgcc/Makefile.in libstdc++-v3/include/Makefile.in

mkdir -v build && cd build
../configure --build=$(../config.guess)            \
             --host=$LFS_TGT                       \
             --target=$LFS_TGT                     \
    LDFLAGS_FOR_TARGET=-L$PWD/$LFS_TGT/libgcc      \
             --prefix=/usr                         \
             --with-build-sysroot=$LFS             \
             --enable-default-pie                  \
             --enable-default-ssp                  \
             --disable-nls                         \
             --disable-multilib                    \
             --disable-libatomic                   \
             --disable-libgomp                     \
             --disable-libquadmath                 \
             --disable-libsanitizer                \
             --disable-libssp                      \
             --disable-libvtv                      \
             --enable-languages=c,c++
make -j$(nproc) && make DESTDIR=$LFS install
ln -sv gcc $LFS/usr/bin/cc
cd $LFS/sources

su - root -c "cd /home/lazybev/LazyOS && chmod +x ./Chroot.sh && ./Chroot.sh"
