#!/usr/bin/env bash
# Throwaway harness: loads the modified scripts without their entry point and
# exercises the new/changed helper functions. Run from the repo root:
#   bash run-tests.sh
set -u
pass=0; fail=0
ck() { # name actual expected
    if [[ "$2" == "$3" ]]; then pass=$((pass+1)); else fail=$((fail+1)); echo "FAIL: $1 got=[$2] want=[$3]"; fi
}

extract_lib() { # file -> strip everything from the root-check entry point on
    local line
    line=$(grep -n '^# This script must be executed as root' "$1" | cut -d: -f1 | head -n1)
    head -n $((line - 1)) "$1" > "$1.lib.tmp"
    echo "$1.lib.tmp"
}

lib1=$(extract_lib xray-install.sh)
# shellcheck disable=SC1090
source "$lib1"
lib2=$(extract_lib xray-install-docker.sh)
# shellcheck disable=SC1090
source "$lib2"

# ---- is_valid_host ----
ck host-domain "$(is_valid_host www.cloudflare.com && echo ok || echo bad)" ok
ck host-ipv4   "$(is_valid_host 203.0.113.10 && echo ok || echo bad)" ok
ck host-empty  "$(is_valid_host "" && echo ok || echo bad)" bad
ck host-slash  "$(is_valid_host 'evil.com/x' && echo ok || echo bad)" bad
ck host-inj    "$(is_valid_host 'a","b' && echo ok || echo bad)" bad
ck host-space  "$(is_valid_host 'a b' && echo ok || echo bad)" bad
ck host-1label "$(is_valid_host localhost && echo ok || echo bad)" bad
ck host-multi  "$(is_valid_host my-host.example.com && echo ok || echo bad)" ok
ck host-typo5  "$(is_valid_host 1.2.3.4.5 && echo ok || echo bad)" ok   # accepted as a label sequence

# ---- generate_uuid / generate_short_id (MSYS: no /proc uuid, no uuidgen -> od fallback) ----
u1=$(generate_uuid); u2=$(generate_uuid)
ck uuid-fmt1 "$([[ $u1 =~ ^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$ ]] && echo ok || echo bad)" ok
ck uuid-uniq "$([[ $u1 != "$u2" ]] && echo ok || echo bad)" ok
s1=$(generate_short_id)
ck sid-fmt   "$([[ $s1 =~ ^[0-9a-f]{8}$ ]] && echo ok || echo bad)" ok
ck sid-collide "$(generate_short_id "$s1" | grep -vqx "$s1" && echo ok || echo bad)" ok

# ---- private-IP filter logic from detect_public_ip (regex extracted verbatim) ----
is_private() {
    local cand="$1"
    [[ "$cand" =~ ^[0-9]{1,3}(\.[0-9]{1,3}){3}$ ]] || return 0
    case "$cand" in 10.*|127.*|169.254.*|192.168.*|0.*) return 0 ;; esac
    [[ "$cand" =~ ^172\.(1[6-9]|2[0-9]|3[01])\. ]] && return 0
    [[ "$cand" =~ ^100\.(6[4-9]|[7-9][0-9]|1[01][0-9]|12[0-7])\. ]] && return 0
    return 1
}
for ip in 10.0.0.5 127.0.0.1 169.254.1.1 192.168.1.1 172.16.0.1 172.31.255.255 100.64.0.1 100.127.255.255 0.0.0.0; do
    ck "private-$ip" "$(is_private "$ip" && echo priv || echo pub)" priv
done
for ip in 8.8.8.8 203.0.113.10 172.32.0.1 100.128.0.1 100.63.0.1; do
    ck "public-$ip" "$(is_private "$ip" && echo priv || echo pub)" pub
done

# ---- leading-zero octal fix ----
ck octal "$((10#08))" 8

# ---- bilingual helpers (default must be English when SCRIPT_LANG is unset) ----
ck i18n-t-default "$(t hello 你好)" hello
ck i18n-msg-default "$(msg hello 你好)" hello
SCRIPT_LANG=en
ck i18n-t-en "$(t hello 你好)" hello
ck i18n-msg-en "$(msg hello 你好)" hello
SCRIPT_LANG=zh
ck i18n-t-zh "$(t hello 你好)" 你好
ck i18n-msg-zh "$(msg hello 你好)" 你好
unset SCRIPT_LANG

# ---- default_lang: XRAY_INSTALL_LANG wins over the locale; zh locales detected ----
def=$(XRAY_INSTALL_LANG=en LC_ALL=zh_CN.UTF-8 default_lang);     ck lang-env-en   "$def" en
def=$(XRAY_INSTALL_LANG=zh LC_ALL=en_US.UTF-8 default_lang);     ck lang-env-zh   "$def" zh
def=$(XRAY_INSTALL_LANG=xx LC_ALL=zh_CN.UTF-8 default_lang);     ck lang-env-bad  "$def" zh
def=$(LC_ALL=zh_TW.UTF-8 default_lang);                          ck lang-loc-tw   "$def" zh
def=$(LC_MESSAGES=zh_CN default_lang);                           ck lang-loc-msgs "$def" zh
def=$(LC_ALL=en_US.UTF-8 default_lang);                          ck lang-loc-en   "$def" en
def=$(unset LANG LC_ALL LC_MESSAGES; default_lang);              ck lang-loc-none "$def" en

# ---- get_server_address: manual input validated and persisted; saved value reused ----
srv_file=$(mktemp)
rm -f "$srv_file"
SERVER_ADDR_FILE="$srv_file"
detect_public_ip() { echo ""; }   # force the manual-input path
out=$(printf 'bad address\n1.2.3.4\n' | get_server_address 2>/dev/null)
ck gsa-validate "$out" "1.2.3.4"
ck gsa-persist "$(cat "$srv_file")" "1.2.3.4"
printf '203.0.113.9\n' > "$srv_file"
out=$(get_server_address < /dev/null)
ck gsa-reuse "$out" "203.0.113.9"
rm -f "$srv_file"
unset SERVER_ADDR_FILE

# ---- awk rc.local insertion (portable replacement for GNU sed 0,/re/) ----
printf '#!/bin/sh\nfoo\nexit 0\n' > rc.local.test
awk -v line="/usr/local/bin/xray-autostart # xray-autostart" \
    '!done && /^exit 0/ { print line; done = 1 } { print }' \
    rc.local.test > rc.local.test2
c1=$(grep -c 'xray-autostart' rc.local.test2)
c2=$(tail -n1 rc.local.test2)
ck rclocal "$( [[ $c1 -eq 1 && $c2 == 'exit 0' ]] && echo ok || echo bad)" ok
rm -f rc.local.test rc.local.test2

rm -f "$lib1" "$lib2"
echo "RESULT pass=$pass fail=$fail"
[[ $fail -eq 0 ]]
