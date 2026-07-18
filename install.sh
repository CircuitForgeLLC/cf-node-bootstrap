#!/bin/bash
###################################################################
#         Pyr0ball's Reductive Bash Library Installer            #
###################################################################

# initial vars
VERSION=2.3.5
scripttitle="Pyr0ball's Reductive Bash Library Installer - v$VERSION"

# Bash expansions to get the name and location of this script when run
scriptname="${BASH_SOURCE[0]##*/}"
rundir="${BASH_SOURCE[0]%/*}"

# Source PRbL Functions locally or retrieve from online
if [ ! -z $prbl_functions ] ; then
    source $prbl_functions
else
    if [ -f ${rundir}/functions ] ; then
        source ${rundir}/functions
    else
        # Iterate through get commands and fall back on next if unavailable
        if command -v curl >/dev/null 2>&1; then
            source <(curl -ks 'https://raw.githubusercontent.com/pyr0ball/PRbL/main/functions')
        elif command -v wget >/dev/null 2>&1; then
            source <(wget -qO- 'https://raw.githubusercontent.com/pyr0ball/PRbL/main/functions')
        elif command -v fetch >/dev/null 2>&1; then
            source <(fetch -qo- 'https://raw.githubusercontent.com/pyr0ball/PRbL/main/functions')
        else
            echo "Error: curl, wget, and fetch commands are not available. Please install one to retrieve PRbL functions."
            exit 1
        fi
    fi
fi

# Source CF Apps registry/installer (see cf-apps/README.md)
if [ -f "${rundir}/lib/cf-apps.functions" ] ; then
    source "${rundir}/lib/cf-apps.functions"
fi

rundir_absolute=$(pushd $rundir ; pwd ; popd)
escape_dir=$(printf %q "${rundir_absolute}")
logfile="${rundir}/${pretty_date}_${scriptname}.log"
#-----------------------------------------------------------------#
# Script-specific Parameters
#-----------------------------------------------------------------#

# Store functions revision in a variable to compare with if already installed
installer_functionsrev=$functionsrev

# Get and store the user currently executing this script
runuser=$(whoami)

# set up an array containing the users listed under /home/
users=($(ls /home/))

# If run as non-root, default install to user's home directory
userinstalldir="$HOME/.local/share/prbl"

# If run as root, this will be the install directory
globalinstalldir="/usr/share/prbl"

# Initialize arrays for file and dependency management
bins_missing=()
backup_files=()
installed_files=()
installed_dirs=()

# List of dependency packaged to be istalled via apt (For Debian/Ubuntu)
packages=(
    git
    vim
    lm-sensors
    curl
    net-tools
    bc
)

# OS distribution auto-detection
if type lsb_release >/dev/null 2>&1; then
    # linuxbase.org
    OS=$(lsb_release -si)
    VER=$(lsb_release -sr)
elif [ -f /etc/debian_version ]; then
    # Older Debian/Ubuntu/etc.
    OS=Debian
    VER=$(cat /etc/debian_version)
elif [ -f /etc/os-release ]; then
    # freedesktop.org and systemd
    . /etc/os-release
    OS=$NAME
    VER=$VERSION_ID
elif [ -f /etc/lsb-release ]; then
    # For some versions of Debian/Ubuntu without lsb_release command
    . /etc/lsb-release
    OS=$DISTRIB_ID
    VER=$DISTRIB_RELEASE
elif [ -f /etc/debian_version ]; then
    # Older Debian/Ubuntu/etc.
    OS=Debian
    VER=$(cat /etc/debian_version)
elif [ -f /etc/SuSe-release ]; then
    # Older SuSE/etc.
    ...
elif [ -f /etc/redhat-release ]; then
    # Older Red Hat, CentOS, etc.
    OS=$(cat /etc/redhat-release | awk '{print $1}')
else
    # Fall back to uname, e.g. "Linux <version>", also works for BSD, etc.
    OS=$(uname -s)
    VER=$(uname -r)
fi

# Add apt-notifier-common required packages
if [[ $OS_DETECTED == "Debian" ]] || [[ $OS_DETECTED == "Ubuntu" ]]; then
    packages+=(apt-config-auto-update)
fi

