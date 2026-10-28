# php80-scl-el7-rebuild

Unofficial rebuild of Remi Collet's **`php80-php` 8.0.30-21** SCL packages for
**CentOS/RHEL 7**, which Remi stopped building at `8.0.30-6` in June 2024.

Nothing here is new code. It is Remi's own source RPM, rebuilt for EL7 with
three mechanical packaging adjustments. The patches, the sources and the
packaging are all his.

## Why

Remi's EL7 repository for PHP 8.0 was frozen at `8.0.30-6` (2024-06-14), while
the `php80-php` source RPM kept receiving backported security fixes. Rebuilding
`-21` for EL7 closes that gap.

Between `-6` and `-21`, Remi's changelog records **44 CVEs**, among them:

| CVE | |
|---|---|
| CVE-2026-109618 / CVE-2026-109619 | "PHP2Shell" — unauthenticated RCE, CVSS 9.2, CISA KEV |
| CVE-2024-4577 | PHP-CGI argument injection (also in CISA KEV) |
| CVE-2026-91767 | heap buffer overflow in `php_openssl_matches_wildcard_name()` |
| CVE-2026-93682 | OOB read in the HTTP stream wrapper on empty `Location` |
| CVE-2025-1218 | packet overreads in the mysqlnd wire protocol |
| CVE-2026-6103 | integer overflow in `phar_tar_number()` |

The full list is in `docs/cves.txt`.

**This is a stopgap.** PHP 8.0 reached end of life upstream in November 2023 and
CentOS 7 in June 2024. The real fix is to move to a supported platform.

## What is *not* here

No binaries are published in this repository. Build them yourself — that is the
point. You should not install a stranger's RPM into your PHP runtime, and that
includes mine.

## Provenance

| | |
|---|---|
| Source | `https://rpms.remirepo.net/SRPMS/php80-php-8.0.30-21.remi.src.rpm` |
| SHA-256 | `08579b2c1ee97d3f431a0bb088102e554f8346fb6852d458cbcb7335bb2b1ea8` |
| Upstream signing key | Remi Collet, `2E37 5FE2 4EDF F0F2 E0D8 E165 ED5B 58C5 BEFA 00E2` |
| Spec in the SRPM | `php.spec`, `Name: %{?scl_prefix}php` |
| Licenses | `PHP and Zend and BSD and MIT and ASL 1.0 and NCSA`; Remi's packaging is MIT |

The PHP2Shell mitigation itself (`php-8.0-cve-2026-109618.patch`) is authored by
Arnaud Le Blanc, a PHP core developer, and cherry-picked from upstream:

```
Subject: [PATCH] Avoid state corruption via bailout
Minimal mitigation for EOL version.
Fix GHSA-w8hw-w9fx-j79w (CVE-2026-109618)
Fix GHSA-6wmf-4rv5-p3rp (CVE-2026-109619)
(cherry picked from commit b62095c75da776f46b917a8e2a750d6a21d82a99)
```

## The three EL7 adjustments

`patches/php.spec.el7.patch` is the whole of it — 99 lines, touching only the
spec file. **No source file and no patch from the SRPM is modified.**

1. **`pkgconfig(icu-*) >= 74` → `>= 73`.** Remi's EL7 archive tops out at
   `libicu73-73.2`. PHP 8.0's `intl` needs ICU >= 50 upstream, so 73 is ample.
2. **Eight `Recommends:` lines removed.** EL7's rpm 4.11 does not understand
   weak dependencies.
3. **Twenty-one `rm <test>.phpt` lines given `-f`.** The spec's `%else` branch
   assumes OpenSSL 3 and removes `openssl_error_string_basic_openssl3.phpt`,
   which does not exist on EL7 (OpenSSL 1.0.2), so `%prep` aborts. The build
   runs `--without tests`, so removing test files is cosmetic either way.

## Build

Requires Docker. Everything happens in a throwaway `centos:7` container; your
host is not touched.

```sh
./build/run.sh            # RPMs land in ./rpms
```

Roughly 30 minutes under amd64 emulation on Apple Silicon, a few minutes on
native x86_64. The result is 33 RPMs.

`SHA256SUMS.rpms` records the checksums of the author's build. RPM builds are
not bit-for-bit reproducible (timestamps and build host are embedded), so your
checksums **will** differ. Compare package contents, not package hashes.

