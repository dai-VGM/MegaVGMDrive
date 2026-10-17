-----BEGIN PGP SIGNED MESSAGE-----
Hash: SHA512

Format: 3.0 (native)
Source: cross-toolchain-base
Binary: linux-libc-dev-amd64-cross, linux-libc-dev-arm64-cross, linux-libc-dev-armhf-cross, linux-libc-dev-i386-cross, linux-libc-dev-powerpc-cross, linux-libc-dev-ppc64el-cross, linux-libc-dev-riscv64-cross, linux-libc-dev-s390x-cross, libc6-amd64-cross, libc6-dbg-amd64-cross, libc6-dev-amd64-cross, libc6-arm64-cross, libc6-dbg-arm64-cross, libc6-dev-arm64-cross, libc6-armhf-cross, libc6-dbg-armhf-cross, libc6-dev-armhf-cross, libc6-i386-cross, libc6-dbg-i386-cross, libc6-dev-i386-cross, libc6-powerpc-cross, libc6-dbg-powerpc-cross, libc6-dev-powerpc-cross, libc6-ppc64el-cross, libc6-dbg-ppc64el-cross, libc6-dev-ppc64el-cross, libc6-riscv64-cross, libc6-dbg-riscv64-cross, libc6-dev-riscv64-cross, libc6-s390x-cross, libc6-dbg-s390x-cross, libc6-dev-s390x-cross, libc6-ppc64-powerpc-cross, libc6-dbg-ppc64-powerpc-cross, libc6-dev-ppc64-powerpc-cross, libc6-i386-amd64-cross, libc6-dbg-i386-amd64-cross, libc6-dev-i386-amd64-cross, libc6-x32-amd64-cross,
 libc6-dbg-x32-amd64-cross, libc6-dev-x32-amd64-cross, libc6-amd64-i386-cross, libc6-dbg-amd64-i386-cross, libc6-dev-amd64-i386-cross, libc6-x32-i386-cross, libc6-dbg-x32-i386-cross,
 libc6-dev-x32-i386-cross
Architecture: all
Version: 80ubuntu3
Maintainer: Cross Toolchain Base Team <cross-toolchain-base-devs@lists.launchpad.net>
Uploaders: Matthias Klose <doko@debian.org>, Dimitri John Ledkov <xnox@debian.org>
Standards-Version: 4.7.3
Vcs-Browser: https://salsa.debian.org/toolchain-team/cross-toolchain-base
Vcs-Git: https://salsa.debian.org/toolchain-team/cross-toolchain-base.git
Testsuite: autopkgtest
Testsuite-Triggers: @builddeps@
Build-Depends: binutils-multiarch, dpkg (>= 1.21.17), rdfind, symlinks, lsb-release, binutils-source (>= 2.46-3~), glibc-source (>= 2.43-2ubuntu2~), gcc-15-source (>= 15.2.0-16~), g++-15 (>= 15.2.0-16~), linux-source-7.0.0 (>= 7.0.0), linux-libc-dev (>= 7.0.0), autoconf (>= 2.69), autoconf2.69, automake, bison (>= 1:2.3), chrpath, debhelper-compat (= 13), dpkg-dev (>= 1.15.3.1), fakeroot, file, flex, dwz, debugedit (>= 4.16), gawk, gettext, gperf (>= 3.0.1), kernel-wedge (>= 2.24), libisl-dev, libmpc-dev, libelf-dev, libmpfr-dev (>= 2.3.0), rsync, xmlto, libtool, lzma, m4, make (>= 3.81), kmod | module-init-tools, patchutils, procps, quilt, coreutils (>= 2.26) | realpath (>= 1.9.12), sed (>= 4.0.5-4), sharutils, tar (>= 1.22), xz-utils, asciidoc, texinfo, cpio, python3, bc, time, libconfig-auto-perl, libfile-temp-perl, libfile-homedir-perl, liblocale-gettext-perl, libunwind-dev [amd64 i386 x32], libjansson-dev, pkg-config
Build-Conflicts: binutils-aarch64-linux-gnu [!arm64], binutils-arm-linux-gnueabihf [!armhf], binutils-i686-linux-gnu [!i386], binutils-powerpc-linux-gnu [!powerpc], binutils-powerpc64le-linux-gnu [!ppc64el], binutils-riscv64-linux-gnu [!riscv64], binutils-s390x-linux-gnu [!s390x], binutils-x86-64-linux-gnu [!amd64], dpkg-cross, libc6-amd64 [i386 x32], libc6-amd64-cross, libc6-arm64-cross, libc6-armhf-cross, libc6-i386 [amd64 x32], libc6-i386-cross, libc6-powerpc-cross, libc6-ppc64el-cross, libc6-riscv64-cross, libc6-s390x-cross, libc6-x32 [amd64 i386], libdebian-dpkgcross-perl, linux-libc-dev-amd64-cross, linux-libc-dev-arm64-cross, linux-libc-dev-armhf-cross, linux-libc-dev-i386-cross, linux-libc-dev-powerpc-cross, linux-libc-dev-ppc64el-cross, linux-libc-dev-riscv64-cross, linux-libc-dev-s390x-cross
Package-List:
 libc6-amd64-cross deb libs optional arch=all
 libc6-amd64-i386-cross deb libs optional arch=all
 libc6-arm64-cross deb libs optional arch=all
 libc6-armhf-cross deb libs optional arch=all
 libc6-dbg-amd64-cross deb debug optional arch=all
 libc6-dbg-amd64-i386-cross deb debug optional arch=all
 libc6-dbg-arm64-cross deb debug optional arch=all
 libc6-dbg-armhf-cross deb debug optional arch=all
 libc6-dbg-i386-amd64-cross deb debug optional arch=all
 libc6-dbg-i386-cross deb debug optional arch=all
 libc6-dbg-powerpc-cross deb debug optional arch=all
 libc6-dbg-ppc64-powerpc-cross deb debug optional arch=all
 libc6-dbg-ppc64el-cross deb debug optional arch=all
 libc6-dbg-riscv64-cross deb debug optional arch=all
 libc6-dbg-s390x-cross deb debug optional arch=all
 libc6-dbg-x32-amd64-cross deb debug optional arch=all
 libc6-dbg-x32-i386-cross deb debug optional arch=all
 libc6-dev-amd64-cross deb libdevel optional arch=all
 libc6-dev-amd64-i386-cross deb libdevel optional arch=all
 libc6-dev-arm64-cross deb libdevel optional arch=all
 libc6-dev-armhf-cross deb libdevel optional arch=all
 libc6-dev-i386-amd64-cross deb libdevel optional arch=all
 libc6-dev-i386-cross deb libdevel optional arch=all
 libc6-dev-powerpc-cross deb libdevel optional arch=all
 libc6-dev-ppc64-powerpc-cross deb libdevel optional arch=all
 libc6-dev-ppc64el-cross deb libdevel optional arch=all
 libc6-dev-riscv64-cross deb libdevel optional arch=all
 libc6-dev-s390x-cross deb libdevel optional arch=all
 libc6-dev-x32-amd64-cross deb libdevel optional arch=all
 libc6-dev-x32-i386-cross deb libdevel optional arch=all
 libc6-i386-amd64-cross deb libs optional arch=all
 libc6-i386-cross deb libs optional arch=all
 libc6-powerpc-cross deb libs optional arch=all
 libc6-ppc64-powerpc-cross deb libs optional arch=all
 libc6-ppc64el-cross deb libs optional arch=all
 libc6-riscv64-cross deb libs optional arch=all
 libc6-s390x-cross deb libs optional arch=all
 libc6-x32-amd64-cross deb libs optional arch=all
 libc6-x32-i386-cross deb libs optional arch=all
 linux-libc-dev-amd64-cross deb devel optional arch=all
 linux-libc-dev-arm64-cross deb devel optional arch=all
 linux-libc-dev-armhf-cross deb devel optional arch=all
 linux-libc-dev-i386-cross deb devel optional arch=all
 linux-libc-dev-powerpc-cross deb devel optional arch=all
 linux-libc-dev-ppc64el-cross deb devel optional arch=all
 linux-libc-dev-riscv64-cross deb devel optional arch=all
 linux-libc-dev-s390x-cross deb devel optional arch=all