# This variable is what is injected into the bashrc
bashrc_append="
# Pluggable bashrc config. Add environment modifications to ~/.bashrc.d/ and append with '.bashrc'
if [ -n \"\$BASH_VERSION\" ]; then
    # include .bashrc if it exists
    if [ -d \"\$HOME/.bashrc.d\" ]; then
        for file in \$HOME/.bashrc.d/*.bashrc ; do
            source \"\$file\"
        done
    fi
fi
"

#-----------------------------------------------------------------#
# Script-specific Funcitons
#-----------------------------------------------------------------#

script-title() {
    format_boxborder --center --box-type=double \
    "${red}(_____ ${lrd}(_____  ${ylw}| |   ${ong}| |        ${lyl}(_____)           _        | | |            ${dfl}" \
    "${red} _____) )${lrd}____) ) ${ylw}| _ ${ong}| |        ${lyl}   _   ____   ___| |_  ____| | | ____  ____ ${dfl}" \
    "${red}|  ____${lrd}(_____ (${ylw}| ||  ${ong}| |        ${lyl}  | | |  _ \ /___)  _)/ _  | | |/ _  )/ ___)${dfl}" \
    "${red}| |          ${lrd}| ${ylw}| |_) ) ${ong}|_____   ${lyl} _| |_| | | |___ | |_( ( | | | ( (/ /| |    ${dfl}" \
    "${red}|_|          ${lrd}|_${ylw}|____/${ong}|_______)  ${lyl}(_____)_| |_(___/ \___)_||_|_|_|\____)_|    ${dfl}"
}

# Function for displaying the usage of this script
usage(){
    boxborder \
        "${lbl}Usage:${dfl}" \
        "${lyl}./$scriptname ${bld}[args]${dfl}" \
        "$(boxseparator)" \
        "[args:]" \
        "   -i [--install]" \
        "   -d [--dependencies]" \
        "   -D [--dry-run]" \
        "   -r [--remove]" \
        "   -f [--force]" \
        "   -F [--force-remove]" \
        "   -u [--update]" \
        "   -h [--help]" \
        "" \
        "Running this installer as 'root' will install globally to $globalinstalldir" \
        "You must run as 'root' for this script to automatically resolve dependencies"
}

detectvim(){
    # If the vim install directory exists, check for and store the highest numerical value version installed
    if [[ -d /usr/share/vim ]] ; then
        viminstall=$(ls -lah /usr/share/vim/ | grep vim | grep -v rc | awk '{print $NF}' | tail -n 1)
    else
        viminstall=null
        warn "vim is not currently installed, unable to set up colorscheme and formatting"
    fi
}

check-deps(){
    # Iterate through the list of required packages and check if installed
    for pkg in ${packages[@]} ; do
        local _pkg=$(dpkg -l $pkg 2>&1 >/dev/null ; echo $?)
        # If not installed, add it to the list of missing bins
        if [[ $_pkg != 0 ]] ; then
            bins_missing+=($pkg)
        fi
    done
    # Count the number of entries in bins_missing
    local _bins_missing=${#bins_missing[@]}
    # If higher than 0, return a fail (1)
    if [[ $_bins_missing != 0 ]] ; then
        return 1
    else
        return 0
    fi
}

install(){
    # If script is run as root, run global install
    if [[ $runuser == root ]] ; then
        installdir="${globalinstalldir}"
        prbl_bashrc="
        # Pyr0ball's Reductive Bash Library (PRbL) Functions library v$VERSION and greeting page setup
        export prbl_functions=\"${installdir}/functions\"
        "
        globalinstall
    else
    # If user is non-root, run user-level install
        installdir="${userinstalldir}"
        prbl_bashrc="
        # Pyr0ball's Reductive Bash Library (PRbL) Functions library v$VERSION and greeting page setup
        export prbl_functions=\"${installdir}/functions\"
        "
        userinstall
    fi
}

install-functions(){
    # Copy functions
    if [ -f ${rundir}/PRbL/functions ] ; then
        install-file ${rundir}/PRbL/functions ${installdir}
    else
        curl -ks 'https://raw.githubusercontent.com/pyr0ball/PRbL/main/functions' > ${rundir}/functions
        install-file ${rundir}/functions ${installdir}
    fi  
}

take-backup(){
    name="$1"
    # if [[ $update_run != true ]] ; then
        # Check if a backup file or symbolic link already exists
        if [[ -e "$name.bak" || -L "$name.bak" ]]; then
            run boxline " $name.bak backup already exists"
        else
            # Check if the file is a hidden file (starts with a dot)
            if [[ "$name" == .* ]]; then
                # Add a dot to the beginning of the backup file name
                backup_name=".${name}.bak"
            else
                # Create the backup file name by appending ".bak" to the original file name
                backup_name="${name}.bak"
            fi
            # Copy the file to the backup file with preservation of file attributes
            run cp -p "$name" "$backup_name"
            # Add the original file to the list of backup files
            run boxline " $name.bak backup already exists"
            # Log the original file name to the backup file list file
            run echo "$name" >> "$rundir/backup_files.list"
        fi
    # fi
}

restore-backup(){
	run echo "${#backup_files[@]}"
	for file in "${backup_files[@]}" ; do 
		run cp "$file".bak $file
		run echo "$file is restored"
	done
        run boxline " $name.bak backup already exists"
    if [ -f $rundir/backup_files.list ] ; then
        run rm $rundir/backup_files.list
    fi
}

install-file(){
    local _source="$1"
    local _destination="$2"
    local _source_root="$3"
    local _filename=${_source##*/}
    local _destination_file=${_destination}/${_filename#${_source_root}}
    installed_files+=("${_destination_file}")
    if [[ $update_run == true ]] ; then
        run boxline "$scriptname: added file ${_destination_file} to list"
    else
        run cp -p $_source $_destination_file && boxline "Installed ${_filename}" || warn "Unable to install ${_filename}"
        run echo "${_destination_file}" >> $rundir/installed_files.list
    fi
}

install-dir() {
    local _source="$1"
    local _destination="$2"
    installed_dirs+=("$_source -> $_destination")
    # Iterate through all files in the source directory recursively
    while IFS= read -r -d '' source_file; do
        # Construct the destination file path by removing the source directory path
        # and appending it to the destination directory path
        local _filename="${source_file#${_source}}"
        local destination_file="${_destination}/${source_file#${_source}}"
        # Create the parent directory of the destination file if it doesn't exist
        # Log the destination file path to the logfile
        #echo "$destination_file" >> "$logfile"
        installed_files+=($destination_file)
        if [[ $update_run == true ]] ; then
            run boxline "$scriptname: added file ${destination_file} to list"
        else
            run mkdir -p "$(dirname "$destination_file")"
            run cp -p ${_source}${_filename} $destination_file && boxline "Installed ${_filename}" || warn "Unable to install ${_filename}"
            run echo "${destination_file}" >> $rundir/installed_files.list
        fi
    done < <(find "$_source" -type f -print0)
}

install-deps(){
    boxborder "Installing packages $packages"
    if [[ dry_run != true ]] ; then
        # using a spinner function block to track installation progress
        for _package in $packages ; do 
            sudo apt-get install -y $_package
        done
    else
        boxline "DryRun: spin \"for $_package in $packages ; do sudo apt-get install -y $_package ; done\""
    fi
    # Sets dependency installed flag to true
    depsinstalled=true
}

install-extras(){
    _extras=($(ls ${escape_dir}/extras/ | grep -v 'log$'))
    # extra_installs=$(ls ${escape_dir}/extras/)
    # for file in $extra_installs ; do
    #     _extras+=("$file")
    # done

    boxborder "Which extras should be installed?"
    for each in {1..${#_extras[@]}} ; do
        preselect+=("false")
    done
    multiselect result _extras preselect

    # For each extra, compare input choice and apply installs
    idx=0
    for extra in "${_extras[@]}"; do
        # If the selected user is set to true
        if [[ "${result[idx]}" == "true" ]] ; then
            if [[ $dry_run != true ]] ; then
                boxline "running extra $extra"
                run "${escape_dir}/extras/$extra -i"
            else
                dry_run=false
                run "${escape_dir}/extras/$extra -D"
                dry_run=true
            fi
        # else
        #     echo "index for $extra is ${result[idx]}"
        fi
    done
}

extras-menu(){
    # Download and install any other extras
    #if [ -d "${rundir_absolute}/extras/" ] ; then
        boxborder "Extra installs available. Select and install?"
        extras_menu=(
        "$(boxline "${green_check} Yes")"
        "$(boxline "${red_x} No")"
        )
        case `select_opt "${extras_menu[@]}"` in
            0)  boxborder "${grn}Installing extras...${dfl}"
                install-extras
                ;;
            1)  boxline "Skipping extras installs" ;;
        esac
    #fi
}

userinstall(){
# TODO: modify this function to accept a user as an argument and call it from globalinstall
    # Create install directory under user's home directory
    run mkdir -p ${installdir}

    # Copy functions first
    install-functions

    # Copy bashrc scripts to home folder
    install-dir ${rundir}/lib/skel/ $HOME

    # Check for dependent applications and warn user if any are missing
    if ! check-deps ; then
        warn "Some of the utilities needed by this script are missing"
        boxlinelog "Missing utilities:"
        boxlinelog "${bins_missing[@]}"
        boxlinelog "Would you like to install them? (this will require root password)"
        utilsmissing_menu=(
        "$(boxline "${green_check} Yes")"
        "$(boxline "${red_x} No")"
        )
        case `select_opt "${utilsmissing_menu[@]}"` in
            0)  boxlinelog "${grn}Installing dependencies...${dfl}"
                install-deps
                ;;
            1)  warn "Dependent Utilities missing: $bins_missing" ;;
        esac
    fi

    # Check for and parse the installed vim version
    detectvim

    # If vim is installed, add config files for colorization and expandtab
    if [[ $viminstall != null ]] ; then
        run mkdir -p ${HOME}/.vim/colors
        install-file $rundir/lib/vimfiles/crystallite.vim ${HOME}/.vim/colors
        take-backup $HOME/.vimrc
        cp $rundir/lib/vimfiles/vimrc.local $rundir/lib/vimfiles/.vimrc
        install-file $rundir/lib/vimfiles/.vimrc $HOME
        rm $rundir/lib/vimfiles/.vimrc
    fi

    # Check for existing bashrc config, append if missing
    if [[ $(cat ${HOME}/.bashrc | grep -c 'bashrc.d') == 0 ]] ; then
        take-backup $HOME/.bashrc
        echo -e "$bashrc_append" >> $HOME/.bashrc && boxborder "bashc.d installed..." 
        echo -e "$prbl_bashrc" >> $HOME/.bashrc.d/00-prbl.bashrc && boxborder "bashc.d/00-prbl installed..." 
    fi

    # Create the quickinfo cache directory
    #mkdir -p $HOME/.quickinfo
    export prbl_functions="${installdir}/functions"

    # If all required dependencies are installed, launch initial cache creation
    #if [[ "$bins_missing" == "false" ]] ; then
    #    bash $HOME/.bashrc.d/11-quickinfo.bashrc
    #fi
    #clear

    # launch extra installs
    extras-menu

    # Optionally provision this node with CircuitForge apps
    if declare -F cf-provision-menu >/dev/null; then
        cf-provision-menu
    fi

    if [[ $dry_run != true ]] ; then
        boxborder "${grn}Please be sure to run ${lyl}sensors-detect --auto${grn} after installation completes${dfl}"
    fi
}