## Install

These are Software Collections packages. They install under `/opt/remi/php80`
and **coexist** with an existing `php74`/`php72` SCL — nothing is replaced, and
the running site is unaffected until you repoint it yourself.

```sh
yum -y --enablerepo=remi localinstall \
  php80-php-common-*.rpm php80-php-cli-*.rpm php80-php-fpm-*.rpm \
  php80-php-xml-*.rpm php80-php-mbstring-*.rpm php80-php-mysqlnd-*.rpm \
  php80-php-pdo-*.rpm php80-php-opcache-*.rpm php80-php-gd-*.rpm
```

`php80-runtime` comes from Remi's EL7 repository and is pulled in automatically;
so are `gd3php`, `libwebp7` and `oniguruma5php`. For a fully offline install,
fetch those four with `yumdownloader` first.

Two notes if you are migrating from `php74`:

- `php74-php-json` has no counterpart: JSON is in core as of PHP 8.0, shipped in
  `php80-php-common`.
- `php74-php-xmlrpc` has no counterpart either: `ext/xmlrpc` was moved out of
  core in PHP 8.0.

### Switching a site over

`php80-php-fpm`'s default pool listens on `127.0.0.1:9000`, which an existing
`php74-php-fpm` already holds. Give it a different port, then repoint nginx:

```sh
sed -i 's|^listen = 127.0.0.1:9000$|listen = 127.0.0.1:9090|' \
    /etc/opt/remi/php80/php-fpm.d/www.conf
systemctl enable --now php80-php-fpm
# then in your nginx server block: fastcgi_pass 127.0.0.1:9090;
```

Leaving `php74-php-fpm` running gives you a one-line rollback.

## Verifying the mitigation is really in the binary

Two independent checks. If an unpatched PHP is still installed, run them against
both and compare — that is the strongest evidence available short of an exploit.

**The patch exports a new symbol:**

```sh
nm -D /opt/remi/php80/root/usr/bin/php | grep zend_mm_safe_error_ex
# patched:   000000000021a54e T zend_mm_safe_error_ex
# unpatched: (no output)
```

**And it changes what happens on memory exhaustion.** The mitigation replaces
`exit(1)` with `_exit(1)` and writes straight to stderr, bypassing the normal
error path — which is precisely the unwinding that corrupted interpreter state:

```sh
php -d memory_limit=2M -r '$a=[]; while(1){$a[]=str_repeat("x",10000);}' \
  >/dev/null 2>&1; echo $?
# patched:   1
# unpatched: 255
```

### A behavioural side effect worth knowing

The same patch hard-disables `session.upload_progress`:

```c
-	if (!PS(rfc1867_enabled)) {
+	if (!PS(rfc1867_enabled) || true) {
```

It is off regardless of `php.ini`. That is deliberate — it is the trigger path
for CVE-2026-109619 — but if you rely on upload progress tracking, it is gone.

## Rebuilding for a newer Remi release

When Remi publishes `-22` or later, edit `SRPM_URL` and `SRPM_SHA256` in
`build/build.sh` and run `./build/run.sh` again. The three adjustments are
unlikely to change; if the build fails in `%prep`, re-read section
"The three EL7 adjustments" — it will be another EL7-vs-modern-distro assumption
of the same kind.

## Two EL7 potholes you will hit anyway

Independent of PHP, and worth knowing if you still run EL7:

1. **`vault.centos.org` now returns HTTP 403 for `*-primary.sqlite.bz2`** while
   still listing those files in `repomd.xml`. yum fails with "No more mirrors to
   try". Use `archive.kernel.org/centos-vault`, `linuxsoft.cern.ch/centos-vault`
   or `mirror.nsc.liu.se/centos-store` instead.
2. **`/etc/yum.repos.d/CentOS-SCLo-scl.repo` ships with its `baseurl` commented
   out** and no mirrorlist, so `centos-sclo-sclo` cannot resolve at all. Write
   the baseurl by hand.

## Status

Built from Remi `8.0.30-21` (2026-10-21). A one-off rebuild — **no promise of
future updates**. If Remi has published a newer release, what is described here
is out of date: rebuild it yourself with `build/`.

Not affiliated with, endorsed by, or supported by Remi Collet, the PHP project,
Red Hat, or the CentOS project. No warranty. See `LICENSE`.
