#!/bin/bash

set -eau

#Variables
export LFS_SRC=$LFS/sources
export LFS=/mnt/lfs
export LFS_TGT=$(uname -m)-lfs-linux-gnu
export LC_ALL=C 
export PATH=/usr/bin:/bin

chown --from lfs -R root:root $LFS/{usr,lib,var,etc,bin,sbin,tools}
case $(uname -m) in
	x86_64) chown --from lfs -R root:root $LFS/lib64 ;;
esac

mkdir -pv $LFS/{dev,proc,sys,run}
ls $LFS
mount -v --bind /dev $LFS/dev
mount -vt devpts devpts -o gid=5,mode=0620 $LFS/dev/pts
mount -vt proc proc $LFS/proc
mount -vt sysfs sysfs $LFS/sys
mount -vt tmpfs tmpfs $LFS/run

if [ -h $LFS/dev/shm ]; then
	install -v -d -m 1777 $LFS$(realpath /dev/shm)
else
	mount -vt tmpfs -o nosuid,nodev tmpfs $LFS/dev/shm
fi

chroot "$LFS" /usr/bin/env -i HOME=/root TERM="$TERM" PS1='(lfs chroot) \u:\w\$ ' \
    PATH=/usr/bin:/usr/sbin MAKEFLAGS="-j$(nproc)" TESTSUITEFLAGS="-j$(nproc)" /bin/bash --login <<EOF
set -e

mkdir -pv /{boot,home,mnt,opt,srv}
ls /
mkdir -pv /etc/{opt,sysconfig}
mkdir -pv /lib/firmware
mkdir -pv /media/{floppy,cdrom}
mkdir -pv /usr/{,local/}{include,src}
mkdir -pv /usr/lib/locale
mkdir -pv /usr/local/{bin,lib,sbin}
mkdir -pv /usr/{,local/}share/{color,dict,doc,info,locale,man}
mkdir -pv /usr/{,local/}share/{misc,terminfo,zoneinfo}
mkdir -pv /usr/{,local/}share/man/man{1..8}
mkdir -pv /var/{cache,local,log,mail,opt,spool}
mkdir -pv /var/lib/{color,misc,locate}

ln -sfv /run /var/run
ln -sfv /run/lock /var/lock
install -dv -m 0750 /root
install -dv -m 1777 /tmp /var/tmp
ln -sv /proc/self/mounts /etc/mtab

cat > /etc/hosts << "HOSTS"
127.0.0.1  localhost $(hostname)
::1        localhost
HOSTS

cat > /etc/passwd << "PASSWD"
root:x:0:0:root:/root:/bin/bash
bin:x:1:1:bin:/dev/null:/usr/bin/false
daemon:x:6:6:Daemon User:/dev/null:/usr/bin/false
messagebus:x:18:18:D-Bus Message Daemon User:/run/dbus:/usr/bin/false
uuidd:x:80:80:UUID Generation Daemon User:/dev/null:/usr/bin/false
nobody:x:65534:65534:Unprivileged User:/dev/null:/usr/bin/false
PASSWD

cat > /etc/group << "GROUP"
root:x:0:
bin:x:1:daemon
sys:x:2:
kmem:x:3:
tape:x:4:
tty:x:5:
daemon:x:6:
floppy:x:7:
disk:x:8:
lp:x:9:
dialout:x:10:
audio:x:11:
video:x:12:
utmp:x:13:
cdrom:x:15:
adm:x:16:
messagebus:x:18:
input:x:24:
mail:x:34:
kvm:x:61:
uuidd:x:80:
wheel:x:97:
users:x:999:
nogroup:x:65534:
GROUP

localedef -i C -f UTF-8 C.UTF-8

echo "tester:x:101:101::/home/tester:/bin/bash" >> /etc/passwd
echo "tester:x:101:" >> /etc/group
install -o tester -d /home/tester

exec /usr/bin/bash --login

touch /var/log/{btmp,lastlog,faillog,wtmp}
chgrp -v utmp /var/log/lastlog
chmod -v 664  /var/log/lastlog
chmod -v 600  /var/log/btmp

# Gettext
cd sources
tar -xvJf gettext*.tar.xz && cd gettext*/
./configure --disable-shared
make -j$(nproc)
cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
cd /sources
# Bison
tar -xvJf gettext*.tar.xz && cd gettext*/ 
./configure --prefix=/usr \
            --docdir=/usr/share/doc/bison-3.8.2
make -j$(nproc) && make install
cd /sources

# Perl
tar -xvJf perl*.tar.xz && cd perl*/ 
sh Configure -des                                         \
             -D prefix=/usr                               \
             -D vendorprefix=/usr                         \
             -D useshrplib                                \
             -D privlib=/usr/lib/perl5/5.40/core_perl     \
             -D archlib=/usr/lib/perl5/5.40/core_perl     \
             -D sitelib=/usr/lib/perl5/5.40/site_perl     \
             -D sitearch=/usr/lib/perl5/5.40/site_perl    \
             -D vendorlib=/usr/lib/perl5/5.40/vendor_perl \
             -D vendorarch=/usr/lib/perl5/5.40/vendor_perl
make -j$(nproc) && make install
cd /sources

# Python
tar -xvJf python*.tar.xz && cd python*/
./configure --prefix=/usr   \
            --enable-shared \
            --without-ensurepip
make -j$(nproc) && make install
cd /sources

# Texinfo
tar -xvJf texinfo*.tar.xz && cd texinfo*/
./configure --prefix=/usr
make -j$(nproc) && make install
cd /sources

# Util-linux
tar -xvJf util-linux*.tar.xz && cd util-linux*/
mkdir -pv /var/lib/hwclock
./configure --libdir=/usr/lib     \
            --runstatedir=/run    \
            --disable-chfn-chsh   \
            --disable-login       \
            --disable-nologin     \
            --disable-su          \
            --disable-setpriv     \
            --disable-runuser     \
            --disable-pylibmount  \
            --disable-static      \
            --disable-liblastlog2 \
            --without-python      \
            ADJTIME_PATH=/var/lib/hwclock/adjtime \
            --docdir=/usr/share/doc/util-linux-2.40.2
make -j$(nproc) && make install

# Cleanup
rm -rf /usr/share/{info,man,doc}/*
find /usr/{lib,libexec} -name \*.la -delete
rm -rf /tools

# Man pages
cd /sources
tar -xvJf man-pages*.tar.xz && cd man-pages*/
rm -v man3/crypt*
make prefix=/usr install
cd /sources

# Iana-etc
tar -xvJf iana-etc*.tar.xz && cd iana-etc*/
cp services protocols /etc
cd /sources

