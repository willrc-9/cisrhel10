#!/usr/bin/env bash
CONTROL_ID="1.1_filesystems"
CONTROL_DESC="Disable unused filesystem and storage kernel modules"

shopt -s globstar

FILESYSTEMS=(
    "cramfs"
    "freevxfs"
    "hfs"
    "hfsplus"
    "jffs2"
    "overlay"
    "squashfs"
    "udf"
)
DRIVERS=(
	"firewire-core"
	"usb-storage"
)

audit() {
	local failed=0


	for mod in "${FILESYSTEMS[@]}"; do
		l_mod_name="${mod}"
		l_mod_type="fs"
		local exists_msg=""

   		while IFS= read -r l_mod_path; do
      		if [ -d "$l_mod_path/${l_mod_name//-/\/}" ] &&  \
      		[ -n "$(ls -A "$l_mod_path/${l_mod_name//-/\/}")" ]; then
			exists_msg="$l_mod_name exists in $l_mod_path"

      		fi
   		done < <(readlink -e /usr/lib/modules/**/kernel/"$l_mod_type" 2>/dev/null \
   		|| readlink -e /lib/modules/**/kernel/$l_mod_type 2>/dev/null)

		if [[ -z "$exists_msg" ]]; then
			continue
		fi
		
		local check_fail=0

		if ! lsmod | grep -Eq "^${l_mod_name}\b"; then
			check_fail=1
		fi

		if ! modprobe --showconfig | grep -Eq "^\s*blacklist\s+${l_mod_name}\b"; then
			check_fail=1
		fi

		if [[ $check_fail -eq 1 ]]; then
			echo "[!] $exists_msg (not blacklisted or disabled)" >&2
			((failed++))
		fi
	done

	for mod in "${DRIVERS[@]}"; do
                l_mod_name="${mod}"
                l_mod_type="drivers"
                local exists_msg=""

                while IFS= read -r l_mod_path; do
                	if [ -d "$l_mod_path/${l_mod_name//-/\/}" ] &&  \
                	[ -n "$(ls -A "$l_mod_path/${l_mod_name//-/\/}")" ]; then
                                exists_msg="$l_mod_name exists in $l_mod_path"

                	fi
                done < <(readlink -e /usr/lib/modules/**/kernel/"$l_mod_type" 2>/dev/null \
                || readlink -e /lib/modules/**/kernel/$l_mod_type 2>/dev/null)

                
		
		if [[ -z "$exists_msg" ]]; then
                        continue
                fi

                local check_fail=0

                if ! lsmod | grep -Eq "^${l_mod_name}\b"; then
                        check_fail=1
                fi

                if ! modprobe --showconfig | grep -Eq "^\s*blacklist\s+${l_mod_name}\b"; then
                        check_fail=1
                fi

		if [[ $check_fail -eq 1 ]]; then
                        echo "[!] $exists_msg (not blacklisted or disabled)" >&2
                        ((failed++))
                fi

        done
	if [[ $failed -gt 0 ]]; then
		return 1
	else
		return 0
	fi
}

harden() {
    f_module_fix() {
        if [ -n "$l_mpath" ]; then
            echo " - Unloading module: \"$l_mname\""
            modprobe -r "$l_mname" 2>/dev/null
            rmmod "$l_mname" 2>/dev/null

            echo " - Disabling module: \"$l_mname\" in \"$l_mpat\""
            printf '%s\n' "install $l_mname /bin/false" >> "$l_mpat"
            printf '%s\n' "blacklist $l_mname" >> "$l_mpat"
        fi
    }

    # 1. Remediate Filesystems
    for mod in "${FILESYSTEMS[@]}"; do
        l_mname="$mod"
        l_mtype="fs"
        l_mpath=""
        l_mpat="/etc/modprobe.d/${l_mname}.conf"

        while IFS= read -r l_mod_path; do
            if [ -d "$l_mod_path/${l_mname//-/\/}" ] && \
               [ -n "$(ls -A "$l_mod_path/${l_mod_name//-/\/}")" ]; then
                l_mpath="$l_mod_path"
            fi
        done < <(readlink -e /usr/lib/modules/**/kernel/$l_mtype 2>/dev/null \
              || readlink -e /lib/modules/**/kernel/$l_mtype 2>/dev/null)

        f_module_fix
    done

    # 2. Remediate Drivers
    for mod in "${DRIVERS[@]}"; do
        l_mname="$mod"
        l_mtype="drivers"
        l_mpath=""
        l_mpat="/etc/modprobe.d/${l_mname}.conf"

        while IFS= read -r l_mod_path; do
            if [ -d "$l_mod_path/${l_mname//-/\/}" ] && \
               [ -n "$(ls -A "$l_mod_path/${l_mod_name//-/\/}")" ]; then
                l_mpath="$l_mod_path"
            fi
        done < <(readlink -e /usr/lib/modules/**/kernel/$l_mtype 2>/dev/null \
              || readlink -e /lib/modules/**/kernel/$l_mtype 2>/dev/null)

        f_module_fix
    done

    return 0
}
