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

mkdir -pv $LFS/{dev,proc,sys,run} && ls $LFS
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
make
cp -v gettext-tools/src/{msgfmt,msgmerge,xgettext} /usr/bin
cd /sources
# Bison
tar -xvJf gettext*.tar.xz && cd gettext*/ 
./configure --prefix=/usr \
            --docdir=/usr/share/doc/bison-3.8.2
make && make install
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
make && make install
cd /sources

# Python
tar -xvJf python*.tar.xz && cd python*/
./configure --prefix=/usr   \
            --enable-shared \
            --without-ensurepip
make && make install
cd /sources

# Texinfo
tar -xvJf texinfo*.tar.xz && cd texinfo*/
./configure --prefix=/usr
make && make install
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
make && make install

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
make && make check
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
make && make check && make install
rm -fv /usr/lib/libz.a
cd /sources

# Bzip
tar -xvzf bzip2*.tar.gz && cd bzip2*/
patch -Np1 -i ../bzip2*.patch
sed -i 's@\(ln -s -f \)$(PREFIX)/bin/@\1@' Makefile
sed -i "s@(PREFIX)/man@(PREFIX)/share/man@g" Makefile
make -f Makefile-libbz2_so && make clean && make && make PREFIX=/usr install
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
make && make check && make install
cd /sources

# Lz4
tar -xvzf lz4*.tar.gz && cd lz4*/
make BUILD_STATIC=no PREFIX=/usr && make -j1 check && make BUILD_STATIC=no PREFIX=/usr install
cd /sources

# Zstd
tar -xvzf zstd*.tar.gz && cd zstd*/
make prefix=/usr && make check && make prefix=/usr install
rm -v /usr/lib/libzstd.a
cd /sources

# File
tar -xvzf file*.tar.gz && cd file*/
/configure --prefix=/usr
make && make check && make install
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
make SHLIB_LIBS="-lncursesw" && make SHLIB_LIBS="-lncursesw" install
install -v -m644 doc/*.{ps,pdf,html,dvi} /usr/share/doc/readline-8.2.13
cd /sources

# M4
tar -xvJf m4*.tar.xz && cd m4*/
./configure --prefix=/usr
make && make check && make install
cd /sources

# Bc
tar -xvJf bc*.tar.xz && cd bc*/
CC=gcc ./configure --prefix=/usr -G -O3 -r
make && make test && make install
cd /sources

# Flex
tar -xvzf flex*.tar.gz && cd flex*/
./configure --prefix=/usr \
            --docdir=/usr/share/doc/flex-2.6.4 \
            --disable-static
make && make check && make install
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
make

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
make && make test && make install
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
make && make install
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
make tooldir=/usr && make -k check && make tooldir=/usr install
rm -fv /usr/lib/lib{bfd,ctf,ctf-nobfd,gprofng,opcodes,sframe}.a
rm -rf build
cd /sources

# Gmp
tar -xvJf gmp*.tar.xz && cd gmp*/
./configure --prefix=/usr    \
            --enable-cxx     \
            --disable-static \
            --docdir=/usr/share/doc/gmp-6.3.0
make && make html
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
make && make check
make install
cd /sources

# Acl
tar -xvzf acl*.tar.gz && cd acl*/
./configure --prefix=/usr         \
            --disable-static      \
            --docdir=/usr/share/doc/acl-2.3.2
make && make install
cd /sources

# Libcap
tar -xvJf libcap*.tar.xz && cd libcap*/
sed -i '/install -m.*STA/d' libcap/Makefile
make prefix=/usr lib=lib 
make test && make prefix=/usr lib=lib install
cd /sources

# Libxcrypt
tar -xvJf libxcrypt*.tar.xz && cd libxcrypt*/
./configure --prefix=/usr                \
            --enable-hashes=strong,glibc \
            --enable-obsolete-api=no     \
            --disable-static             \
            --disable-failure-tokens
make && make check
make install && make distclean
./configure --prefix=/usr                \
            --enable-hashes=strong,glibc \
            --enable-obsolete-api=glibc  \
            --disable-static             \
            --disable-failure-tokens
make
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
make
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
make
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
make && make DESTDIR=$PWD/dest install
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
make && make check
make install
cd /sources

# Gettext
tar -xvJf gettext*.tar.xz && cd gettext*/
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/gettext-0.22.5
make && make check
make install
chmod -v 0755 /usr/lib/preloadable_libintl.so
cd /sources

# Bison
tar -xvJf bison*.tar.xz && cd bison*/
./configure --prefix=/usr --docdir=/usr/share/doc/bison-3.8.2
make && make check
make install
cd /sources

# Grep
tar -xvJf grep*.tar.xz && cd grep*/
sed -i "s/echo/#echo/" src/egrep.sh
./configure --prefix=/usr
make && make check
make install
cd /sources

# Bash
tar -xvzf bash*.tar.gz && cd bash*/
./configure --prefix=/usr             \
            --without-bash-malloc     \
            --with-installed-readline \
            bash_cv_strtold_broken=no \
            --docdir=/usr/share/doc/bash-5.2.32
make && chown -R tester .
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
make && make -k check
make install
rm -fv /usr/lib/libltdl.a
cd /sources

# Gdbm
tar -xvzf gdbm*.tar.gz && cd gdbm*/
./configure --prefix=/usr    \
            --disable-static \
            --enable-libgdbm-compat
make && make -k check
make install
cd /sources

# Gperf
tar -xvzf gperf*.tar.gz && cd tar -xvzf gdbm*.tar.gz && cd gdbm*/*/
./configure --prefix=/usr --docdir=/usr/share/doc/gperf-3.1
make && make -j1 check
make install
cd /sources

# Expat
tar -xvJf expat*.tar.xz && cd expat*/
./configure --prefix=/usr    \
            --disable-static \
            --docdir=/usr/share/doc/expat-2.6.2
make && make check
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
make && make check
make install
mv -v /usr/{,s}bin/ifconfig
cd /sources

# Less
tar -xvzf less*.tar.gz && cd less*/
./configure --prefix=/usr --sysconfdir=/etc
make && make check
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
make 
TEST_JOBS=$(nproc) make test_harness
make install
unset BUILD_ZLIB BUILD_BZIP2
cd /sources

# Xml-Parser
tar -xvzf XML-Parser*.tar.gz && cd XML-Parser*/
perl Makefile.PL
make && make test
make install
cd /sources

# Intltool
tar -xvzf intltool*.tar.gz && cd intltool*/
sed -i 's:\\\${:\\\$\\{:' intltool-update.in
./configure --prefix=/usr
make && make check
make install
install -v -Dm644 doc/I18N-HOWTO /usr/share/doc/intltool-0.51.0/I18N-HOWTO
cd /sources