# Glibc
tar -xvJf glibc*.tar.xz && cd glibc*/
patch -Np1 -i ../glibc*.patch
mkdir -v build && cd build
echo "rootsbindir=/usr/sbin" > configparms
../configure --prefix=/usr                            \
             --disable-werror                         \
             --enable-kernel=4.19                     \
             --enable-stack-protector=strong          \
             --disable-nscd                           \
             libc_cv_slibdir=/usr/lib
make -j$(nproc) && make check
touch /etc/ld.so.conf
sed '/test-installation/s@$(PERL)@echo not running@' -i ../Makefile
make install
sed '/RTLDLIST=/s@/usr@@g' -i /usr/bin/ldd

localedef -i C -f UTF-8 C.UTF-8
localedef -i cs_CZ -f UTF-8 cs_CZ.UTF-8
localedef -i de_DE -f ISO-8859-1 de_DE
localedef -i de_DE@euro -f ISO-8859-15 de_DE@euro
localedef -i de_DE -f UTF-8 de_DE.UTF-8
localedef -i el_GR -f ISO-8859-7 el_GR
localedef -i en_GB -f ISO-8859-1 en_GB
localedef -i en_GB -f UTF-8 en_GB.UTF-8
localedef -i en_HK -f ISO-8859-1 en_HK
localedef -i en_PH -f ISO-8859-1 en_PH
localedef -i en_US -f ISO-8859-1 en_US
localedef -i en_US -f UTF-8 en_US.UTF-8
localedef -i es_ES -f ISO-8859-15 es_ES@euro
localedef -i es_MX -f ISO-8859-1 es_MX
localedef -i fa_IR -f UTF-8 fa_IR
localedef -i fr_FR -f ISO-8859-1 fr_FR
localedef -i fr_FR@euro -f ISO-8859-15 fr_FR@euro
localedef -i fr_FR -f UTF-8 fr_FR.UTF-8
localedef -i is_IS -f ISO-8859-1 is_IS
localedef -i is_IS -f UTF-8 is_IS.UTF-8
localedef -i it_IT -f ISO-8859-1 it_IT
localedef -i it_IT -f ISO-8859-15 it_IT@euro
localedef -i it_IT -f UTF-8 it_IT.UTF-8
localedef -i ja_JP -f EUC-JP ja_JP
localedef -i ja_JP -f SHIFT_JIS ja_JP.SJIS 2> /dev/null || true
localedef -i ja_JP -f UTF-8 ja_JP.UTF-8
localedef -i nl_NL@euro -f ISO-8859-15 nl_NL@euro
localedef -i ru_RU -f KOI8-R ru_RU.KOI8-R
localedef -i ru_RU -f UTF-8 ru_RU.UTF-8
localedef -i se_NO -f UTF-8 se_NO.UTF-8
localedef -i ta_IN -f UTF-8 ta_IN.UTF-8
localedef -i tr_TR -f UTF-8 tr_TR.UTF-8
localedef -i zh_CN -f GB18030 zh_CN.GB18030
localedef -i zh_HK -f BIG5-HKSCS zh_HK.BIG5-HKSCS
localedef -i zh_TW -f UTF-8 zh_TW.UTF-8

make localedata/install-locales
localedef -i C -f UTF-8 C.UTF-8
localedef -i ja_JP -f SHIFT_JIS ja_JP.SJIS 2> /dev/null || true

cat > /etc/nsswitch.conf << "NSS"
passwd: files
group: files
shadow: files

hosts: files dns
networks: files

protocols: files
services: files
ethers: files
rpc: files
NSS

tar -xf ../../tzdata2024a.tar.gz

ZONEINFO=/usr/share/zoneinfo
mkdir -pv $ZONEINFO/{posix,right}

for tz in etcetera southamerica northamerica europe africa antarctica  \
          asia australasia backward; do
	zic -L /dev/null   -d $ZONEINFO       ${tz}
    zic -L /dev/null   -d $ZONEINFO/posix ${tz}
    zic -L leapseconds -d $ZONEINFO/right ${tz}
done

cp -v zone.tab zone1970.tab iso3166.tab $ZONEINFO
zic -d $ZONEINFO -p America/New_York
unset ZONEINFO

tmzn=$(tzselect)

ln -sfv /usr/share/zoneinfo/$tmzn /etc/localtime

cat > /etc/ld.so.conf << "LDCONF"
# Begin /etc/ld.so.conf
/usr/local/lib
/opt/lib
LDCONF

cat >> /etc/ld.so.conf << "LDCONF"
# Add an include directory
include /etc/ld.so.conf.d/*.conf
LDCONF

mkdir -pv /etc/ld.so.conf.d

# Zlib
tar -xvzf zlib*.tar.gz && cd zlib*/
./configure --prefix=/usr
make -j$(nproc) && make check && make install
rm -fv /usr/lib/libz.a
cd /sources

# Bzip
tar -xvzf bzip2*.tar.gz && cd bzip2*/
patch -Np1 -i ../bzip2*.patch
sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
make -j$(nproc) -f Makefile-libbz2_so && make clean && make -j$(nproc) && make PREFIX=/usr install
cp -av libbz2.so.* /usr/lib
ln -sv libbz2.so.1.0.8 /usr/lib/libbz2.so
cp -v bzip2-shared /usr/bin/bzip2
for i in /usr/bin/{bzcat,bunzip2}; do
	ln -sfv bzip2 $i
done
rm -fv /usr/lib/libbz2.a
cd /sources

# Xz
tar -xvJf xz*.tar.xz && cd xz*/
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/xz-5.6.2
make -j$(nproc) && make check && make install
cd /sources

# Lz4
tar -xvzf lz4*.tar.gz && cd lz4*/
make -j$(nproc) BUILD_STATIC=no PREFIX=/usr && make -j1 check && make BUILD_STATIC=no PREFIX=/usr install
cd /sources

# Zstd
tar -xvzf zstd*.tar.gz && cd zstd*/
make -j$(nproc) prefix=/usr && make check && make prefix=/usr install
rm -v /usr/lib/libzstd.a
cd /sources

# File
tar -xvzf file*.tar.gz && cd file*/
/configure --prefix=/usr
make -j$(nproc) && make check && make install
cd /sources

# Readline
tar -xvzf readline*.tar.gz && cd readline*/
sed -i '/MV.*old/d' Makefile.in
sed -i '/{OLDSUFF}/c:' support/shlib-install
sed -i 's/-Wl,-rpath,[^ ]*//' support/shobj-conf
./configure --prefix=/usr    \
            --disable-static \
            --with-curses    \
            --docdir=/usr/share/doc/readline-8.2.13
