#!/bin/bash

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
        msys*) OS="Windows";
        ;;
        mingw*) OS="Windows";
        ;;
        *) OS="UNKNOWN:$1"; exit 1;
        ;;
    esac
    return 0
};

function check_distro(){
	local distro=$(ls -la /etc/ | awk '$9 ~ /release$/ && $1 !~ /^l/ {print $9}' )
	case $distro in
		ubuntu*|debian*)
        		pkg_mgr="apt"
	        	install_cmd="sudo apt update && sudo apt install -y"
        	;;
    	centos*|rhel*|fedora*|rocky*|almalinux*)
       			if command -v dnf >/dev/null 2>&1; then
        	    		pkg_mgr="dnf"
        		    	install_cmd="sudo dnf install -y"
       			else
        	    		pkg_mgr="yum"
        	    		install_cmd="sudo yum install -y"
        		fi
			#echo "Use: $install_cmd"
        	;;
    	arch*|manjaro*)
        		pkg_mgr="pacman"
        		install_cmd="sudo pacman -Syu --noconfirm"
        	;;
   		alpine*)
        		pkg_mgr="apk"
        		install_cmd="sudo apk add"
        	;;
    		*)
        		echo "Unsupported OS: $distro" >&2;
        		exit 1
        	;;
	esac
	echo "$install_cmd"
};

function generate_sudoers_rule() {
    local user
    local pkg_mgr_path

    user=$(whoami)

    # You should already have $inst_cmd set, e.g. "sudo dnf install -y"
    # Extract package manager command (e.g. "dnf") from $inst_cmd
    # Here we extract the second word from the command string (assumes format: sudo <pkg_mgr> install -y)
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


function check_dependencies(){
    os_filtered=$(echo "${OSTYPE//[0-9]*$/}");
    lo_os="$(echo "$os_filtered" | tr '[:upper:]' '[:lower:]')";
    check_os "$lo_os" || return 1;
    echo "Detected OS=$OS"

    # collect missing deps
    missing=()
    while IFS= read -r dep; do
        # skip blank lines and comments
        [[ -z "$dep" || "$dep" =~ ^# ]] && continue

        if command -v "$dep" >/dev/null 2>&1; then
            echo "✔ $dep is already installed."
        else
            echo "✖ $dep is missing."
            missing+=("$dep")
        fi
    done < deps

    # nothing to do?
    if [ ${#missing[@]} -eq 0 ]; then
        echo "All dependencies are satisfied."
        return 0
    fi

    # macOS: Homebrew doesn’t need sudoers hacks
    if [ "$OS" = "MacOS" ]; then
        echo "Installing missing deps with brew: ${missing[*]}"
        brew update
        brew install "${missing[@]}"
    else
        # optionally set up passwordless sudo for package installs
        read -rp "Create sudoers entry for passwordless installs? [y/N] " ans
        if [[ "$ans" =~ ^[Yy]$ ]]; then
            sudoers_file="/etc/sudoers.d/$(whoami)-pkgmgr"
            echo "Creating $sudoers_file..."
            generate_sudoers_rule | sudo tee "$sudoers_file" >/dev/null
            echo "Verify syntax with: sudo visudo -c"
        fi

        echo "Installing missing deps with: $PKGMGR ${missing[*]}"
        # split PKGMGR into array to handle sudo + flags
        read -r -a mgr_cmd <<< "$PKGMGR"
        "${mgr_cmd[@]}" "${missing[@]}"
    fi

    return 0
};

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
target_ftype="$2"
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