globalinstall(){
    # Create global install directory
    run mkdir -p ${installdir}

    install-functions
    export prbl_functions="${globalinstalldir}/functions"

    # Check for dependent applications and offer to install
    if ! check-deps ; then
        warn "Some of the utilities needed by this script are missing"
        boxlinelog "Missing utilities:"
        boxlinelog "${bins_missing[@]}"
        boxlinelog "Would you like to install them? (this will require root password)"
        utilsmissing_menu=(
        "$(boxline "${green_check} Yes")"
        "$(boxline "${red_x} No")"
        )
        case `select_opt "${utilsmissing_menu[@]}"` in
            0)  boxlinelog "${grn}Installing dependencies...${dfl}"
                install-deps
                ;;
            1)  warn "Dependent Utilities missing: $bins_missing" ;;
        esac
    fi

    # Prompt the user to specify which users to install the quickinfo script for
    boxborder "Which users should PRbL be installed for?"
    multiselect result users "false"

    # For each user, compare input choice and apply installs
    idx=0
    for selecteduser in "${users[@]}"; do
        # If the selected user is set to true
        if [[ "${result[idx]}" == "true" ]] ; then
            #cp -r ${rundir}/lib/skel/* /etc/skel/
            install-dir ${rundir}/lib/skel/ /home/${selecteduser}/
            # for file in $(ls -a -I . -I .. ${rundir}/lib/skel/) ; do
            #     install-dir ${rundir}/lib/skel/$file $HOME
            # done
            if [[ $(cat /home/${selecteduser}/.bashrc | grep -c prbl) == 0 ]] ; then
                take-backup /home/${selecteduser}/.bashrc
                echo -e "$bashrc_append" >> /home/${selecteduser}/.bashrc && boxborder "bashc.d installed..." || warn "Malformed append on ${lbl}/home/${selecteduser}/.bashrc${dfl}. Check this file for errors"
            fi
            run sudo chown -R ${selecteduser}:${selecteduser} ${installdir}
            if [[ "$bins_missing" == "false" ]] ; then
                boxborder "Checking ${selecteduser}'s bashrc..."
                run su ${selecteduser} -c /home/${selecteduser}.bashrc.d/11-quickinfo.bashrc
            fi
        fi
    done

    detectvim
    if [[ $viminstall != null ]] ; then
        install-file $rundir/lib/vimfiles/crystallite.vim /usr/share/vim/${viminstall}/colors
        take-backup /etc/vim/vimrc.local
        install-file $rundir/lib/vimfiles/vimrc.local /etc/vim/vimrc.local
    fi
    if [ ! -z $(which sensors-detect) ] ; then
        run sensors-detect --auto
    fi

    # Download and install any other extras
    extras-menu

    # Optionally provision this node with CircuitForge apps
    if declare -F cf-provision-menu >/dev/null; then
        cf-provision-menu
    fi
    #clear
}