make -j$(nproc) SHLIB_LIBS="-lncursesw" && make SHLIB_LIBS="-lncursesw" install
install -v -m644 doc/*.{ps,pdf,html,dvi} /usr/share/doc/readline-8.2.13
cd /sources

# M4
tar -xvJf m4*.tar.xz && cd m4*/
./configure --prefix=/usr
make -j$(nproc) && make check && make install
cd /sources

# Bc
tar -xvJf bc*.tar.xz && cd bc*/
CC=gcc ./configure --prefix=/usr -G -O3 -r
make -j$(nproc) && make test && make install
cd /sources

# Flex
tar -xvzf flex*.tar.gz && cd flex*/
./configure --prefix=/usr \
            --docdir=/usr/share/doc/flex-2.6.4 \
            --disable-static
make -j$(nproc) && make check && make install
ln -sv flex   /usr/bin/lex
ln -sv flex.1 /usr/share/man/man1/lex.1
cd /sources

# Tcl
tar -xvzf tcl*src.tar.gz && cd tcl*/
SRCDIR=$(pwd)
cd unix
./configure --prefix=/usr           \
            --mandir=/usr/share/man \
            --disable-rpath
make -j$(nproc)

sed -e "s|$SRCDIR/unix|/usr/lib|" \
    -e "s|$SRCDIR|/usr/include|"  \
    -i tclConfig.sh

sed -e "s|$SRCDIR/unix/pkgs/tdbc1.1.7|/usr/lib/tdbc1.1.7|" \
    -e "s|$SRCDIR/pkgs/tdbc1.1.7/generic|/usr/include|"    \
    -e "s|$SRCDIR/pkgs/tdbc1.1.7/library|/usr/lib/tcl8.6|" \
    -e "s|$SRCDIR/pkgs/tdbc1.1.7|/usr/include|"            \
    -i pkgs/tdbc1.1.7/tdbcConfig.sh

sed -e "s|$SRCDIR/unix/pkgs/itcl4.2.4|/usr/lib/itcl4.2.4|" \
    -e "s|$SRCDIR/pkgs/itcl4.2.4/generic|/usr/include|"    \
    -e "s|$SRCDIR/pkgs/itcl4.2.4|/usr/include|"            \
    -i pkgs/itcl4.2.4/itclConfig.sh

unset SRCDIR
make test && make install
chmod -v u+w /usr/lib/libtcl8.6.so
make install-private-headers
ln -sfv tclsh8.6 /usr/bin/tclsh     
mv /usr/share/man/man3/{Thread,Tcl_Thread}.3
cd ..
tar -xf ../tcl8.6.14-html.tar.gz --strip-components=1
mkdir -v -p /usr/share/doc/tcl-8.6.14
cp -v -r  ./html/* /usr/share/doc/tcl-8.6.14
cd /sources

# Expect
tar -xvzf expect*.tar.gz && cd expect*/
python3 -c 'from pty import spawn; spawn(["echo", "ok"])'
patch -Np1 -i ../expect*.patch
./configure --prefix=/usr           \
            --with-tcl=/usr/lib     \
            --enable-shared         \
            --disable-rpath         \
            --mandir=/usr/share/man \
            --with-tclinclude=/usr/include
make -j$(nproc) && make test && make install
ln -svf expect5.45.4/libexpect5.45.4.so /usr/lib
cd /sources

# DejaGNU
tar -xvzf dejagnu*.tar.gz && cd dejagnu*/
mkdir -v build && cd build
../configure --prefix=/usr
makeinfo --html --no-split -o doc/dejagnu.html ../doc/dejagnu.texi
makeinfo --plaintext       -o doc/dejagnu.txt  ../doc/dejagnu.texi
make check && make install
install -v -dm755  /usr/share/doc/dejagnu-1.6.3
install -v -m644   doc/dejagnu.{html,txt} /usr/share/doc/dejagnu-1.6.3
rm -rf build
cd /sources

# Pkgconf
tar -xvJf pkgconf*.tar.xz && cd pkgconf*/
./configure --prefix=/usr              \
            --disable-static           \
            --docdir=/usr/share/doc/pkgconf-2.3.0
make -j$(nproc) && make install
ln -sv pkgconf   /usr/bin/pkg-config
ln -sv pkgconf.1 /usr/share/man/man1/pkg-config.1
cd /sources

# Binutils
tar -xvJf binutils*.tar.xz && cd binutils*/
mkdir -v build && cd build
../configure --prefix=/usr       \
             --sysconfdir=/etc   \
             --enable-gold       \
             --enable-ld=default \
             --enable-plugins    \
             --enable-shared     \
             --disable-werror    \
             --enable-64-bit-bfd \
             --enable-new-dtags  \
             --with-system-zlib  \
             --enable-default-hash-style=gnu
make -j$(nproc) tooldir=/usr && make -k check && make tooldir=/usr install
rm -fv /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a
rm -rf build
cd /sources

# Gmp
tar -xvJf gmp*.tar.xz && cd gmp*/
./configure --prefix=/usr    \
            --enable-cxx     \
            --disable-static \
            --docdir=/usr/share/doc/gmp-6.3.0
make -j$(nproc) && make html
make check 2>&1 | tee gmp-check-log
make install && make install-html
cd /sources

# Mpfr
tar -xvJf mpfr*.tar.xz && cd mpfr*/
./configure --prefix=/usr        \
            --disable-static     \
            --enable-thread-safe \
            --docdir=/usr/share/doc/mpfr-4.2.1
make && make html
make check
make install && make install-html
cd /sources

# Mpc
tar -xvzf mpc*.tar.gz && cd mpc*/
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/mpc-1.3.1
make && make html
make check
make install && make install-html
cd /sources

# Attr
tar -xvzf attr*.tar.gz && cd attr*/
./configure --prefix=/usr     \
            --disable-static  \
            --sysconfdir=/etc \
            --docdir=/usr/share/doc/attr-2.5.2
make -j$(nproc) && make check
make install
cd /sources

# Acl
tar -xvzf acl*.tar.gz && cd acl*/
./configure --prefix=/usr         \
            --disable-static      \
            --docdir=/usr/share/doc/acl-2.3.2
make -j$(nproc) && make install
cd /sources

# Libcap
tar -xvJf libcap*.tar.xz && cd libcap*/
sed -i '/install -m.*STA/d' libcap/Makefile
make -j$(nproc) prefix=/usr lib=lib 
make test && make prefix=/usr lib=lib install
cd /sources