# Autoconf
tar -xvJf autoconf*.tar.xz && cd autoconf*/
./configure --prefix=/usr
make && make check
make install
cd /sources

# Automake
tar -xvJf automake*.tar.xz && cd automake*/
./configure --prefix=/usr --docdir=/usr/share/doc/automake-1.17
make && make -j$(($(nproc)>4?$(nproc):4)) check
make install
cd /sources

# Openssl
tar -xvzf openssl*.tar.gz && cd openssl*/
./config --prefix=/usr         \
         --openssldir=/etc/ssl \
         --libdir=lib          \
         shared                \
         zlib-dynamic
make && HARNESS_JOBS=$(nproc) make test
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
make && make install

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
make && make check
make -C libelf install
install -vm644 config/libelf.pc /usr/lib/pkgconfig
rm /usr/lib/libelf.a
cd /sources

# Libffi
tar -xvzf libffi*.tar.gz && cd libffi*/
/configure --prefix=/usr          \
            --disable-static       \
            --with-gcc-arch=native
make && make check
make install
cd /sources

# Python
tar -xvJf Python*.tar.xz && cd Python*/
./configure --prefix=/usr        \
            --enable-shared      \
            --with-system-expat  \
            --enable-optimizations
make && make test TESTOPTS="--timeout 120"
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
make && make NON_ROOT_USERNAME=tester check-root
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
make && make check
make docdir=/usr/share/doc/check-0.15.2 install
cd /sources

# Diffutils
tar -xvJf diffutils*.tar.xz && cd diffutils*/
./configure --prefix=/usr
make && make check
make install
cd /sources

# Gawk
tar -xvJf gawk*.tar.xz && cd gawk*/
sed -i 's/extras//' Makefile.in
./configure --prefix=/usr
make
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
make && make check
make install
cd /sources
   
# Gzip
tar -xvJf gzip*.tar.xz && cd gzip*/
./configure --prefix=/usr
make && make check
make install
cd /sources

# Iproute2
tar -xvJf iproute2*.tar.xz && cd iproute2*/
sed -i /ARPD/d Makefile
rm -fv man/man8/arpd.8
make NETNS_RUN_DIR=/run/netns && make SBINDIR=/usr/sbin install
mkdir -pv /usr/share/doc/iproute2-6.10.0
cp -v COPYING README* /usr/share/doc/iproute2-6.10.0
cd /sources

# Kbd
tar -xvJf kbd*.tar.xz && cd kbd*/
patch -Np1 -i ../kbd*.patch
sed -i '/RESIZECONS_PROGS=/s/yes/no/' configure
sed -i 's/resizecons.8 //' docs/man/man8/Makefile.in
./configure --prefix=/usr --disable-vlock
make && make check
make install
cp -R -v docs/doc -T /usr/share/doc/kbd-2.6.4
cd /sources

# Libpipeline
tar -xvzf libpipeline*.tar.gz && cd libpipeline*/
./configure --prefix=/usr
make && make check
make install
cd /sources

# Make
tar -xvzf make*.tar.gz && cd make*/
./configure --prefix=/usr
make
chown -R tester .
su tester -c "PATH=$PATH make check"
make install
cd /sources

# Patch
tar -xvJf patch*.tar.xz && cd patch*/
./configure --prefix=/usr
make && make check
make install
cd /sources

# Tar
tar -xvJf tar*.tar.xz && cd tar*/
FORCE_UNSAFE_CONFIGURE=1  \
./configure --prefix=/usr
make && make check
make install && make -C doc install-html docdir=/usr/share/doc/tar-1.35
cd /sources

# Texinfo
tar -xvJf texinfo*.tar.xz && cd texinfo*/
./configure --prefix=/usr
make && make check
make install && make TEXMF=/usr/share/texmf install-tex
cd /sources

# Vim
tar -xvzf vim*.tar.gz && cd vim*/
echo '#define SYS_VIMRC_FILE "/etc/vimrc"' >> src/feature.h
./configure --prefix=/usr
make
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
make && make check
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
make
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
make && make check
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
make && make install
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
make && make install
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


lsblk
read -p "Re-enter the disk you are installing on (e.g., /dev/sda): " disk

# Determine disk prefix
if [[ "$disk" == /dev/nvme* ]]; then
    disk_prefix="p"
else
    disk_prefix=""
fi

export bootP="/dev/${disk}${disk_prefix}1"
export swapP="/dev/${disk}${disk_prefix}2"
export rootP="/dev/${disk}${disk_prefix}3"

cat > /etc/fstab << "FSTAB"
# file system  mount-point    type     options             dump  fsck
#                                                                order

$rootP         /              ext4     defaults            1     1
$booP          /boot          vfat     noauto              1     2
$swapP         swap           swap     pri=1               0     0
proc           /proc          proc     nosuid,noexec,nodev 0     0
sysfs          /sys           sysfs    nosuid,noexec,nodev 0     0
devpts         /dev/pts       devpts   gid=5,mode=620      0     0
tmpfs          /run           tmpfs    defaults            0     0
devtmpfs       /dev           devtmpfs mode=0755,nosuid    0     0
tmpfs          /dev/shm       tmpfs    nosuid,nodev        0     0
cgroup2        /sys/fs/cgroup cgroup2  nosuid,noexec,nodev 0     0
FSTAB

# Linux kernel
cd /sources
tar -xvJf linux*.tar.xz && cd linux*/
make mrproper
make defconfig
sed -i '/#/d' .config
sed -i 's/CONFIG_DRM=y/CONFIG_DRM=m/' .config
sed -i 's/CONFIG_NLS_CODEPAGE_437=y/CONFIG_NLS_CODEPAGE_437=m/' .config
sed -i 's/CONFIG_NLS_ISO8859_1=y/CONFIG_NLS_ISO8859_1=m/' .config
# Check if the disk is an NVMe device
if [[ "$disk" == /dev/nvme* ]]; then
    sed -i '/^CONFIG_BLK_DEV_NVME/d' .config
    echo "CONFIG_BLK_DEV_NVME=y" >> .config
fi
static_configs=(
    "CONFIG_DRM_I915=m"
    "CONFIG_DRM_RADEON=m"
    "CONFIG_DRM_AMDGPU=m"
    "CONFIG_DRM_AMDGPU_SI=y"
    "CONFIG_DRM_AMDGPU_CIK=y"
    "CONFIG_DRM_AMDG_DC=y"
    "CONFIG_DRM_VGEM=m"
    "CONFIG_DRM_VMWGFX=m"
    "ONFIG_DRM_NOUVEAU=y"
    "CONFIG_FUSE_FS=y"
    "CONFIG_PSI=y"
    "CONFIG_MEMCG=y"
    "CONFIG_DRM_FBDEV_EMULATION=y"
    "CONFIG_FRAMEBUFFER_CONSOLE=y"
    "CONFIG_IRQ_REMAP=y"
    "CONFIG_X86_X2APIC=y"
    "CONFIG_HIGHMEM64G=y"
    "CONFIG_PARTITION_ADVANCED=y"
    "CONFIG_SYSFB_SIMPLEFB=y"
    "CONFIG_DRM_SIMPLEDRM=y"
    "CONFIG_AUDIT=y"
)
for config in "${static_configs[@]}"; do
    sed -i "/^${config%=*}/d" .config
    echo "$config" >> .config