remove(){
    if [ -f $rundir/installed_files.list ] ; then
        _installed_list=($(cat $rundir/installed_files.list))
    fi
    for file in "${installed_files[@]}" ; do
        if [ -f $file ] ; then
            run rm "$file"
            boxline "Removed $file"
        fi
    done
    for file in "${_installed_list[@]}" ; do
        if [ -f $file ] ; then
            run rm "$file"
            boxline "Removed $file"
        fi
    done
    if [ -f $rundir/installed_files.list ] ; then
        run rm $rundir/installed_files.list
    fi
    installed_files=()
    # if [ -f $rundir/backup_files.list ] ; then
    #     for file in $(cat $rundir/backup_files.list) ; do
    #         restore-backup $file
    #     done
    # fi
    restore-backup
}

remove-arbitrary(){
    update_run=true
    userinstall
    globalinstall
    update_run=
    #backup_files=()
    remove
}

update(){
    remove-arbitrary
    run git stash -m "$pretty_date stashing changes before update to latest"
    run git fetch && run git pull --recurse-submodules
    pushd PRbL
        run git checkout main
        run git pull
    popd
    install
}

dry-run-report(){
    box-rounded
    boxborder "${grn}Dry-run Report:${dfl}"
    box-norm
    boxborder \
    "bins_missing= " \
    "${bins_missing[@]}" \
    "backup_files= " \
    "${backup_files[@]}" \
    "installed_files= " \
    "${installed_files[@]}" \
    "installed_dirs= " \
    "${installed_dirs[@]}"
}