# Libxcrypt
tar -xvJf libxcrypt*.tar.xz && cd libxcrypt*/
./configure --prefix=/usr                \
            --enable-hashes=strong,glibc \
            --enable-obsolete-api=no     \
            --disable-static             \
            --disable-failure-tokens
make -j$(nproc) && make check
make install && make distclean
./configure --prefix=/usr                \
            --enable-hashes=strong,glibc \
            --enable-obsolete-api=glibc  \
            --disable-static             \
            --disable-failure-tokens
make -j$(nproc)
cp -av --remove-destination .libs/libcrypt.so.1* /usr/lib
cd /sources

# Shadow
tar -xvJf shadow*.tar.xz && cd shadow*/
sed -i 's/groups$(EXEEXT) //' src/Makefile.in
find man -name Makefile.in -exec sed -i 's/groups\.1 / /'   {} \;
find man -name Makefile.in -exec sed -i 's/getspnam\.3 / /' {} \;
find man -name Makefile.in -exec sed -i 's/passwd\.5 / /'   {} \;
sed -i 's:DICTPATH.*:DICTPATH\t/lib/cracklib/pw_dict:' etc/login.defs
touch /usr/bin/passwd
./configure --sysconfdir=/etc   \
            --disable-static    \
            --with-{b,yes}crypt \
            --without-libbsd    \
            --with-group-name-max-length=32
make -j$(nproc)
make exec_prefix=/usr install && make -C man install-man
pwconv && grpconv
mkdir -p /etc/default && useradd -D --gid 999
sed -i '/MAIL/s/yes/no/' /etc/default/useradd
passwd root
cd /sources

# Gcc
tar -xvJf gcc*.tar.xz && cd gcc*/
case $(uname -m) in
	x86_64)
    	sed -e '/m64=/s/lib64/lib/' \
        	-i.orig gcc/config/i386/t-linux64
  	;;
esac
mkdir -v build && cd build
../configure --prefix=/usr            \
             LD=ld                    \
             --enable-languages=c,c++ \
             --enable-default-pie     \
             --enable-default-ssp     \
             --enable-host-pie        \
             --disable-multilib       \
             --disable-bootstrap      \
             --disable-fixincludes    \
             --with-system-zlib
make -j$(nproc)
ulimit -s -H unlimited
sed -e '/cpython/d'               -i ../gcc/testsuite/gcc.dg/plugin/plugin.exp
sed -e 's/no-pic /&-no-pie /'     -i ../gcc/testsuite/gcc.target/i386/pr113689-1.c
sed -e 's/300000/(1|300000)/'     -i ../libgomp/testsuite/libgomp.c-c++-common/pr109062.c
sed -e 's/{ target nonpic } //' \
    -e '/GOTPCREL/d'              -i ../gcc/testsuite/gcc.target/i386/fentryname3.c
chown -R tester .
su tester -c "PATH=$PATH make -k check"
../contrib/test_summary
make install
chown -v -R root:root \
    /usr/lib/gcc/$(gcc -dumpmachine)/14.2.0/include{,-fixed}
ln -svr /usr/bin/cpp /usr/lib
ln -sv gcc.1 /usr/share/man/man1/cc.1
ln -sfv ../../libexec/gcc/$(gcc -dumpmachine)/14.2.0/liblto_plugin.so \
        /usr/lib/bfd-plugins/
echo 'int main(){}' > dummy.c
cc dummy.c -v -Wl,--verbose &> dummy.log
readelf -l a.out | grep ': /lib'
grep -E -o '/usr/lib.*/S?crt[1in].*succeeded' dummy.log
grep -B4 '^ /usr/include' dummy.log
grep 'SEARCH.*/usr/lib' dummy.log |sed 's|; |\n|g'
grep "/lib.*/libc.so.6 " dummy.log
grep found dummy.log
rm -v dummy.c a.out dummy.log
mkdir -pv /usr/share/gdb/auto-load/usr/lib
mv -v /usr/lib/*gdb.py /usr/share/gdb/auto-load/usr/lib
cd /sources

# Ncurses
tar -xvzf ncurses*.tar.gz && cd ncurses*/
./configure --prefix=/usr           \
            --mandir=/usr/share/man \
            --with-shared           \
            --without-debug         \
            --without-normal        \
            --with-cxx-shared       \
            --enable-pc-files       \
            --with-pkg-config-libdir=/usr/lib/pkgconfig
make -j$(nproc) && make DESTDIR=$PWD/dest install
install -vm755 dest/usr/lib/libncursesw.so.6.5 /usr/lib
rm -v  dest/usr/lib/libncursesw.so.6.5
sed -e 's/^#if.*XOPEN.*$/#if 1/' \
    -i dest/usr/include/curses.h
cp -av dest/* /
for lib in ncurses form panel menu ; do
    ln -sfv lib${lib}w.so /usr/lib/lib${lib}.so
    ln -sfv ${lib}w.pc    /usr/lib/pkgconfig/${lib}.pc
done
ln -sfv libncursesw.so /usr/lib/libcurses.so
cp -v -R doc -T /usr/share/doc/ncurses-6.5
make distclean
./configure --prefix=/usr    \
            --with-shared    \
            --without-normal \
            --without-debug  \
            --without-cxx-binding \
            --with-abi-version=5
make sources libs
cp -av lib/lib*.so.5* /usr/lib
cd /sources

# Sed
tar -xvJf sed*.tar.xz && cd sed*/
./configure --prefix=/usr
make && make html
chown -R tester .
su tester -c "PATH=$PATH make check"
make install
install -d -m755           /usr/share/doc/sed-4.9
install -m644 doc/sed.html /usr/share/doc/sed-4.9
cd /sources

# Psmisc
tar -xvJf psmisc*.tar.xz && cd psmisc*/
./configure --prefix=/usr
make -j$(nproc) && make check
make install
cd /sources

# Gettext
tar -xvJf gettext*.tar.xz && cd gettext*/
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/gettext-0.22.5
make -j$(nproc) && make check
make install
chmod -v 0755 /usr/lib/preloadable_libintl.so
cd /sources

# Bison
tar -xvJf bison*.tar.xz && cd bison*/
./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
make -j$(nproc) && make check
make install
cd /sources

# Grep
tar -xvJf grep*.tar.xz && cd grep*/
sed -i "s/echo/#echo/" src/egrep.sh
./configure --prefix=/usr
make -j$(nproc) && make check
make install
cd /sources

# Bash
tar -xvzf bash*.tar.gz && cd bash*/
./configure --prefix=/usr             \
            --without-bash-malloc     \
            --with-installed-readline \
            bash_cv_strtold_broken=no \
            --docdir=/usr/share/doc/bash-5.2.32