done
make && make modules_install
mount /boot
cp -iv arch/x86/boot/bzImage /boot/vmlinuz-6.10.5-lfs-12.2
cp -iv System.map /boot/System.map-6.10.5
cp -iv .config /boot/config-6.10.5
cp -r Documentation -T /usr/share/doc/linux-6.10.5
chown -R 0:0
install -v -m755 -d /etc/modprobe.d
cat > /etc/modprobe.d/usb.conf << "MODPROB"
install ohci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i ohci_hcd ; true
install uhci_hcd /sbin/modprobe ehci_hcd ; /sbin/modprobe -i uhci_hcd ; true
MODPROB
cd /sources

# Wget
tar -xvzf wget*.tar.gz && cd wget*/
./configure --prefix=/usr      \
            --sysconfdir=/etc  \
            --with-ssl=openssl &&
make && make install
cd /sources

wget https://codeload.github.com/intel/Intel-Linux-Processor-Microcode-Data-Files/tar.gz/refs/tags/microcode-20241029 --directory-prefix=/sources
wget https://ftp.gnu.org/gnu/cpio/cpio-2.15.tar.bz2 --directory-prefix=/sources
wget https://github.com/vcrhonek/hwdata/archive/v0.385/hwdata-0.385.tar.gz --directory-prefix=/sources
wget https://www.kernel.org/pub/software/scm/git/git-2.46.0.tar.xz --directory-prefix=/sources
wget https://github.com/rhboot/efibootmgr/archive/18/efibootmgr-18.tar.gz --directory-prefix=/sources
wget http://ftp.rpm.org/popt/releases/popt-1.x/popt-1.19.tar.gz --directory-prefix=/sources
wget https://github.com/rhboot/efivar/archive/39/efivar-39.tar.gz --directory-prefix=/sources
wget https://downloads.sourceforge.net/freetype/freetype-2.13.3.tar.xz --directory-prefix=/sources
wget https://github.com/google/brotli/archive/v1.1.0/brotli-1.1.0.tar.gz --directory-prefix=/sources
wget https://cmake.org/files/v3.30/cmake-3.30.2.tar.gz --directory-prefix=/sources
wget https://curl.se/download/curl-8.9.1.tar.xz --directory-prefix=/sources
wget https://github.com/lfs-book/make-ca/archive/v1.14/make-ca-1.14.tar.gz --directory-prefix=/sources
wget https://github.com/p11-glue/p11-kit/releases/download/0.25.5/p11-kit-0.25.5.tar.xz --directory-prefix=/sources
wget https://ftp.gnu.org/gnu/libtasn1/libtasn1-4.19.0.tar.gz --directory-prefix=/sources
wget https://download.gnome.org/sources/librsvg/2.58/librsvg-2.58.3.tar.xz --directory-prefix=/sources
wget https://github.com/dosfstools/dosfstools/releases/download/v4.2/dosfstools-4.2.tar.gz --directory-prefix=/sources
wget https://ftp.gnu.org/gnu/which/which-2.21.tar.gz --directory-prefix=/sources

# Grub with UEFI support
tar -xvJf grub*.tar.xz && cd grub*/
mkdir -pv /usr/share/fonts/unifont &&
gunzip -c ../unifont-15.1.05.pcf.gz > /usr/share/fonts/unifont/unifont.pcf
unset {C,CPP,CXX,LD}FLAGS
echo depends bli part_gpt > grub-core/extra_deps.lst
case $(uname -m) in i?86 )
    tar xf ../gcc*.tar.xz
    mkdir gcc*/build
    pushd gcc*/build
        ../configure --prefix=$PWD/../../x86_64-gcc \
                     --target=x86_64-linux-gnu      \
                     --with-system-zlib             \
                     --enable-languages=c,c++       \
                     --with-ld=/usr/bin/ld
        make all-gcc
        make install-gcc
    popd
    export TARGET_CC=$PWD/x86_64-gcc/bin/x86_64-linux-gnu-gcc
esac
./configure --prefix=/usr        \
            --sysconfdir=/etc    \
            --disable-efiemu     \
            --enable-grub-mkfont \
            --with-platform=efi  \
            --target=x86_64      \
            --disable-werror     &&
unset TARGET_CC &&
make && make install &&
mv -v /etc/bash_completion.d/grub /usr/share/bash-completion/completions
cp -av dest/usr/bin/grub-mount /usr/bin
cd /sources

# Efivar
tar -xvzf efivar*.tar.gz && cd efivar*/
make && make install LIBDIR=/usr/lib 
cd /sources

# Popt
tar -xvzf popt*.tar.gz && cd popt*/
./configure --prefix=/usr --disable-static &&
make && make install
cd /sources

# Efibootmgr
tar -xvzf efibootmgr*.tar.gz && cd efibootmgr*/
tar -xf ../freetype-doc-2.13.3.tar.xz --strip-components=2 -C docs
make EFIDIR=LFS EFI_LOADER=grubx64.efi && make install EFIDIR=LFS
cd /sources

# Freetype2
tar -xvJf freetype*.tar.xz && cd freetype*/
sed -ri "s:.*(AUX_MODULES.*valid):\1:" modules.cfg &&

sed -r "s:.*(#.*SUBPIXEL_RENDERING) .*:\1:" \
    -i include/freetype/config/ftoption.h  &&

./configure --prefix=/usr --enable-freetype-config --disable-static &&
make && make install
cp -v -R docs -T /usr/share/doc/freetype-2.13.3 &&
rm -v /usr/share/doc/freetype-2.13.3/freetype-config.1
cd /sources

# Dosfstools
tar -xvzf dosfstools*.tar.gz && cd dosfstools*/
./configure --prefix=/usr            \
            --enable-compat-symlinks \
            --mandir=/usr/share/man  \
            --docdir=/usr/share/doc/dosfstools-4.2 &&
make && make install

grub-install --target=x86_64-efi --removable
mountpoint /sys/firmware/efi/efivars || mount -v -t efivarfs efivarfs /sys/firmware/efi/efivars

