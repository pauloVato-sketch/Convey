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
    if [ "$OS" == 'MacOS' ]; then
        echo "Install using homebrew;"
    elif [ "$OS" == 'Linux' ]; then
        echo "Checking distro for package manager."
	inst_cmd=$(check_distro) || return 1
	echo "Seu comando de instalação é $inst_cmd"
	
	read -rp "Do you want me to create the sudoers rule file for passwordless installs? [y/N] " ans
	if [[ "$ans" =~ ^[Yy]$ ]]; then
    		sudoers_file="/etc/sudoers.d/$(whoami)-pkgmgr"
    		echo "Creating sudoers file $sudoers_file..."
 		generate_sudoers_rule | sudo tee "$sudoers_file" > /dev/null
		echo "Done! Please verify with 'sudo visudo -c'."
	fi

	read -r -a install_cmd <<< "$inst_cmd"

	for dep in $(cat deps); do
		"${install_cmd[@]}" "$dep"
	done

    else
        echo "Windows, requires downloading from either msys or vcpkg.?"
    fi
    return 0;
};

if ! check_dependencies; then
    echo "Dependencies error. Exiting...";
    exit 1;
fi
figlet -f sub-zero "Convey"

if [ $# -eq 0 ]; then
    printf "\nError. Missing one or more arguments.\n";
    print_usage;
fi