make -j$(nproc) && chown -R tester .
su -s /usr/bin/expect tester << "TEST"
set timeout -1
spawn make tests
expect eof
lassign [wait] _ _ _ value
exit $value
TEST
make install
exec /usr/bin/bash --login
cd /sources

# Libtool
tar -xvJf libtool*.tar.xz && cd libtool*/
./configure --prefix=/usr
make -j$(nproc) && make -k check
make install
rm -fv /usr/lib/libltdl.a
cd /sources

# Gdbm
tar -xvzf gdbm*.tar.gz && cd gdbm*/
./configure --prefix=/usr    \
            --disable-static \
            --enable-libgdbm-compat
make -j$(nproc) && make -k check
make install
cd /sources

# Gperf
tar -xvzf gperf*.tar.gz && cd tar -xvzf gdbm*.tar.gz && cd gdbm*/*/
./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.1
make -j$(nproc) && make -j1 check
make install
cd /sources

# Expat
tar -xvJf expat*.tar.xz && cd expat*/
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/expat-2.6.2
make -j$(nproc) && make check
make install
install -v -m644 doc/*.{html,css} /usr/share/doc/expat-2.6.2
cd /sources

# Inetutils
tar -xvJf inetutils*.tar.xz && cd inetutils*/
sed -i 's/def HAVE_TERMCAP_TGETENT/ 1/' telnet/telnet.c
./configure --prefix=/usr        \
            --bindir=/usr/bin    \
            --localstatedir=/var \
            --disable-logger     \
            --disable-whois      \
            --disable-rcp        \
            --disable-rexec      \
            --disable-rlogin     \
            --disable-rsh        \
            --disable-servers
make -j$(nproc) && make check
make install
mv -v /usr/{,s}bin/ifconfig
cd /sources

# Less
tar -xvzf less*.tar.gz && cd less*/
./configure --prefix=/usr --sysconfdir=/etc
make -j$(nproc) && make check
make install
cd /sources

# Perl
tar -xvJf perl*.tar.zz && cd perl*/
export BUILD_ZLIB=False
export BUILD_BZIP2=0
sh Configure -des                                          \
             -D prefix=/usr                                \
             -D vendorprefix=/usr                          \
             -D privlib=/usr/lib/perl5/5.40/core_perl      \
             -D archlib=/usr/lib/perl5/5.40/core_perl      \
             -D sitelib=/usr/lib/perl5/5.40/site_perl      \
             -D sitearch=/usr/lib/perl5/5.40/site_perl     \
             -D vendorlib=/usr/lib/perl5/5.40/vendor_perl  \
             -D vendorarch=/usr/lib/perl5/5.40/vendor_perl \
             -D man1dir=/usr/share/man/man1                \
             -D man3dir=/usr/share/man/man3                \
             -D pager="/usr/bin/less -isR"                 \
             -D useshrplib                                 \
             -D usethreads
make -j$(nproc) 
TEST_JOBS=$(nproc) make test_harness
make install
unset BUILD_ZLIB BUILD_BZIP2
cd /sources

# Xml-Parser
tar -xvzf XML-Parser*.tar.gz && cd XML-Parser*/
perl Makefile.PL
make -j$(nproc) && make test
make install
cd /sources

# Intltool
tar -xvzf intltool*.tar.gz && cd intltool*/
sed -i 's:\\\${:\\\$\\{:' intltool-update.in
./configure --prefix=/usr
make -j$(nproc) && make check
make install
install -v -Dm644 doc/I18N-HOWTO /usr/share/doc/intltool-0.51.0/I18N-HOWTO
cd /sources

# Autoconf
tar -xvJf autoconf*.tar.xz && cd autoconf*/
./configure --prefix=/usr
make -j$(nproc) && make check
make install
cd /sources

# Automake
tar -xvJf automake*.tar.xz && cd automake*/
./configure --prefix=/usr --docdir=/usr/share/doc/automake-1.17
make -j$(nproc) && make -j$(($(nproc)>4?$(nproc):4)) check
make install
cd /sources

# Openssl
tar -xvzf openssl*.tar.gz && cd openssl*/
./config --prefix=/usr         \
         --openssldir=/etc/ssl \
         --libdir=lib          \
         shared                \
         zlib-dynamic
make -j$(nproc) && HARNESS_JOBS=$(nproc) make test
sed -i '/INSTALL_LIBS/s/libcrypto.a libssl.a//' Makefile
make MANSUFFIX=ssl install
mv -v /usr/share/doc/openssl /usr/share/doc/openssl-3.3.1
cp -vfr doc/* /usr/share/doc/openssl-3.3.1
cd /sources

# Kmod
tar -xvJf kmod*.tar.xz && cd kmod*/
./configure --prefix=/usr     \
            --sysconfdir=/etc \
            --with-openssl    \
            --with-xz         \
            --with-zstd       \
            --with-zlib       \
            --disable-manpages
make -j$(nproc) && make install

for target in depmod insmod modinfo modprobe rmmod; do
  	ln -sfv ../bin/kmod /usr/sbin/$target
  	rm -fv /usr/bin/$target
done
cd /sources

# Elfutils
tar -xvjf elfutils*.tar.bz2 && cd elfutils*/
./configure --prefix=/usr                \
            --disable-debuginfod         \
            --enable-libdebuginfod=dummy
make -j$(nproc) && make check
make -C libelf install
install -vm644 config/libelf.pc /usr/lib/pkgconfig
rm /usr/lib/libelf.a
cd /sources

# Libffi
tar -xvzf libffi*.tar.gz && cd libffi*/
/configure --prefix=/usr          \
            --disable-static       \
            --with-gcc-arch=native
make -j$(nproc) && make check
make install
cd /sources

# Python
tar -xvJf Python*.tar.xz && cd Python*/
./configure --prefix=/usr        \
            --enable-shared      \
            --with-system-expat  \
            --enable-optimizations
make -j$(nproc) && make test TESTOPTS="--timeout 120"
make install
cat > /etc/pip.conf << "PIP"
[global]
root-user-action = ignore
disable-pip-version-check = true
PIP
install -v -dm755 /usr/share/doc/python-3.12.5/html
tar --no-same-owner \
    -xvf ../python-3.12.5-docs-html.tar.bz2
cp -R --no-preserve=mode python-3.12.5-docs-html/* \
    /usr/share/doc/python-3.12.5/html
cd /sources

# Flit
tar -xvzf flit*.tar.gz && cd flit*/
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --no-user --find-links dist flit_core
cd /sources