cat >> /etc/fstab << "FSTAB"
efivarfs /sys/firmware/efi/efivars efivarfs defaults 0 0
FSTAB

grub-install --bootloader-id=LFS --recheck
efibootmgr | cut -f 1

cat > /boot/grub/grub.cfg << "CFG"
set default=0
set timeout=5

insmod part_gpt
insmod ext2
set root=(hd0,2)

insmod efi_gop
insmod efi_uga
if loadfont /boot/grub/fonts/unicode.pf2; then
  terminal_output gfxterm
fi

menuentry "GNU/Linux, Linux 6.10.5-lfs-12.2" {
  linux   /boot/vmlinuz-6.10.5-lfs-12.2 root=/dev/sda2 ro
}

menuentry "Firmware Setup" {
  fwsetup
}
CFG

echo "12.2" > /etc/lfs-release

cat > /etc/lsb-release << "LSBREL"
DISTRIB_ID="LazyOS"
DISTRIB_RELEASE="0.0.1"
DISTRIB_CODENAME="Gentuwu"
DISTRIB_DESCRIPTION="LazyOS"
LSBREL

cat > /etc/os-release << "OSREL"
NAME="LazyOS"
VERSION="12.2"
ID=LOS
PRETTY_NAME="LazyOS"
VERSION_CODENAME="Cyborg"
HOME_URL="https://github.com/LazyBev/LazyOS/"
OSREL

# Git
cd /sources && tar -xvJf git*.tar.xz && cd git*/
./configure --prefix=/usr \
            --with-gitconfig=/etc/gitconfig \
            --with-python=python3 &&
make
cd /sources

# Cpio
tar -xvjf cpio*.tar.bz2 && cd cpio*/
./configure --prefix=/usr \
            --enable-mt   \
            --with-rmt=/usr/libexec/rmt &&
make &&
makeinfo --html            -o doc/html      doc/cpio.texi &&
makeinfo --html --no-split -o doc/cpio.html doc/cpio.texi &&
makeinfo --plaintext       -o doc/cpio.txt  doc/cpio.texi
make install &&
install -v -m755 -d /usr/share/doc/cpio-2.15/html &&
install -v -m644    doc/html/* \
                    /usr/share/doc/cpio-2.15/html &&
install -v -m644    doc/cpio.{html,txt} \
                    /usr/share/doc/cpio-2.15
cd /sources

# Pci utils
tar -xvzf pciutils*.tar.gz && cd pciutils*/
sed -r '/INSTALL/{/PCI_IDS|update-pciids /d; s/update-pciids.8//}' \
    -i Makefile
make PREFIX=/usr                \
     SHAREDIR=/usr/share/hwdata \
     SHARED=yes
make PREFIX=/usr                \
     SHAREDIR=/usr/share/hwdata \
     SHARED=yes                 \
     install install-lib        &&
	 
chmod -v 755 /usr/lib/libpci.so
cd /sources

# Hwdata
tar -xvzf hwdata*.tar.gz && cd hwdata*/
./configure --prefix=/usr --disable-blacklist
make install
cd /sources

# DKMS
git clone https://github.com/dell/dkms.git
cd dkms && make install

mkdir -p /usr/src
mkdir -p /var/lib/dkms

export KERNELDIR=/usr/src/linux
dkms autoinstall
cd /sources

# Audio
PULSEAUDIO_VERSION="16.1"
PULSEAUDIO_DIR="/sources/pulseaudio-${PULSEAUDIO_VERSION}"

# Install GLib
wget http://ftp.acc.umu.se/pub/GNOME/sources/glib/2.70/glib-2.70.0.tar.xz
tar -xvJf glib-2.70.0.tar.xz
cd glib-2.70.0
./configure --prefix=/usr
make && make install
cd /sources

# Install libxml2
wget http://xmlsoft.org/sources/libxml2-2.9.10.tar.gz
tar --xvzf libxml2-2.9.10.tar.gz
cd libxml2-2.9.10
./configure --prefix=/usr
make && make install
cd /sources

# Install dbus
wget https://dbus.freedesktop.org/releases/dbus/dbus-1.12.16.tar.xz
tar -xvJf dbus-1.12.16.tar.xz
cd dbus-1.12.16
./configure --prefix=/usr
make && make install
cd /sources

# Install libsndfile
wget http://www.mega-nerd.com/SRC/libsndfile-1.0.31.tar.gz
tar -xvzf libsndfile-1.0.31.tar.gz
cd libsndfile-1.0.31
./configure --prefix=/usr
make && make install
cd /sources

# Install libcap
wget https://github.com/avinoam/libcap/releases/download/v2.56/libcap-2.56.tar.xz
tar -xvJf libcap-2.56.tar.xz
cd libcap-2.56
make && make install
cd /sources

wget https://www.freedesktop.org/software/pulseaudio/releases/pulseaudio-${PULSEAUDIO_VERSION}.tar.xz
tar -xvJf pulseaudio-${PULSEAUDIO_VERSION}.tar.xz
cd pulseaudio-${PULSEAUDIO_VERSION}
./configure --prefix=/usr --sysconfdir=/etc --localstatedir=/var --disable-static --enable-shared
make && make install
cat > /etc/init.d/pulseaudio << 'PA'
#!/bin/sh

set -e

# Define the PulseAudio binary location
PULSEAUDIO="/usr/bin/pulseaudio"
PULSEAUDIO_CONF="/etc/pulse/default.pa"

# Source function library.
. /etc/init.d/functions

start() {
    echo -n "Starting PulseAudio: "
    # Start PulseAudio as a daemon, with a default configuration
    start_daemon $PULSEAUDIO --daemonize=no --config-file=$PULSEAUDIO_CONF
    echo
}

stop() {
    echo -n "Stopping PulseAudio: "
    # Stop PulseAudio gracefully
    killall -TERM pulseaudio
    echo
}

restart() {
    stop
    start
}

status() {
    if pgrep -x pulseaudio > /dev/null; then
        echo "PulseAudio is running"
    else
        echo "PulseAudio is not running"
    fi
}

case "$1" in
  start)
    start
    ;;
  stop)
    stop
    ;;
  restart)
    restart
    ;;
  status)
    status
    ;;
  *)
    echo "Usage: $0 {start|stop|restart|status}"
    exit 1
    ;;
esac
exit 0
PA
chmod +x /etc/init.d/pulseaudio
ln -s /etc/init.d/pulseaudio /etc/rc.d/rc3.d/S99pulseaudio
cd /sources

# PAM
wget https://github.com/linux-pam/linux-pam/releases/download/v1.6.1/Linux-PAM-1.6.1-docs.tar.xz
wget https://github.com/linux-pam/linux-pam/releases/download/v1.6.1/Linux-PAM-1.6.1.tar.xz
tar -xvJf Linux-PAM-1.6.1.tar.xz && cd Linux-PAM-1.6.1/
sed -e /service_DATA/d \
    -i modules/pam_namespace/Makefile.am
