#!/usr/bin/env bash

# First thing, check for dependencies
# jq, yq, figlet, my exe    
#
#

function print_usage(){
	echo "Usage: convey <input-file> <output-type>.";
	printf "To see all possible conversions, use the flag -h\n\n";
};

function check_os(){
    case $1 in 
        *microsoft*) OS="WSL";
        ;;
        linux*) OS="Linux";
        ;;
        darwin*) OS="MacOS";
        ;;
        #msys*) OS="Windows";
        #;;
        #mingw*) OS="Windows";
        #;;
        *) OS="UNKNOWN:$1"; exit 1;
        ;;
    esac
    return 0
};

function check_distro(){
	local distro=$(cat /etc/os-release | awk -F= '$1=="ID" {
		val=$2
		gsub(/"/, "", val)   # strip any quotes
		print val
		exit
		}' /etc/os-release)
	local pkg_mgr=""
    local install_cmd=""
	case $distro in
		ubuntu*|debian*)
        		pkg_mgr="apt-get"
				update_cmd="$pkg_mgr update"
	        	install_cmd="$SUDO $pkg_mgr install -y"
        	;;
    	centos*|rhel*|fedora*|rocky*|*alma*)
       			if command -v dnf >/dev/null 2>&1; then
        	    		pkg_mgr="dnf"
        		    	install_cmd="$SUDO $pkg_mgr install -y"
       			else
        	    		pkg_mgr="yum"
        	    		install_cmd="$SUDO $pkg_mgr install -y"
        		fi
			#echo "Use: $install_cmd"
        	;;
    	arch*|manjaro*)
        		pkg_mgr="pacman"
        		install_cmd="$SUDO $pkg_mgr -Syu --noconfirm"
        	;;
   		alpine*)
		    	update_cmd=":"
        		pkg_mgr="apk"
        		install_cmd="$SUDO $pkg_mgr add"
        	;;
    		*)
        		echo "Unsupported OS: $distro" >&2;
        		exit 1
        	;;
	esac
    echo "$distro;$pkg_mgr;$install_cmd;$update_cmd"
};

function generate_sudoers_rule() {
    local user
    local pkg_mgr_path
	local inst_cmd="$1"
    user=$(whoami)

    # You should already have $inst_cmd set, e.g. "$SUDO dnf install -y"
    # Extract package manager command (e.g. "dnf") from $inst_cmd
    # Here we extract the second word from the command string (assumes format: $SUDO <pkg_mgr> install -y)
    local pkg_mgr=$(echo "$inst_cmd" | awk '{print $2}')
    pkg_mgr_path=$(command -v "$pkg_mgr")

    if [[ -z "$pkg_mgr_path" ]]; then
        echo "Package manager command '$pkg_mgr' not found!"
        return 1
    fi

    cat <<EOF
	# To allow user '$user' to run '$pkg_mgr install -y' without password, add this line to sudoers:
	$user ALL=(ALL) NOPASSWD: $pkg_mgr_path install -y *
EOF
};


# Only use $SUDO if we're non-root *and* sudo exists
if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
  SUDO="sudo"
else
  SUDO=""
fi

# Get package manager commands based on distro
IFS=';' read -r distro pkg_mgr install_cmd update_cmd <<< "$(check_distro)"