# Wheel
tar -xvzf wheel*.tar.gz && cd wheel*/
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links=dist wheel
cd /sources

# Setuptools
tar -xvzf setuptools*.tar.gz && cd setuptools*/
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist setuptools
cd /sources

# Ninja
tar -xvzf ninja*.tar.gz && cd ninja*/
export NINJAJOBS=4
sed -i '/int Guess/a \
  int   j = 0;\
  char* jobs = getenv( "NINJAJOBS" );\
  if ( jobs != NULL ) j = atoi( jobs );\
  if ( j > 0 ) return j;\
' src/ninja.cc
python3 configure.py --bootstrap
install -vm755 ninja /usr/bin/
install -vDm644 misc/bash-completion /usr/share/bash-completion/completions/ninja
install -vDm644 misc/zsh-completion  /usr/share/zsh/site-functions/_ninja
cd /sources

# Meson
tar -xvzf meson*.tar.gz && cd meson*/
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --find-links dist meson
install -vDm644 data/shell-completions/bash/meson /usr/share/bash-completion/completions/meson
install -vDm644 data/shell-completions/zsh/_meson /usr/share/zsh/site-functions/_meson
cd /sources

# Coreutils
tar -xvJf coreutils*.tar.xz && cd coreutils*/
patch -Np1 -i ../coreutils*.patch
autoreconf -fiv
FORCE_UNSAFE_CONFIGURE=1 ./configure \
            --prefix=/usr            \
            --enable-no-install-program=kill,uptime
make -j$(nproc) && make NON_ROOT_USERNAME=tester check-root
groupadd -g 102 dummy -U tester
chown -R tester . 
su tester -c "PATH=$PATH make -k RUN_EXPENSIVE_TESTS=yes check" \
   < /dev/null
groupdel dummy
make install
mv -v /usr/bin/chroot /usr/sbin
mv -v /usr/share/man/man1/chroot.1 /usr/share/man/man8/chroot.8
sed -i 's/"1"/"8"/' /usr/share/man/man8/chroot.8
cd /sources

# Check
tar -xvzf check*.tar.gz & cd check*/
/configure --prefix=/usr --disable-static
make -j$(nproc) && make check
make docdir=/usr/share/doc/check-0.15.2 install
cd /sources

# Diffutils
tar -xvJf diffutils*.tar.xz && cd diffutils*/
./configure --prefix=/usr
make -j$(nproc) && make check
make install
cd /sources

# Gawk
tar -xvJf gawk*.tar.xz && cd gawk*/
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr
make -j$(nproc)
chown -R tester .
su tester -c "PATH=$PATH make check"
rm -f /usr/bin/gawk-5.3.0
make install
cd /sources

# Findutils
tar -xvJf findutils*.tar.xz && cd findutils*/
./configure --prefix=/usr --localstatedir=/var/lib/locate
make
chown -R tester .
su tester -c "PATH=$PATH make check"
make install
cd /sources

# Groff
tar -xvzf groff*.tar.gz && cd groff*/
PAGE=<paper_size> ./configure --prefix=/usr
make -j$(nproc) && make check
make install
cd /sources

# Gzip
tar -xvJf gzip*.tar.xz && cd gzip*/
./configure --prefix=/usr
make -j$(nproc) && make check
make install
cd /sources

# Iproute2
tar -xvJf iproute2*.tar.xz && cd iproute2*/
sed -i /ARPD/d Makefile
rm -fv man/man8/arpd.8
make -j$(nproc) NETNS_RUN_DIR=/run/netns && make SBINDIR=/usr/sbin install
mkdir -pv /usr/share/doc/iproute2-6.10.0
cp -v COPYING README* /usr/share/doc/iproute2-6.10.0
cd /sources

# Kbd
tar -xvJf kbd*.tar.xz && cd kbd*/
patch -Np1 -i ../kbd*.patch
sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure
sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in
./configure --prefix=/usr --disable-vlock
make -j$(nproc) && make check
make install
cp -R -v docs/doc -T /usr/share/doc/kbd-2.6.4
cd /sources

# Libpipeline
tar -xvzf libpipeline*.tar.gz && cd libpipeline*/
./configure --prefix=/usr
make -j$(nproc) && make check
make install
cd /sources

# Make
tar -xvzf make*.tar.gz && cd make*/
./configure --prefix=/usr
make -j$(nproc)
chown -R tester .
su tester -c "PATH=$PATH make check"
make install
cd /sources

# Patch
tar -xvJf patch*.tar.xz && cd patch*/
./configure --prefix=/usr
make -j$(nproc) && make check
make install
cd /sources

# Tar
tar -xvJf tar*.tar.xz && cd tar*/
FORCE_UNSAFE_CONFIGURE=1  \
./configure --prefix=/usr
make -j$(nproc) && make check
make install && make -C doc install-html docdir=/usr/share/doc/tar-1.35
cd /sources

# Texinfo
tar -xvJf texinfo*.tar.xz && cd texinfo*/
./configure --prefix=/usr
make -j$(nproc) && make check
make install && make TEXMF=/usr/share/texmf install-tex
cd /sources

# Vim
tar -xvzf vim*.tar.gz && cd vim*/
echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
./configure --prefix=/usr
make -j$(nproc)
chown -R tester .
su tester -c "TERM=xterm-256color LANG=en_US.UTF-8 make -j1 test" \
   &> vim-test.log
ln -sv vim /usr/bin/vi
for L in  /usr/share/man/{,*/}man1/vim.1; do
    ln -sv vim.1 $(dirname $L)/vi.1
done
ln -sv ../vim/vim91/doc /usr/share/doc/vim-9.1.0660

cat > /etc/vimrc << "RC"
source $VIMRUNTIME/defaults.vim
let skip_defaults_vim=1

set nocompatible
set backspace=2
set mouse=
syntax on
if (&term == "xterm") || (&term == "putty")
  set background=dark
endif
RC
cd /sources

# Markupsafe
tar -xvzf MarkupSafe*.tar.gz && cd Markupsafe*/
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --no-user --find-links dist Markupsafe
cd /sources

# Jinja
tar -xvzf jinja2*.tar.gz && cd jinja2*/
pip3 wheel -w dist --no-cache-dir --no-build-isolation --no-deps $PWD
pip3 install --no-index --no-user --find-links dist Jinja2
cd /sources

# Udev
tar -xvzf systemd*.tar.gz && cd systemd*/
sed -i -e 's/GROUP="render"/GROUP="video"/' \
       -e 's/GROUP="sgx", //' rules.d/50-udev-default.rules.in
