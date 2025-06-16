#!/bin/bash

# First thing, check for dependencies
# jq, yq, figlet, my exe    
#
#
OS=$?;
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

function check_dependencies(){
    os_filtered=$(echo "${OSTYPE//[0-9]*$/}");
    lo_os="$(echo "$os_filtered" | tr '[:upper:]' '[:lower:]')";
    check_os "$lo_os";
    if [ "$OS" == 'MacOS' ]; then
        echo "Install using homebrew;"
    elif [ "$OS" == 'Linux' ]; then
        echo "Check distro for package manager."
    else
        echo "Windows, requires downloading from either msys or vcpkg.?"
    fi
    return "$retval";
};

retval=$?;
check_dependencies;
if [ "$retval" -eq 0 ]; then
    echo "Dependencies error. Exiting...";
    exit 1;
fi
figlet -f sub-zero "Convey"

if [ $# -eq 0 ]; then
    printf "\nError. Missing one or more arguments.\n";
    print_usage;
fi