function check_dependencies(){
    os_filtered=$(echo "${OSTYPE//[0-9]*$/}")
    lo_os="$(echo "$os_filtered" | tr '[:upper:]' '[:lower:]')"
    check_os "$lo_os" || return 1
    echo "Detected OS=$OS"
    echo "Distro: $distro"

    # collect missing deps
    missing=()
    while IFS= read -r dep; do
        [[ -z "$dep" || "$dep" =~ ^# ]] && continue
        if command -v "$dep" >/dev/null 2>&1; then
            echo "✔ $dep is already installed."
        else
            echo "✖ $dep is missing."
            missing+=("$dep")
        fi
    done < deps

    if [ ${#missing[@]} -eq 0 ]; then
        echo "All dependencies are satisfied."
        return 0
    fi

    if [ "$OS" = "MacOS" ]; then
        echo "Installing missing deps with brew: ${missing[*]}"
        brew update
        brew install "${missing[@]}"
    elif [ "$OS" = "Linux" ]; then
        case "$distro" in
            *centos*|*redhat*|*fedora*|*rocky*|*almalinux*)
                echo "Installing missing deps on $OS with $pkg_mgr: ${missing[*]}"

                read -rp "Create sudoers entry for passwordless installs? [y/N] " ans
                if echo "$ans" | grep -qi '^y'; then
                    generate_sudoers_rule "$install_cmd" | $SUDO tee /etc/sudoers.d/$(whoami)-pkgmgr
                    $SUDO chmod 440 /etc/sudoers.d/$(whoami)-pkgmgr
                    echo "Verify syntax with: $SUDO visudo -c"
                fi

                if printf '%s\n' "${missing[@]}" | grep -q '^figlet$'; then
                    echo "→ Installing epel-release for figlet support"
                    $SUDO "$pkg_mgr" install -y epel-release
                fi

                if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
                    echo "→ Installing curl for downloading yq"
                    $SUDO "$pkg_mgr" install -y curl
                fi

                for pkg in "${missing[@]}"; do
                    if [ "$pkg" = "yq" ]; then
                        echo "→ Installing Mike Farah's yq from GitHub..."
                        if command -v curl >/dev/null 2>&1; then
                            $SUDO curl -fsSL -o /usr/local/bin/yq \
                              https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
                        else
                            $SUDO wget -qO /usr/local/bin/yq \
                              https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
                        fi
                        $SUDO chmod +x /usr/local/bin/yq
                    else
                        echo "→ ${SUDO:+$SUDO }$pkg_mgr install -y $pkg"
                        $SUDO "$pkg_mgr" install -y "$pkg"
                    fi
                done
                ;;
            *debian*|*ubuntu*)
                if [ -n "$update_cmd" ] && [ "$update_cmd" != ":" ]; then
                    echo "→ Refreshing package lists…"
                    $SUDO sh -c "$update_cmd"
                fi

                installable=()
                for pkg in "${missing[@]}"; do
                    [ "$pkg" != "yq" ] && installable+=("$pkg")
                done

                if [ "${#installable[@]}" -gt 0 ]; then
                    echo "→ Installing with apt-get: ${installable[*]}"
                    $SUDO apt-get install -y "${installable[@]}"
                fi

				if printf '%s\n' "${missing[@]}" | grep -q '^yq$'; then
					if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
						echo "→ Installing curl for downloading yq"
						$SUDO apt-get install -y curl
					fi

					echo "→ Installing yq from GitHub..."
					if command -v curl >/dev/null 2>&1; then
						$SUDO curl -fsSL -o /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
					else
						$SUDO wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
					fi
					$SUDO chmod +x /usr/local/bin/yq
				fi
                ;;
            *alpine*)
                # No-op update already handled by update_cmd=":"
                installable=()
                for pkg in "${missing[@]}"; do
                    [ "$pkg" != "yq" ] && installable+=("$pkg")
                done

                if [ "${#installable[@]}" -gt 0 ]; then
                    echo "→ Installing with apk: ${installable[*]}"
                    $SUDO apk add --no-cache "${installable[@]}"
                fi

				if printf '%s\n' "${missing[@]}" | grep -q '^yq$'; then
					if ! command -v curl >/dev/null 2>&1 && ! command -v wget >/dev/null 2>&1; then
						echo "→ Installing curl for downloading yq"
						$SUDO $pkg_mgr add --no-cache curl
					fi

					echo "→ Installing yq from GitHub..."
					if command -v curl >/dev/null 2>&1; then
						$SUDO curl -fsSL -o /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
					else
						$SUDO wget -qO /usr/local/bin/yq https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64
					fi
					$SUDO chmod +x /usr/local/bin/yq
				fi
                ;;
        esac
    fi

    return 0
}


if ! check_dependencies; then
    echo "Dependencies error. Exiting...";
    exit 1;
fi

if [ $# -eq 0 ]; then
    printf "\nError. Missing one or more arguments.\n";
    print_usage;
fi


figlet "Convey" || exit 1
input_fname="${1%.*}"
# echo "$input_fname"
input_ftype="${1##*.}"
target_ftype="${2#.}"
# echo "$input_ftype"
# echo "$target_ftype"
target="$input_fname"."$target_ftype"
# echo "$target"
case $input_ftype in
	json)
		case $target_ftype in 
			yaml|yml)
				# Detect which yq you're running
				if yq --version 2>&1 | grep -qi 'python'; then
					# Python-based yq (kislyuk/yq)
					# echo "Using Python-yq → converting JSON to YAML"
					# -y = YAML output; . = identity filter
					yq -y . "$1" > "$target"

				else
					# Go-based yq (mikefarah/yq v4+)
					# echo "Using Go-yq → converting JSON to YAML"
					# --input-format=json, -o=yaml (or -P), . = identity
					yq eval --input-format=json --output-format=yaml '.' "$1" > "$target"
				fi
			;;
			xml)
				yq eval --input-format=json -o=xml "$1" > "$target"
			;;
			*env*)
				jq -r 'to_entries | .[] | "\(.key)=\(.value)"' "$1" > "$target"
			;;
		esac
	;;
	*yaml*|*yml*)
		case $target_ftype in 
			json)
				yq eval -o=json "$1" > "$target"
			;;
			xml)
				yq eval -o=xml "$1" > "$target"
			;;
			*env*)
				yq eval -o=json "$1" \
				| jq -r '
						paths(scalars) as $p
						| [($p | join(".")), getpath($p)]
						| "\(.[0])=\(.[1])"
						' > "$target"
  			;;
		esac
	;;
	xml)
		case $target_ftype in 
			yaml|yml)
				yq eval --input-format=xml --output-format=yaml '.' "$1" > "$target"
			;;
			json)
				yq eval --input-format=xml -o=json "$1" > "$target"
			;;
			*env*)
				yq eval --input-format=xml -o=json "$1" \
					| jq -r '
						paths(scalars) as $p
						| [($p | join(".")), getpath($p)]
						| "\(.[0])=\(.[1])"
						' > "$target"
			;;
		esac
	;;
	*env*)
		case $target_ftype in 
			*yaml*|*yml*)
				jq -Rn '
					reduce inputs as $line ({}; 
						($line | select(test("=")) | split("=")) as [$k,$v] |
						setpath($k | split("."); $v)
					)
				' < "$1" \
				| yq eval -o=yaml - \
				> "$target"
  			;;
			*xml*)
				jq -Rn '
					reduce inputs as $line ({}; 
						($line | select(test("=")) | split("=")) as [$k,$v] |
						setpath($k | split("."); $v)
					)
				' < "$1" \
				| yq eval -o=xml - \
				> "$target"
  			;;
			*json*)
				jq -Rn '
				reduce inputs as $line ({}; 
					($line | select(test("=")) | split("=")) as [$k,$v] |
					setpath($k | split("."); $v)
				)
				' < "$1" > "$target"
			;;
		esac
	;;

esac