sed '/systemd-sysctl/s/^/#/' -i rules.d/99-systemd.rules.in
sed '/NETWORK_DIRS/s/systemd/udev/' -i src/basic/path-lookup.h
mkdir -p build && cd build
meson setup ..                  \
      --prefix=/usr             \
      --buildtype=release       \
      -D mode=release           \
      -D dev-kvm-mode=0660      \
      -D link-udev-shared=false \
      -D logind=false           \
      -D vconsole=false
export udev_helpers=$(grep "'name' :" ../src/udev/meson.build | \
                      awk '{print $3}' | tr -d ",'" | grep -v 'udevadm')
ninja udevadm systemd-hwdb                                           \
      $(ninja -n | grep -Eo '(src/(lib)?udev|rules.d|hwdb.d)/[^ ]*') \
      $(realpath libudev.so --relative-to .)                         \
      $udev_helpers
install -vm755 -d {/usr/lib,/etc}/udev/{hwdb.d,rules.d,network}
install -vm755 -d /usr/{lib,share}/pkgconfig
install -vm755 udevadm                             /usr/bin/
install -vm755 systemd-hwdb                        /usr/bin/udev-hwdb
ln      -svfn  ../bin/udevadm                      /usr/sbin/udevd
cp      -av    libudev.so{,*[0-9]}                 /usr/lib/
install -vm644 ../src/libudev/libudev.h            /usr/include/
install -vm644 src/libudev/*.pc                    /usr/lib/pkgconfig/
install -vm644 src/udev/*.pc                       /usr/share/pkgconfig/
install -vm644 ../src/udev/udev.conf               /etc/udev/
install -vm644 rules.d/* ../rules.d/README         /usr/lib/udev/rules.d/
install -vm644 $(find ../rules.d/*.rules \
                      -not -name '*power-switch*') /usr/lib/udev/rules.d/
install -vm644 hwdb.d/*  ../hwdb.d/{*.hwdb,README} /usr/lib/udev/hwdb.d/
install -vm755 $udev_helpers                       /usr/lib/udev
install -vm644 ../network/99-default.link          /usr/lib/udev/network
tar -xvf ../../udev-lfs-20230818.tar.xz
make -f udev-lfs-20230818/Makefile.lfs install
tar -xf ../../systemd-man-pages-256.4.tar.xz                            \
    --no-same-owner --strip-components=1                              \
    -C /usr/share/man --wildcards '*/udev*' '*/libudev*'              \
                                  '*/systemd.link.5'                  \
                                  '*/systemd-'{hwdb,udevd.service}.8

sed 's|systemd/network|udev/network|'                                 \
    /usr/share/man/man5/systemd.link.5                                \
  > /usr/share/man/man5/udev.link.5

sed 's/systemd\(\\\?-\)/udev\1/' /usr/share/man/man8/systemd-hwdb.8   \
                               > /usr/share/man/man8/udev-hwdb.8

sed 's|lib.*udevd|sbin/udevd|'                                        \
    /usr/share/man/man8/systemd-udevd.service.8                       \
  > /usr/share/man/man8/udevd.8

rm /usr/share/man/man*/systemd*
unset udev_helpers
udev-hwdb update
cd /sources

# Man-db
tar -xvJf man-db*.tar.xz && cd man-db*/
./configure --prefix=/usr                         \
            --docdir=/usr/share/doc/man-db-2.12.1 \
            --sysconfdir=/etc                     \
            --disable-setuid                      \
            --enable-cache-owner=bin              \
            --with-browser=/usr/bin/lynx          \
            --with-vgrind=/usr/bin/vgrind         \
            --with-grap=/usr/bin/grap             \
            --with-systemdtmpfilesdir=            \
            --with-systemdsystemunitdir=
make -j$(nproc) && make check
make install
cd /sources

# Procps
tar -xvJf procps*.tar.xz && cd procps*/
./configure --prefix=/usr                           \
            --docdir=/usr/share/doc/procps-ng-4.0.4 \
            --disable-static                        \
            --disable-kill
make -$(nprocs) 
chown -R tester .
su tester -c "PATH=$PATH make check"
make install
cd /sources

# Util-linux
tar -xvJf util-linux*.tar.xz && cd util-linux*/
./configure --bindir=/usr/bin     \
            --libdir=/usr/lib     \
            --runstatedir=/run    \
            --sbindir=/usr/sbin   \
            --disable-chfn-chsh   \
            --disable-login       \
            --disable-nologin     \
            --disable-su          \
            --disable-setpriv     \
            --disable-runuser     \
            --disable-pylibmount  \
            --disable-liblastlog2 \
            --disable-static      \
            --without-python      \
            --without-systemd     \
            --without-systemdsystemunitdir        \
            ADJTIME_PATH=/var/lib/hwclock/adjtime \
            --docdir=/usr/share/doc/util-linux-2.40.2
make -j$(nproc)
touch /etc/fstab
chown -R tester .
su tester -c "make -k check"
make install
cd /sources

# E2fsprogs
tar -xvzf e2fsprogs*.tar.gz && cd e2fsprogs*/
mkdir -v build && cd build
../configure --prefix=/usr           \
             --sysconfdir=/etc       \
             --enable-elf-shlibs     \
             --disable-libblkid      \
             --disable-libuuid       \
             --disable-uuidd         \
             --disable-fsck
make -j$(nproc) && make check
make install
rm -fv /usr/lib/{libcom_err,libe2p,libext2fs,libss}.a
gunzip -v /usr/share/info/libext2fs.info.gz
install-info --dir-file=/usr/share/info/dir /usr/share/info/libext2fs.info
makeinfo -o      doc/com_err.info ../lib/et/com_err.texinfo
install -v -m644 doc/com_err.info /usr/share/info
install-info --dir-file=/usr/share/info/dir /usr/share/info/com_err.info
sed 's/metadata_csum_seed,//' -i /etc/mke2fs.conf
cd /sources

# Sysklogd
tar -xvzf sysklogd*.tar.gz && cd sysklogd*/
./configure --prefix=/usr      \
            --sysconfdir=/etc  \
            --runstatedir=/run \
            --without-logger
make -j$(nproc) && make install
cat > /etc/syslog.conf << "SYSLOG"
auth,authpriv.* -/var/log/auth.log
*.*;auth,authpriv.none -/var/log/sys.log
daemon.* -/var/log/daemon.log
kern.* -/var/log/kern.log
mail.* -/var/log/mail.log
user.* -/var/log/user.log
*.emerg *
secure_mode 2
SYSLOG
cd /sources