Checksums-Sha1:
 d69b9e8a89e959e0ca7816bb0866d7ffb4c86499 48316 cross-toolchain-base_80ubuntu3.tar.xz
Checksums-Sha256:
 61baf2f68dd26cfbf3230dc493f128faa989c2139ada0490aa3ed9e2e0731d53 48316 cross-toolchain-base_80ubuntu3.tar.xz
Files:
 18e8a594290859042940c482aeb4288a 48316 cross-toolchain-base_80ubuntu3.tar.xz

-----BEGIN PGP SIGNATURE-----

iQIzBAEBCgAdFiEEVovyKmYzfL/Jprm3LIPbyOm9DjcFAmnZ63sACgkQLIPbyOm9
Djf+Ww/+Ljn2iWQmbMAQk0Dygop+gS5olUAR0DQlQ3WxY3+YME24tNqm5oSy2e3Y
oPlk1N/USFvlT80EZpeTdgOo5Um0yVkRyOrtQYCrUydze2ZiGqCw6kv7A0Msz1FD
fgrz9rbT/Y3IUXLc2DR9DpJtK0ksNCOFEtyJNpykPjXdl0SZpZ/p6SEdKZcHw00M
jUFmqH7eyP7exhp4XhjarPQs6KEO+ODcwYyrK03FQKuuR5lEBFkG+axgti+5/Z1N
K1rXtHvFEAQVWgMRxZDFsASOjRFMdV0Gjq+GqIp0VBJNYaz9g2vtzpi+ZRxgxAeE
S/zJ4onHcDGY/LrM6P1br+Fk3/NUwflQcFo0g/kav5X1zTT3mfQYXcPSz7XwccYM
pQKtGuV93XS1Ujg8pMlY4me5DrzgBjUcJe4KO3x+Fe2WB1wkvyBuUo6ZNR4vadPf
SCtKS0IJ2Vwi/SMBtmjPyOrpkC3vUSfy3jAfrmJnLlgoJ1SrbEdeKGk+iR5jlroY
AA7Qw+PDfBdC86bDeOlLkW5BFrooXobk/KfOgzRqfw1NfVmbKytMnIMyEIsNC2O1
eyhCOSelEONapnStkIxMYXEq8z1L8on10zK5PybYI0bVnfv4EXTzAlOnjJ+xbNUE
fR8bdtCp5DCZgaKWozL2fnAjL4l3t0UU69sbIIHEr97Uq5hLsw4=
=Fvp2
-----END PGP SIGNATURE-----
