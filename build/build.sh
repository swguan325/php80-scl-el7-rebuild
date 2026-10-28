#!/bin/bash
# Rebuild Remi's php80-php 8.0.30-21 SCL packages for EL7 (CentOS/RHEL 7).
# Runs INSIDE a centos:7 container. See run.sh for the wrapper.
set -euo pipefail

SRPM_URL="https://rpms.remirepo.net/SRPMS/php80-php-8.0.30-21.remi.src.rpm"
SRPM_SHA256="08579b2c1ee97d3f431a0bb088102e554f8346fb6852d458cbcb7335bb2b1ea8"
# CentOS 7 vault mirror. NOTE: vault.centos.org itself now returns HTTP 403 for
# *-primary.sqlite.bz2 (repomd.xml still lists them), which breaks yum entirely.
VAULT="http://archive.kernel.org/centos-vault/7.9.2009"

say() { printf '\n=== %s ===\n' "$1"; }

say "Pointing base repos at a working vault mirror"
cat > /etc/yum.repos.d/CentOS-Base.repo <<REPO
[base]
name=CentOS-7 - Base
baseurl=$VAULT/os/x86_64/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
[updates]
name=CentOS-7 - Updates
baseurl=$VAULT/updates/x86_64/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
[extras]
name=CentOS-7 - Extras
baseurl=$VAULT/extras/x86_64/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-7
REPO
rm -f /etc/yum.repos.d/CentOS-{CR,Debuginfo,Media,Sources,Vault,fasttrack,x86_64-kernel}.repo

say "EPEL 7 + SCLo (devtoolset) + Remi EL7"
yum -y install epel-release
yum -y install centos-release-scl-rh centos-release-scl || true
# The stock CentOS-SCLo-scl.repo ships with its baseurl commented out and no
# mirrorlist, so it must be written by hand.
cat > /etc/yum.repos.d/CentOS-SCLo-scl-rh.repo <<REPO
[centos-sclo-rh]
name=CentOS-7 - SCLo rh
baseurl=$VAULT/sclo/x86_64/rh/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-SCLo
REPO
cat > /etc/yum.repos.d/CentOS-SCLo-scl.repo <<REPO
[centos-sclo-sclo]
name=CentOS-7 - SCLo sclo
baseurl=$VAULT/sclo/x86_64/sclo/
gpgcheck=1
gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-CentOS-SIG-SCLo
REPO
yum -y install https://rpms.remirepo.net/enterprise/remi-release-7.rpm
yum -y install yum-utils rpm-build rpmdevtools scl-utils-build cpio

say "php80-build supplies the SCL macros (%_scl_prefix = /opt/remi)"
# Without it the build lands in /opt/rh/php80 instead of Remi's /opt/remi/php80.
yum -y install php80-build

say "Fetching and verifying Remi's source RPM"
cd /tmp
curl -fsSLO "$SRPM_URL"
echo "$SRPM_SHA256  $(basename "$SRPM_URL")" | sha256sum -c -

say "Unpacking (rpm -i cannot install this SRPM: EL7's rpm 4.11 lacks rich deps)"
rpmdev-setuptree
mkdir -p /tmp/srpm && cd /tmp/srpm
rpm2cpio "/tmp/$(basename "$SRPM_URL")" | cpio -idm --quiet
cp -f /tmp/srpm/* ~/rpmbuild/SOURCES/
cp -f /tmp/srpm/php.spec ~/rpmbuild/SPECS/php.spec

say "Applying the EL7 adjustments"
patch -p1 -d ~/rpmbuild/SPECS < "${PATCH_FILE:-/work/patches/php.spec.el7.patch}"

say "Installing build dependencies"
yum-builddep -y --enablerepo=remi \
  --define "scl php80" --define "dtsprefix devtoolset-11-" \
  ~/rpmbuild/SPECS/php.spec

say "Building"
cd ~/rpmbuild/SPECS
scl enable devtoolset-11 -- rpmbuild -ba \
  --define "scl php80" \
  --define "dtsprefix devtoolset-11-" \
  --without tests \
  php.spec

say "Done"
ls -1 ~/rpmbuild/RPMS/x86_64/*.rpm