# Sysvinit
tar -xvJf sysvinit*.tar.xz && cd sysvinit*/
patch -Np1 -i ../sysvinit*.patch
make -j$(nproc) && make install
cd /sources

rm -rf /tmp/{*,.*}
find /usr/lib /usr/libexec -name \*.la -delete
find /usr -depth -name $(uname -m)-lfs-linux-gnu\* | xargs rm -rf
userdel -r tester

# Lfs-bootscripts
tar -xvJf lfs-bootscripts*.tar.xz && cd lfs-bootscripts*/
make install
cd /sources

bash /usr/lib/udev/init-net-rules.sh
cat /etc/udev/rules.d/70-persistent-net.rules

echo -e "Setting up network configuration"

export IFACE=$(grep -o 'NAME="[^"]*"' /etc/udev/rules.d/70-persistent-net.rules | awk -F'=' '{gsub(/"/, "", $2); print $2}')
export ONBOOT=$(ip link show "$IFACE" | grep -q "state UP" && echo "yes" || echo "no")
export SERVICE=$(ip link show "$IFACE" | grep -oP "(?<=link/)[^ ]+")
export IP=$(ip -4 addr show "$IFACE" | grep -oP "(?<=inet\s)\d+(\.\d+){3}")
export GATEWAY=$(ip route | grep -m1 default | awk '{print $3}')
export PREFIX=$(ip -4 addr show "$IFACE" | grep -oP "(?<=inet\s)\d+(\.\d+){3}/\d+" | awk -F'/' '{print $2}')
export BROADCAST=$(ip -4 addr show "$IFACE" | grep -oP "(?<=brd\s)\d+(\.\d+){3}")

echo "ONBOOT=$ONBOOT"
echo "IFACE=$INTFACE"
echo "SERVICE=$SERVICE"
echo "IP=$IP"
echo "GATEWAY=$GATEWAY"
echo "PREFIX=$PREFIX"
echo "BROADCAST=$BROADCAST"

sed -e '/^AlternativeNamesPolicy/s/=.*$/=/'  \
       /usr/lib/udev/network/99-default.link \
     > /etc/udev/network/99-default.link

cd /etc/sysconfig/
cat > ifconfig.eth0 << "IFCONF"
ONBOOT=yes
IFACE=$IFACE
SERVICE=$SERVICE
IP=$IP
GATEWAY=$GATEWAY
PREFIX=$PREFIX
BROADCAST=$BROADCAST
IFCONF

cat > /etc/resolv.conf << "RESLOV"
domain cloudflare IPv4
nameserver 1.1.1.1
nameserver 1.0.0.1
RESOLV

read -p "Type in a hostname for your system: " hsnm

echo "$hsnm" > /etc/hostname

cat > /etc/inittab << "INIT"
id:3:initdefault:

si::sysinit:/etc/rc.d/init.d/rc S

l0:0:wait:/etc/rc.d/init.d/rc 0
l1:S1:wait:/etc/rc.d/init.d/rc 1
l2:2:wait:/etc/rc.d/init.d/rc 2
l3:3:wait:/etc/rc.d/init.d/rc 3
l4:4:wait:/etc/rc.d/init.d/rc 4
l5:5:wait:/etc/rc.d/init.d/rc 5
l6:6:wait:/etc/rc.d/init.d/rc 6

ca:12345:ctrlaltdel:/sbin/shutdown -t1 -a -r now

su:S06:once:/sbin/sulogin
s1:1:respawn:/sbin/sulogin

1:2345:respawn:/sbin/agetty --noclear tty1 9600
2:2345:respawn:/sbin/agetty tty2 9600
3:2345:respawn:/sbin/agetty tty3 9600
4:2345:respawn:/sbin/agetty tty4 9600
5:2345:respawn:/sbin/agetty tty5 9600
6:2345:respawn:/sbin/agetty tty6 9600
INIT

cat > /etc/sysconfig/clock << "SYSCLOCK"
UTC=1
# Set this to any options you might need to give to hwclock,
# such as machine hardware clock type for Alphas.
CLOCKPARAMS=
SYSCLOCK

cat > /etc/sysconfig/console << "SYSCONSOLE"
KEYMAP="uk"
FONT="lat2a-16 -m 8859-1"
LOGLEVEL="3"
SYSCONSOLE

echo -e "\nFind your locale and remember it."; sleep 3 && locale -a | less && \
read -p "What locale do you want: " loc && LC_ALL=$loc 
export locchar=$(locale charmap)

if [[ "$loc" == *.* ]]; then
	loc="${loc%%.*}"
fi

cat > /etc/profile << "PROF"
for i in $(locale); do
  unset ${i%=*}
done

if [[ "$TERM" = linux ]]; then
  export LANG=C.UTF-8
else
  export LANG=$loc.$locchar
fi
PROF

cat > /etc/inputrc << "IRC"
# Modified by Chris Lynn <roryo@roryo.dynup.net>

# Allow the command prompt to wrap to the next line
set horizontal-scroll-mode Off

# Enable 8-bit input
set meta-flag On
set input-meta On

# Turns off 8th bit stripping
set convert-meta Off

# Keep the 8th bit for display
set output-meta On

# none, visible or audible
set bell-style none

# All of the following map the escape sequence of the value
# contained in the 1st argument to the readline specific functions
"\eOd": backward-word
"\eOc": forward-word

# for linux console
"\e[1~": beginning-of-line
"\e[4~": end-of-line
"\e[5~": beginning-of-history
"\e[6~": end-of-history
"\e[3~": delete-char
"\e[2~": quoted-insert

# for xterm
"\eOH": beginning-of-line
"\eOF": end-of-line

# for Konsole
"\e[H": beginning-of-line
"\e[F": end-of-line
IRC

cat > /etc/shells << "SHELL"
/bin/sh
/bin/bash
SHELL

cat > /etc/fstab << "FSTAB"
# file system  mount-point    type     options             dump  fsck
#                                                                order

/dev/<xxx>     /              <fff>    defaults            1     1
/dev/<yyy>     swap           swap     pri=1               0     0
proc           /proc          proc     nosuid,noexec,nodev 0     0
sysfs          /sys           sysfs    nosuid,noexec,nodev 0     0
devpts         /dev/pts       devpts   gid=5,mode=620      0     0
tmpfs          /run           tmpfs    defaults            0     0
devtmpfs       /dev           devtmpfs mode=0755,nosuid    0     0
tmpfs          /dev/shm       tmpfs    nosuid,nodev        0     0
cgroup2        /sys/fs/cgroup cgroup2  nosuid,noexec,nodev 0     0
FSTAB


EOF