autoreconf -fi
tar -xvJf ../Linux-PAM-1.6.1-docs.tar.xz --strip-components=1
./configure --prefix=/usr                        \
            --sbindir=/usr/sbin                  \
            --sysconfdir=/etc                    \
            --libdir=/usr/lib                    \
            --enable-securedir=/usr/lib/security \
            --docdir=/usr/share/doc/Linux-PAM-1.6.1 &&
make
install -v -m755 -d /etc/pam.d &&

cat > /etc/pam.d/other << "PAM"
auth     required       pam_deny.so
account  required       pam_deny.so
password required       pam_deny.so
session  required       pam_deny.so
PAM
rm -fv /etc/pam.d/other
make install && chmod -v 4755 /usr/sbin/unix_chkpwd
install -vdm755 /etc/pam.d &&
cat > /etc/pam.d/system-account << "SYSACC" &&
# Begin /etc/pam.d/system-account

account   required    pam_unix.so

# End /etc/pam.d/system-account
SYSACC

cat > /etc/pam.d/system-auth << "SYSAUTH" &&
# Begin /etc/pam.d/system-auth

auth      required    pam_unix.so

# End /etc/pam.d/system-auth
SYSAUTH

cat > /etc/pam.d/system-session << "SYSSESH" &&
# Begin /etc/pam.d/system-session

session   required    pam_unix.so

# End /etc/pam.d/system-session
SYSSESH

cat > /etc/pam.d/system-password << "SYSPASS"
# Begin /etc/pam.d/system-password

# use yescrypt hash for encryption, use shadow, and try to use any
# previously defined authentication token (chosen password) set by any
# prior module.
password  required    pam_unix.so       yescrypt shadow try_first_pass

# End /etc/pam.d/system-password
SYSPASS
cd /sources

# Sudo
wget https://www.sudo.ws/dist/sudo-1.9.15p5.tar.gz
tar -xvzf sudo-1.9.15p5.tar.gz && cd sudo-1.9.15p5/
./configure --prefix=/usr              \
            --libexecdir=/usr/lib      \
            --with-secure-path         \
            --with-env-editor          \
            --docdir=/usr/share/doc/sudo-1.9.15p5 \
            --with-passprompt="[sudo] password for %p: " &&
make && make install
cat > /etc/sudoers.d/00-sudo << "SUDO"
Defaults secure_path="/usr/sbin:/usr/bin"
%wheel ALL=(ALL) ALL
SUDO

cat > /etc/pam.d/sudo << "PSUDO"
# Begin /etc/pam.d/sudo

# include the default auth settings
auth      include     system-auth

# include the default account settings
account   include     system-account

# Set default environment variables for the service user
session   required    pam_env.so

# include system session defaults
session   include     system-session

# End /etc/pam.d/sudo
PSUDO
chmod 644 /etc/pam.d/sudo
cd /sources

# Xorg
export XORG_PREFIX="/usr"
cat > /etc/profile.d/xorg.sh << XORG
XORG_PREFIX="$XORG_PREFIX"
XORG_CONFIG="--prefix=\$XORG_PREFIX --sysconfdir=/etc --localstatedir=/var --disable-static"
export XORG_PREFIX XORG_CONFIG XORG
chmod 644 /etc/profile.d/xorg.sh
cat > /etc/sudoers.d/xorg << SXORG
Defaults env_keep += XORG_PREFIX
Defaults env_keep += XORG_CONFIG
SXORG
cd /sources

# Util-macros
wget https://www.x.org/pub/individual/util/util-macros-1.20.1.tar.xz
tar -xvJf util-macros-1.20.1.tar.xz && cd util-macros-1.20.1/
./configure $XORG_CONFIG && make install
cd /sources

# Xorgproto
wget https://xorg.freedesktop.org/archive/individual/proto/xorgproto-2024.1.tar.xz
tar -xvJf xorgproto-2024.1.tar.xz && cd xorgproto-2024.1/
mkdir build && cd build
meson setup --prefix=$XORG_PREFIX .. && ninja
ninja install && mv -v $XORG_PREFIX/share/doc/xorgproto{,-2024.1}
cd /sources

# LibXau
wget https://www.x.org/pub/individual/lib/libXau-1.0.11.tar.xz
tar -xvJf libXau-1.0.11.tar.xz && cd libXau-1.0.11/
./configure $XORG_CONFIG &&
make && make install
cd /sources

# libXdmcp
wget https://www.x.org/pub/individual/lib/libXdmcp-1.1.5.tar.xz
tar -xvJf libXdmcp-1.1.5.tar.xz && cd libXdcmp-1.1.5/
./configure $XORG_CONFIG --docdir=/usr/share/doc/libXdmcp-1.1.5 &&
make && make install
cd /sources

# Xcb-proto
wget https://xorg.freedesktop.org/archive/individual/proto/xcb-proto-1.17.0.tar.xz
tar -xvJf xcb-proto-1.17.0.tar.xz && cd xcb-proto-1.17.0/
PYTHON=python3 ./configure $XORG_CONFIG && make install
cd /sources

# Libxcb 
wget https://xorg.freedesktop.org/archive/individual/lib/libxcb-1.17.0.tar.xz
tar -xvJf libxcb-1.17.0.tar.xz && cd libxcb-1.17.0/
./configure $XORG_CONFIG      \
            --without-doxygen \
            --docdir='${datadir}'/doc/libxcb-1.17.0 &&
LC_ALL=en_US.UTF-8 make
make install
cd /sources

# Fontconfig
wget https://www.freedesktop.org/software/fontconfig/release/fontconfig-2.15.0.tar.xz
tar -xvJf fontconfig-2.15.0.tar.xz && cd fontconfig-2.15.0/
./configure --prefix=/usr        \
            --sysconfdir=/etc    \
            --localstatedir=/var \
            --disable-docs       \
            --docdir=/usr/share/doc/fontconfig-2.15.0 &&
make && make install
install -v -dm755 \
        /usr/share/{man/man{1,3,5},doc/fontconfig-2.15.0/fontconfig-devel} &&