#------------------------------------------------------#
# Options and Arguments Parser
#------------------------------------------------------#
script-title
case $1 in
    -i | --install)
        install && success " [${red}P${lrd}R${ylw}b${ong}L ${lyl}Installed${dfl}]"
        ;;
    -r | --remove)
        remove && success " [${red}P${lrd}R${ylw}b${ong}L ${lyl}Removed${dfl}]"
        ;;
    -d | --dependencies)
        install-deps && success "${red}P${lrd}R${ylw}b${ong}L${dfl} Dependencies installed!"
        ;;
    -D | --dry-run)
        export dry_run=true
        box-double
        boxtop
        install
        boxbottom
        dry-run-report
        usage   
        unset dry_run
        success "${red}P${lrd}R${ylw}b${ong}L${dfl} Dry-Run Complete!"
        ;;
    -u | --update)
        export update_run=true
        update && unset update_run && success " [${red}P${lrd}R${ylw}b${ong}L ${lyl}Updated${dfl}]"
        ;;
    -f | --force)
        remove-arbitrary
        install && success " [${red}P${lrd}R${ylw}b${ong}L ${lyl}Installed${dfl}]"
        ;;
    -F | --force-remove)
        remove-arbitrary && success " [${red}P${lrd}R${ylw}b${ong}L ${lyl}Force-Removed${dfl}]"
        ;;
    -h | --help)
        usage
        ;;
    *)
        warn "Invalid argument $@"
        usage
        #exit 2
        ;;
esac
#------------------------------------------------------#
# Script begins here
#------------------------------------------------------#