install -v -m644 fc-*/*.1         /usr/share/man/man1 &&
install -v -m644 doc/*.3          /usr/share/man/man3 &&
install -v -m644 doc/fonts-conf.5 /usr/share/man/man5 &&
install -v -m644 doc/fontconfig-devel/* \
                                  /usr/share/doc/fontconfig-2.15.0/fontconfig-devel &&
install -v -m644 doc/*.{pdf,sgml,txt,html} \
                                  /usr/share/doc/fontconfig-2.15.0
cd /sources

# Xorg libs
cat > lib-7.md5 << "MD5"
12344cd74a1eb25436ca6e6a2cf93097  xtrans-1.5.0.tar.xz
5b8fa54e0ef94136b56f887a5e6cf6c9  libX11-1.8.10.tar.xz
e59476db179e48c1fb4487c12d0105d1  libXext-1.3.6.tar.xz
c5cc0942ed39c49b8fcd47a427bd4305  libFS-1.0.10.tar.xz
b444a0e4c2163d1bbc7b046c3653eb8d  libICE-1.1.1.tar.xz
ffa434ed96ccae45533b3d653300730e  libSM-1.2.4.tar.xz
e613751d38e13aa0d0fd8e0149cec057  libXScrnSaver-1.2.4.tar.xz
4ea21d3b5a36d93a2177d9abed2e54d4  libXt-1.3.0.tar.xz
85edefb7deaad4590a03fccba517669f  libXmu-1.2.1.tar.xz
05b5667aadd476d77e9b5ba1a1de213e  libXpm-3.5.17.tar.xz
2a9793533224f92ddad256492265dd82  libXaw-1.0.16.tar.xz
65b9ba1e9ff3d16c4fa72915d4bb585a  libXfixes-6.0.1.tar.xz
af0a5f0abb5b55f8411cd738cf0e5259  libXcomposite-0.4.6.tar.xz
ebf7fb3241ec03e8a3b2af72f03b4631  libXrender-0.9.11.tar.xz
bf3a43ad8cb91a258b48f19c83af8790  libXcursor-1.2.2.tar.xz
ca55d29fa0a8b5c4a89f609a7952ebf8  libXdamage-1.1.6.tar.xz
8816cc44d06ebe42e85950b368185826  libfontenc-1.1.8.tar.xz
66e03e3405d923dfaf319d6f2b47e3da  libXfont2-2.0.7.tar.xz
cea0a3304e47a841c90fbeeeb55329ee  libXft-2.3.8.tar.xz
89ac74ad6829c08d5c8ae8f48d363b06  libXi-1.8.1.tar.xz
228c877558c265d2f63c56a03f7d3f21  libXinerama-1.1.5.tar.xz
24e0b72abe16efce9bf10579beaffc27  libXrandr-1.5.4.tar.xz
66c9e9e01b0b53052bb1d02ebf8d7040  libXres-1.2.2.tar.xz
b62dc44d8e63a67bb10230d54c44dcb7  libXtst-1.2.5.tar.xz
70bfdd14ca1a563c218794413f0c1f42  libXv-1.0.12.tar.xz
a90a5f01102dc445c7decbbd9ef77608  libXvMC-1.0.14.tar.xz
74d1acf93b83abeb0954824da0ec400b  libXxf86dga-1.1.6.tar.xz
5b913dac587f2de17a02e17f9a44a75f  libXxf86vm-1.1.5.tar.xz
57c7efbeceedefde006123a77a7bc825  libpciaccess-0.18.1.tar.xz
229708c15c9937b6e5131d0413474139  libxkbfile-1.1.3.tar.xz
faa74f7483074ce7d4349e6bdc237497  libxshmfence-1.3.2.tar.xz
bdd3ec17c6181fd7b26f6775886c730d  libXpresent-1.0.1.tar.xz
MD5
mkdir lib &&
cd lib &&
grep -v '^#' ../lib-7.md5 | awk '{print $2}' | wget -i- -c \
    -B https://www.x.org/pub/individual/lib/ &&
md5sum -c ../lib-7.md5
as_root()
{
  if   [ $EUID = 0 ];        then $*
  elif [ -x /usr/bin/sudo ]; then sudo $*
  else                            su -c \\"$*\\"
  fi
}
export -f as_root
bash -e && for package in $(grep -v '^#' ../lib-7.md5 | awk '{print $2}')
do
    packagedir=${package%.tar.?z*}
    echo "Building $packagedir"

    tar -xvf $package
    pushd $packagedir
    docdir="--docdir=$XORG_PREFIX/share/doc/$packagedir"
  
    case $packagedir in
        libXfont2-[0-9]* )
            ./configure $XORG_CONFIG $docdir --disable-devel-docs
            ;;
        libXt-[0-9]* )
            ./configure $XORG_CONFIG $docdir --with-appdefaultdir=/etc/X11/app-defaults
            ;;

        libXpm-[0-9]* )
            ./configure $XORG_CONFIG $docdir --disable-open-zfile
            ;;
  
        libpciaccess* )
            mkdir build
            cd build
            meson setup --prefix=$XORG_PREFIX --buildtype=release ..
            ninja
            as_root ninja install
            popd     # $packagedir
            continue # for loop
            ;;
	* )
           ./configure $XORG_CONFIG $docdir
           ;;
    esac

    make
    #make check 2>&1 | tee ../$packagedir-make_check.log
    as_root make install
    popd
    rm -rf $packagedir
    as_root /sbin/ldconfig
done
exit
cd /sources

# Libxcvt
wget https://www.x.org/pub/individual/lib/libxcvt-0.1.2.tar.xz
tar -xvJf libxcvt-0.1.2.tar.xz && cd libxcvt-0.1.2
mkdir build && cd build
meson setup --prefix=$XORG_PREFIX --buildtype=release .. &&
ninja && ninja install
cd /sources

# Xcb-util
wget https://xcb.freedesktop.org/dist/xcb-util-0.4.1.tar.xz
tar -xvJf xcb-util-0.4.1.tar.xz && cd xcb-util-0.4.1/
./configure $XORG_CONFIG &&
make && make install
cd /sources

# Xcb-util-image
wget https://xcb.freedesktop.org/dist/xcb-util-image-0.4.1.tar.xz
tar -xvJf xcb-util-image-0.4.1.tar.xz && cd xcb-util-image-0.4.1
./configure $XORG_CONFIG &&
make && make install
cd /sources

# Xcb-util-keysyms
wget https://xcb.freedesktop.org/dist/xcb-util-keysyms-0.4.1.tar.xz
tar -xvJf xcb-util-keysyms-0.4.1.tar.xz && cd xcb-util-keysyms-0.4.1/
./configure $XORG_CONFIG &&
make && make install
cd /sources

# Xcb-util-renderutil
wget https://xcb.freedesktop.org/dist/xcb-util-renderutil-0.3.10.tar.xz
tar -xvJf xcb-util-renderutil-0.3.10.tar.xz && cd xcb-util-renderutil-0.3.10/
./configure $XORG_CONFIG &&
make && make install
cd /sources

# Xcb-util-wm
wget https://xcb.freedesktop.org/dist/xcb-util-wm-0.4.2.tar.xz
tar -xvJf xcb-util-wm-0.4.2.tar.xz && cd xcb-util-wm-0.4.2/
./configure $XORG_CONFIG &&
make && make install
cd /sources

# Xcb-util-cursor
wget https://xcb.freedesktop.org/dist/xcb-util-cursor-0.1.4.tar.xz
tar -xvJf xcb-util-cursor-0.1.4.tar.xz && cd xcb-util-cursor-0.1.4
./configure $XORG_CONFIG &&
make && make install
cd /sources

# Mesa
wget https://dri.freedesktop.org/libdrm/libdrm-2.4.122.tar.xz
tar -xvJf libdrm-2.4.122.tar.xz && cd libdrm-2.4.122/
mkdir build && cd build
meson setup --prefix=$XORG_PREFIX \
            --buildtype=release   \
            -D udev=true          \
            -D valgrind=disabled  \
            ..                    &&
ninja && ninja install
cd /sources
wget https://files.pythonhosted.org/packages/source/M/Mako/Mako-1.3.5.tar.gz
tar -xvzf Mako-1.3.5.tar.gz && cd Mako-1.3.5
pip3 wheel -w dist --no-build-isolation --no-deps --no-cache-dir $PWD
pip3 install --no-index --find-links=dist --no-cache-dir --no-user Mako
cd /sources
wget https://mesa.freedesktop.org/archive/mesa-24.1.5.tar.xz
wget https://www.linuxfromscratch.org/patches/blfs/12.2/mesa-add_xdemos-2.patch
tar -xvJf mesa-24.1.5.tar.xz && cd mesa-24.1.5
patch -Np1 -i ../mesa-add_xdemos-2.patch
mkdir build && cd build
meson setup ..                 \
      --prefix=$XORG_PREFIX    \
      --buildtype=release      \
      -D platforms=x11,wayland \
      -D gallium-drivers=auto  \
      -D vulkan-drivers=auto   \
      -D valgrind=disabled     \
      -D libunwind=disabled    &&

ninja && ninja install
cp -rv ../docs -T /usr/share/doc/mesa-24.1.5
cd /sources

# Xbitmaps
wget https://www.x.org/pub/individual/data/xbitmaps-1.1.3.tar.xz
./configure $XORG_CONFIG && make install
cd /sources

# Xorg apps
wget https://downloads.sourceforge.net/libpng/libpng-1.6.43.tar.xz
wget https://downloads.sourceforge.net/sourceforge/libpng-apng/libpng-1.6.43-apng.patch.gz
tar -xvJf libpng-1.6.43.tar.xz && cd libpng-1.6.43
gzip -cd ../libpng-1.6.43-apng.patch.gz | patch -p1
./configure --prefix=/usr --disable-static
make && make install &&
mkdir -v /usr/share/doc/libpng-1.6.43 &&
cp -v README libpng-manual.txt /usr/share/doc/libpng-1.6.43
cd /sources

cat > app-7.md5 << "XAPPS"
30f898d71a7d8e817302970f1976198c  iceauth-1.0.10.tar.xz
7dcf5f702781bdd4aaff02e963a56270  mkfontscale-1.2.3.tar.xz
05423bb42a006a6eb2c36ba10393de23  sessreg-1.1.3.tar.xz
1d61c9f4a3d1486eff575bf233e5776c  setxkbmap-1.3.4.tar.xz
9f7a4305f0e79d5a46c3c7d02df9437d  smproxy-1.0.7.tar.xz
e96b56756990c56c24d2d02c2964456b  x11perf-1.6.1.tar.bz2
595c941d9aff6f6d6e038c4e42dcff58  xauth-1.1.3.tar.xz
82a90e2feaeab5c5e7610420930cc0f4  xcmsdb-1.0.6.tar.xz
89e81a1c31e4a1fbd0e431425cd733d7  xcursorgen-1.0.8.tar.xz
933e6d65f96c890f8e96a9f21094f0de  xdpyinfo-1.3.4.tar.xz
34aff1f93fa54d6a64cbe4fee079e077  xdriinfo-1.0.7.tar.xz
f29d1544f8dd126a1b85e2f7f728672d  xev-1.2.6.tar.xz
41afaa5a68cdd0de7e7ece4805a37f11  xgamma-1.0.7.tar.xz
48ac13856838d34f2e7fca8cdc1f1699  xhost-1.0.9.tar.xz
8e4d14823b7cbefe1581c398c6ab0035  xinput-1.6.4.tar.xz
83d711948de9ccac550d2f4af50e94c3  xkbcomp-1.4.7.tar.xz
05ce1abd8533a400572784b1186a44d0  xkbevd-1.1.5.tar.xz
07483ddfe1d83c197df792650583ff20  xkbutils-1.0.6.tar.xz
f62b99839249ce9a7a8bb71a5bab6f9d  xkill-1.0.6.tar.xz
da5b7a39702841281e1d86b7349a03ba  xlsatoms-1.1.4.tar.xz
ab4b3c47e848ba8c3e47c021230ab23a  xlsclients-1.1.5.tar.xz
ba2dd3db3361e374fefe2b1c797c46eb  xmessage-1.0.7.tar.xz
0d66e07595ea083871048c4b805d8b13  xmodmap-1.0.11.tar.xz
ab6c9d17eb1940afcfb80a72319270ae  xpr-1.2.0.tar.xz
d050642a667b518cb3429273a59fa36d  xprop-1.2.7.tar.xz
f822a8d5f233e609d27cc22d42a177cb  xrandr-1.5.2.tar.xzx
c8629d5a0bc878d10ac49e1b290bf453  xrdb-1.2.2.tar.xz
55003733ef417db8fafce588ca74d584  xrefresh-1.1.0.tar.xz
18ff5cdff59015722431d568a5c0bad2  xset-1.2.5.tar.xz
fa9a24fe5b1725c52a4566a62dd0a50d  xsetroot-1.1.3.tar.xz
d698862e9cad153c5fefca6eee964685  xvinfo-1.1.5.tar.xz
b0081fb92ae56510958024242ed1bc23  xwd-1.0.9.tar.xz
c91201bc1eb5e7b38933be8d0f7f16a8  xwininfo-1.1.6.tar.xz
5ff5dc120e8e927dc3c331c7fee33fc3  xwud-1.0.6.tar.xz
XAPPS
mkdir app &&
cd app &&
grep -v '^#' ../app-7.md5 | awk '{print $2}' | wget -i- -c \
    -B https://www.x.org/pub/individual/app/ &&
md5sum -c ../app-7.md5
as_root()
{
  if   [ $EUID = 0 ];        then $*
  elif [ -x /usr/bin/sudo ]; then sudo $*
  else                            su -c \\"$*\\"
  fi
}
export -f as_root
bash -e
for package in $(grep -v '^#' ../app-7.md5 | awk '{print $2}')
do
    packagedir=${package%.tar.?z*}
    tar -xf $package
    pushd $packagedir
       ./configure $XORG_CONFIG
       make
       as_root make install
    popd
    rm -rf $packagedir
done
exit; as_root rm -f $XORG_PREFIX/bin/xkeystone
cd /sources

# Luit
wget https://invisible-mirror.net/archives/luit/luit-20240102.tgz
tar -xvzf luit-20240102.tgz && cd luit-20240102
./configure $XORG_CONFIG &&
make && make install
cd /sources

# Xcursor-themes
wget https://www.x.org/pub/individual/data/xcursor-themes-1.0.7.tar.xz
tar -xvJf xcursor-themes-1.0.7.tar.xz && cd xcursor-themes-1.0.7
./configure --prefix=/usr &&
make && make install
cd /sources

cat > font-7.md5 << "XFONTS"
a6541d12ceba004c0c1e3df900324642  font-util-1.4.1.tar.xz
a56b1a7f2c14173f71f010225fa131f1  encodings-1.1.0.tar.xz
79f4c023e27d1db1dfd90d041ce89835  font-alias-1.0.5.tar.xz
546d17feab30d4e3abcf332b454f58ed  font-adobe-utopia-type1-1.0.5.tar.xz
063bfa1456c8a68208bf96a33f472bb1  font-bh-ttf-1.0.4.tar.xz
51a17c981275439b85e15430a3d711ee  font-bh-type1-1.0.4.tar.xz
00f64a84b6c9886040241e081347a853  font-ibm-type1-1.0.4.tar.xz
fe972eaf13176fa9aa7e74a12ecc801a  font-misc-ethiopic-1.0.5.tar.xz
3b47fed2c032af3a32aad9acc1d25150  font-xfree86-type1-1.0.5.tar.xz
XFONTS
mkdir font && cd font
grep -v '^#' ../font-7.md5 | awk '{print $2}' | wget -i- -c \
    -B https://www.x.org/pub/individual/font/ &&
md5sum -c ../font-7.md5
as_root()
{
  if   [ $EUID = 0 ];        then $*
  elif [ -x /usr/bin/sudo ]; then sudo $*
  else                            su -c \\"$*\\"
  fi
}
export -f as_root
bash -e
for package in $(grep -v '^#' ../font-7.md5 | awk '{print $2}')
do
    packagedir=${package%.tar.?z*}
    tar -xf $package
    pushd $packagedir
        ./configure $XORG_CONFIG
        make
        as_root make install
    popd
    as_root rm -rf $packagedir
done
exit 
install -v -d -m755 /usr/share/fonts 
ln -svfn $XORG_PREFIX/share/fonts/X11/OTF /usr/share/fonts/X11-OTF &&
ln -svfn $XORG_PREFIX/share/fonts/X11/TTF /usr/share/fonts/X11-TTF


# Bedrocking
read -p "Do you want to install bedrock linux? [y/N]: " bedrock_choice
if [[ "$bedrock_choice" == "y" ]]; then
    wget https://github.com/libfuse/libfuse/releases/download/fuse-3.16.2/fuse-3.16.2.tar.gz
    tar -xvJf fuse-3.16.2.tar.xz && cd fuse*/
    mkdir build && cd build
    meson setup
    cd /sources

    wget https://gnupg.org/ftp/gcrypt/gnupg/gnupg-2.4.6.tar.bz2
    tar -xvJf gnupg-2.4.6.tar.bz2 && cd gnupg-2.4.6
    ./configure --prefix=/usr --sysconfdir=/etc
    make && make install
    gpg --full-generate-key
    cd /sources

    wget https://github.com/bedrocklinux/bedrocklinux-userland/releases/download/0.7.30/bedrock-linux-0.7.30-x86_64.sh --directory-prefix=/sources
    sh ./bedrock-linux* --hijack 
	
    # Check if Bedrock's `brl` is available
    if ! command -v brl &>/dev/null; then
	echo "Bedrock's brl command not found. Please ensure Bedrock is installed." >&2
	exit 1
    fi
	
    # Check if an Arch stratum exists
    if ! brl list | grep -q arch; then
	echo "No Arch Linux stratum found. Adding Arch Linux stratum..."
	brl fetch arch || { echo "Failed to add Arch Linux stratum."; exit 1; }
    fi
	
    # Ensure pacman is available
    if ! command -v pacman &>/dev/null; then
	echo "Pacman is not available. Ensure your Arch Linux stratum is working properly." >&2
	exit 1
    fi
	
    # Update package database
    echo "Updating pacman package database..."
    pacman -Sy || { echo "Failed to update pacman package database."; exit 1; }

    # Determine CPU type and install appropriate microcode
    CPU_VENDOR=$(grep -m 1 "vendor_id" /proc/cpuinfo | awk '{print $3}')
    case $CPU_VENDOR in
        GenuineIntel)
	    echo "Intel CPU detected. Installing intel-ucode..."
	    pacman -S --noconfirm intel-ucode || { echo "Failed to install intel-ucode."; exit 1; }
	    MICROCODE_PATH="/boot/intel-ucode.img"
	    ;;
	AuthenticAMD)
	    echo "AMD CPU detected. Installing amd-ucode..."
	    pacman -S --noconfirm amd-ucode || { echo "Failed to install amd-ucode."; exit 1; }
	    MICROCODE_PATH="/boot/amd-ucode.img"
	    ;;
	*)
	    echo "Unknown CPU vendor: $CPU_VENDOR. Exiting." >&2
	    exit 1
	    ;;
	esac
else
    echo "Skipping bedrock installation..."
fi

# Update GRUB configuration
if [[ -f /etc/default/grub ]]; then
    echo "Updating GRUB configuration..."
    GRUB_CMDLINE=$(grep "^GRUB_CMDLINE_LINUX" /etc/default/grub)
    if ! echo "$GRUB_CMDLINE" | grep -q "$MICROCODE_PATH"; then
        sed -i "/^GRUB_CMDLINE_LINUX/s|\"$| ${MICROCODE_PATH}\"|" /etc/default/grub
    fi
    grub-mkconfig -o /boot/grub/grub.cfg || { echo "Failed to update GRUB configuration."; exit 1; }
else
    echo "/etc/default/grub not found. Please configure your bootloader manually to include $MICROCODE_PATH."
    exit 1
fi



EOF

umount -v $LFS/dev/pts
mountpoint -q $LFS/dev/shm && umount -v $LFS/dev/shm
umount -v $LFS/dev
umount -v $LFS/run
umount -v $LFS/proc
umount -v $LFS/sys
umount -v $LFS/home
umount -v $LFS

reboot
