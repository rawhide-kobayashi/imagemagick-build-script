#!/usr/bin/env bash
# shellcheck disable=SC1091,SC2034,SC2046,SC2066,SC2068,SC2086,SC2119,SC2162,SC2181

############################################################################################################
##
##  Script Version: 4.3
##  Updated: 01.14.24
##
##  GitHub: https://github.com/slyfox1186/imagemagick-build-script
##
##  Purpose: Build ImageMagick 7 from the source code obtained from ImageMagick's official GitHub repository
##
##  Function: ImageMagick is the leading open-source command line image processor. It can blur, sharpen, warp,
##            reduce total file size, ect... The possibilities are vast
##
##  Method: The script will search GitHub for the latest released version and upon execution will import the
##            information into the script.
##
##  Added:
##
##          - Debian OS support for versions, 11 & 12
##          - A browser user-agent string to the curl command
##          - A CPPFLAGS variable to ImageMagick's configure script
##          - A case command to determine the required libtool version based on the active OS
##          - Autotrace for Ubuntu (18/20/22).04 and Debian 10/11
##          - LCMS Support
##          - Deja-Vu Fonts
##          - APT packages
##
##  Fixed:
##          - Incorrect pkg-config location when building ImageMagick
##          - libjxl dependency
##
#############################################################################################################

clear

if [ "$EUID" -eq '0' ]; then
    printf "%s\n\n" 'This script must be run WITHOUT root/sudo'
    exit 1
fi

#
# SET GLOBAL VARIABLES
#

script_ver=4.3
progname="${0}"
cwd="$PWD"/magick-build-script
packages="$cwd"/packages
workspace="$cwd"/workspace
install_dir=/usr/local
user_agent='Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/120.0.0.0 Safari/537.36'
web_repo=https://github.com/slyfox1186/imagemagick-build-script
debug=OFF # CHANGE THIS VARIABLE TO "ON" FOR HELP WITH TROUBLESHOOTING UNEXPECTED ISSUES DURING THE BUILD

#
# CREATE OUTPUT DIRECTORIES
#

mkdir -p "$packages" "$workspace"

#
# FIGURE OUT WHICH COMPILERS TO USE
#

export CC=gcc CXX=g++

#
# SET COMPILER OPTIMIZATION FLAGS
#

CFLAGS="-g -O3 -pipe -march=native -I$workspace/include -I$install_dir/include/CL -I/usr/local/include -I/usr/include"
CFLAGS+=' -I/usr/include/x86_64-linux-gnu -I/usr/include/openjpeg-2.5'
CXXFLAGS='-g -O3 -pipe -march=native'
CPPFLAGS="-I$workspace/include -I$install_dir/include/CL -I/usr/local/include -I/usr/include"
CPPFLAGS+=' -I/usr/include/x86_64-linux-gnu -I/usr/include/openjpeg-2.5'
LDFLAGS="-L$workspace/lib64 -L$workspace/lib -L/usr/local/lib64"
LDFLAGS+=' -L/usr/local/lib -L/usr/lib64 -L/usr/lib -L/lib64 -L/lib'
export CFLAGS CXXFLAGS CPPFLAGS LDFLAGS

#
# SET THE AVAILABLE CPU COUNT FOR PARALLEL PROCESSING (SPEEDS UP THE BUILD PROCESS)
#

if [ -f /proc/cpuinfo ]; then
    cpu_threads="$(grep --count ^processor '/proc/cpuinfo')"
else
    cpu_threads="$(nproc --all)"
fi

#
# SET THE PATH
#

if [ -d '/usr/lib/ccache/bin' ]; then
    ccache_dir='/usr/lib/ccache/bin'
else
    ccache_dir='/usr/lib/ccache'
fi

PATH="\
$ccache_dir:\
$HOME/perl5/bin:\
$HOME/.cargo/bin:\
$HOME/.local/bin:\
/usr/local/sbin:\
/usr/local/bin:\
/usr/sbin:\
/usr/bin:\
/sbin:\
/bin\
"
export PATH

PKG_CONFIG_PATH="\
$workspace/lib64/pkgconfig:\
$workspace/lib/x86_64-linux-gnu/pkgconfig:\
$workspace/lib/pkgconfig:\
$workspace/usr/lib/pkgconfig:\
$workspace/share/pkgconfig:\
/usr/local/ssl/lib64/pkgconfig:\
/usr/local/lib64/pkgconfig:\
/usr/local/lib/pkgconfig:\
/usr/local/lib/x86_64-linux-gnu/pkgconfig:\
/usr/local/share/pkgconfig:\
/usr/lib64/pkgconfig:\
/usr/lib/pkgconfig:\
/usr/lib/x86_64-linux-gnu/pkgconfig:\
/usr/lib/dbus-1.0/debug-build/lib/pkgconfig:\
/usr/share/pkgconfig:\
/lib64/pkgconfig:\
/lib/pkgconfig:\
/snap/core20/2015/usr/share/pkgconfig:\
/snap/certbot/3462/usr/lib/x86_64-linux-gnu/pkgconfig\
"
export PKG_CONFIG_PATH

#
# CREATE FUNCTIONS
#

exit_fn() {
    printf "%s\n\n%s\n%s\n\n" \
        'The script has completed' \
        'Make sure to star this repository to show your support!' \
        "$web_repo"
    exit 0
}

fail_fn() {
    printf "\n\n%s\n\n%s\n\n%s\n\n" \
        "$1" \
        'To report a bug please visit: ' \
        "$web_repo/issues"
    exit 1
}

cleanup_fn() {
    local choice

    printf "\n%s\n\n%s\n%s\n\n" \
        'Do you want to remove the build files?' \
        '[1] Yes' \
        '[2] No'
    read -p 'Your choices are (1 or 2): ' choice

    case "$choice" in
        1)      sudo rm -fr "$cwd";;
        2)      clear;;
        *)
                unset choice
                clear
                cleanup_fn
                ;;
    esac
}

execute() {
    echo "$ ${*}"

    if [ "${debug}" = 'ON' ]; then
        if ! output="$("$@")"; then
            notify-send -t 5000 "Failed to execute: ${*}" 2>/dev/null
            fail_fn "Failed to execute: ${*}"
        fi
    else
        if ! output="$("$@" 2>&1)"; then
            notify-send -t 5000 "Failed to execute: ${*}" 2>/dev/null
            fail_fn "Failed to execute: ${*}"
        fi
    fi
}

build() {
    printf "\n%s\n%s\n" \
        "Building $1 - version $2" \
        '=========================================='

    if [ -f "$packages/$1.done" ]; then
        if grep -Fx "$2" "$packages/$1.done" >/dev/null; then
            echo "$1 version $2 already built. Remove $packages/$1.done lockfile to rebuild it."
            return 1
        fi
    fi
    return 0
}

build_done() { echo "$2" > "$packages/$1.done"; }

get_version_fn() {
    scipt_name="$(basename "${0}")"
    printf "\n%s\n\n%s\n\n" \
        "Script name: $scipt_name" \
        "Script version: $script_ver"
}

download() {
    dl_path="$packages"
    dl_url="$1"
    dl_file="${2:-"${1##*/}"}"

    if [[ "$dl_file" =~ tar. ]]; then
        output_dir="${dl_file%.*}"
        output_dir="${3:-"${output_dir%.*}"}"
    else
        output_dir="${3:-"${dl_file%.*}"}"
    fi

    target_file="$dl_path/$dl_file"
    target_dir="$dl_path/$output_dir"

    if [ -f "$target_file" ]; then
        echo "The file \"$dl_file\" is already downloaded."
    else
        echo "Downloading \"$dl_url\" saving as \"$dl_file\""
        if ! curl -A "$user_agent" -m 10 -Lso "$target_file" "$dl_url"; then
            printf "\n%s\n\n" "The script failed to download \"$dl_file\" and will try again in 10 seconds..."
            sleep 10
            if ! curl -A "$user_agent" -m 10 -Lso "$target_file" "$dl_url"; then
                fail_fn "The script failed to download \"$dl_file\" twice and will now exit. Line: ${LINENO}"
            fi
        fi
        echo 'Download Completed'
    fi

    if [ -d "$target_dir" ]; then
        sudo rm -fr "$target_dir"
    fi

    mkdir -p "$target_dir"

    if [ -n "$3" ]; then
        if ! tar -xf "$target_file" -C "$target_dir" 2>/dev/null >/dev/null; then
            sudo rm "$target_file"
            fail_fn "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script. Line: ${LINENO}"
        fi
    else
        if ! tar -xf "$target_file" -C "$target_dir" --strip-components 1 2>/dev/null >/dev/null; then
            sudo rm "$target_file"
            fail_fn "The script failed to extract \"$dl_file\" so it was deleted. Please re-run the script. Line: ${LINENO}"
        fi
    fi

    printf "%s\n\n" "File extracted: $dl_file"

    cd "$target_dir" || fail_fn "Unable to change the working directory to \"$target_dir\" Line: ${LINENO}"
}

download_git() {
    local dl_path dl_url dl_file target_dir

    dl_path="$packages"
    dl_url="$1"
    dl_file="${2:-"${1##*/}"}"
    dl_file="${dl_file//\./-}"
    target_dir="$dl_path/$dl_file"

    if [[ "$3" == 'R' ]]; then
        set_recurse='--recursive'
    elif [ -n "$3" ]; then
        output_dir="$dl_path/$3"
        target_dir="$output_dir"
    fi

    if [ -d "$target_dir" ]; then
        sudo rm -fr "$target_dir"
    fi

    echo "Downloading $dl_url as $dl_file"

    if ! git clone ${set_recurse} -q "$dl_url" "$target_dir"; then
        printf "\n%s\n\n" "The script failed to clone the directory \"$target_dir\" and will try again in 10 seconds..."
        sleep 10
        if ! git clone ${set_recurse} -q "$dl_url" "$target_dir"; then
            fail_fn "The script failed to clone the directory \"$target_dir\" twice and will now exit the build. Line: ${LINENO}"
        fi
    else
        printf "%s\n\n" "Successfully cloned: $target_dir"
    fi

    cd "$target_dir" || fail_fn "Unable to change the working directory to: $target_dir. Line: ${LINENO}"
}

show_ver_fn() {
    printf "\n%s\n\n" 'ImageMagick'\''s new version is:'
    if ! magick -version 2>/dev/null; then
        fail_fn "Failure to execute the command: magick -version. Line: ${LINENO}"
    else
        sleep 2
    fi
}

git_1_fn() {
    # Initial cnt
    local cnt curl_cmd git_repo git_url
    git_repo="$1"
    git_url="$2"
    cnt=1

    # Loop until the condition is met or a maximum limit is reached
    while [ $cnt -le 10 ]  # You can set an upper limit to prevent an infinite loop
    do
        curl_cmd="$(curl -sSL "https://github.com/$git_repo/$git_url")"

        # Extract the specific line
        line=$(echo "$curl_cmd" | grep -o 'href="[^"]*\.tar\.gz"' | sed -n "${cnt}p")

        # Check if the line matches the pattern (version without 'RC'/'rc')
        if echo "$line" | grep -qoP '(\d+\.\d+\.\d+(-\d+)?)(?=.tar.gz)'; then
            # Extract and print the version number
            g_ver="$(echo "$line" | grep -oP '(\d+\.\d+\.\d+(-\d+)?)(?=.tar.gz)')"
            break
        else
            # Increment the cnt if no match is found
            ((cnt++))
        fi
    done

    # Check if a version was found
    if [ $cnt -gt 10 ]; then
        echo "No matching version found without RC/rc suffix."
    fi
}

git_2_fn() {
    repo="$1"
    if curl_cmd="$(curl -A "$user_agent" -m 10 -sSL "https://gitlab.freedesktop.org/api/v4/projects/${repo}/repository/tags")"; then
        g_ver="$(echo "$curl_cmd" | jq -r '.[0].name')"
    fi
}

git_ver_fn() {
    local t_flag u_flag v_flag v_tag v_url

    v_url="$1"
    v_tag="$2"

    if [ -n "$3" ]; then
        v_flag="$3"
        case "$v_flag" in
                B)      t_flag=branches;;
                R)      t_flag=releases;;
                T)      t_flag=tags;;
                *)      fail_fn "Could not detect the variable \"v_flag\" in the function \"git_ver_fn\". Line: ${LINENO}"
        esac
    fi

    case "$v_tag" in
            1)      u_flag=git_1_fn;;
            2)      u_flag=git_2_fn;;
            *)      fail_fn "Could not detect the variable \"v_tag\" in the function \"git_ver_fn\". Line: ${LINENO}"
    esac

    "$u_flag" "$v_url" "$t_flag" 2>/dev/null
}

installed() { return $(dpkg-query -W -f '${Status}\n' "$1" 2>&1 | awk '/ok installed/{print 0;exit}{print 1}'); }

#
# PRINT THE OPTIONS AVAILABLE WHEN MANUALLY RUNNING THE SCRIPT
#

pkgs_fn() {
    local missing_pkg missing_packages pkg pkgs

    pkgs=(
        "$1" alien asciidoc autoconf autoconf-archive automake autopoint binutils bison
        build-essential cmake curl dbus-x11 flex fontforge gettext gimp-data git gperf
        imagemagick jq libamd2 libbabl-0.1-0 libc6 libc6-dev libcamd2 libccolamd2
        libgegl-common libcholmod3 libcolamd2 libfont-ttf-perl libfreetype-dev libgc-dev
        libgegl-0.4-0 libgimp2.0 libgimp2.0-dev libgl2ps-dev libglib2.0-dev libgraphviz-dev
        libgs-dev libheif-dev libltdl-dev libmetis5 libnotify-bin libnuma-dev libomp-dev
        libpango1.0-dev libpaper-dev libpng-dev libpstoedit-dev libraw-dev librsvg2-dev
        librust-bzip2-dev libsuitesparseconfig5 libtcmalloc-minimal4 libticonv-dev
        libtool libtool-bin libumfpack5 libxml2-dev libzip-dev m4 meson nasm ninja-build
        opencl-c-headers opencl-headers php php-cli pstoedit software-properties-common
        xmlto yasm zlib1g-dev
)

    # Initialize an empty array for missing packages
    missing_packages=()

    # Loop through the array
    for pkg in ${pkgs[@]}
    do
        # Check if the package is installed using dpkg-query
        if ! dpkg-query -W -f='${Status}' "$pkg" 2>/dev/null | grep -q "ok installed"; then
            # If not installed, add it to the missing packages array
            missing_packages+=("$pkg")
        fi
    done

    # Check if there are any missing packages
    if [ "${#missing_packages[@]}" -gt 0 ]; then
        # Install missing packages
        printf "\n%s\n\n" "Installing missing packages: ${missing_packages[*]}"
        sudo apt -y install "${missing_packages[@]}"
    else
        printf "%s\n\n" "All packages are already installed."
    fi
}

install_autotrace_fn() {
    curl -A "$user_agent" -Lso "$packages"/deb-files/autotrace.deb 'https://github.com/autotrace/autotrace/releases/download/travis-20200219.65/autotrace_0.40.0-20200219_all.deb'

    cd "$packages"/deb-files || exit 1

    echo '$ sudo apt -y install ./autotrace.deb'
    if ! sudo apt -y install ./autotrace.deb; then
        sudo dpkg --configure -a
        sudo apt --fix-broken install
        sudo apt update
    fi
}

install_libjxl_fn() {
    cd "$packages"/deb-files || exit 1

    if ! sudo dpkg -i ./libjxl_0.8.2_amd64.deb; then
        sudo dpkg --configure -a
        sudo apt --fix-broken install
        sudo apt update
        sudo dpkg -i ./libjxl_0.8.2_amd64.deb
    else
        sudo rm libjxl_0.8.2_amd64.deb 2>/dev/null
    fi
    sudo dpkg -i ./*.deb
}

dl_libjxl_fn() {
    local url_base url_suffix

    url_base='https://github.com/libjxl/libjxl/releases/download/v0.8.2/jxl-debs-amd64'
    url_suffix='v0.8.2.tar.gz'

    if [ ! -f "$packages"/libjxl.tar.gz ]; then
        case "$VER" in
            12)
                        libjxl_download="$url_base-debian-bookworm-$url_suffix"
                        libjxl_name='debian-bookworm'
                        ;;
            11)
                        libjxl_download="$url_base-debian-bullseye-$url_suffix"
                        libjxl_name='debian-bullseye'
                        ;;
            10)
                        libjxl_download="$url_base-debian-buster-$url_suffix"
                        libjxl_name='debian-buster'
                        ;;
            22.04)
                        libjxl_download="$url_base-ubuntu-22.04-$url_suffix"
                        libjxl_name='ubuntu-22.04'
                        ;;
            20.04)
                        libjxl_download="$url_base-ubuntu-20.04-$url_suffix"
                        libjxl_name='ubuntu-20.04'
                        ;;
            18.04)
                        libjxl_download="$url_base-ubuntu-18.04-$url_suffix"
                        libjxl_name='ubuntu-18.04'
                        ;;
            *)          fail_fn "Unable to determine the OS architecture. Line: ${LINENO}";;
        esac

        # DOWNLOAD THE LIBJXL DEBIAN FILES
        if ! curl -A "$user_agent" -m 10 -Lso "$packages/libjxl-$libjxl_name.tar.gz" "$libjxl_download"; then
            fail_fn "Failed to download the libjxl archive: $packages/libjxl-$libjxl_name.tar.gz. Line: ${LINENO}"
        fi
        # EXTRACT THE DEBIAN FILES FOR INSTALLATION
        if ! tar -zxf "$packages/libjxl-$libjxl_name.tar.gz" -C "$packages"/deb-files --strip-components 1; then
            fail_fn "Could not extract the libjxl archive: $packages/libjxl-$libjxl_name.tar.gz. Line: ${LINENO}"
        fi
        # INSTALL THE DOWNLOADED LIBJXL DEBIAN PACKAGES
        install_libjxl_fn
    fi
}

#
# ANNOUNCE THE BUILD HAS BEGUN
#

box_out_banner_script_header() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 $input_char); do printf '-'; done)
    tput bold
    line="$(tput setaf 3)$line"
    space=${line//-/ }
    echo " $line"
    printf '|' ; echo -n "$space" ; printf "%s\n" '|';
    printf '| ' ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" ' |';
    printf '|' ; echo -n "$space" ; printf "%s\n" '|';
    echo " $line"
    tput sgr 0
}
box_out_banner_script_header "ImageMagick Build Script v$script_ver"

#
# INSTALL APT LIBRARIES
#

printf "\n%s\n%s\n" \
    'Installing required APT packages' \
    '=========================================='

debian_ver_fn() {
    local pkgs_bookworm pkgs_bullseye pkgs_debian

    pkgs_debian='libcpu-features-dev libfontconfig-dev libgc1 libdmalloc-dev libdmalloc5 libjemalloc-dev'
    pkgs_debian+=' libjemalloc2 librust-malloc-buf-dev libyuv-utils libyuv-dev libyuv0 libsharp-dev'
    pkgs_bullseye="$pkgs_debian libvmmalloc1 libvmmalloc-dev"
    pkgs_bookworm+="$pkgs_debian libhwy-dev"

    case "$VER" in
        12)     pkgs_fn "$pkgs_bookworm";;
        11)     pkgs_fn "$pkgs_bullseye";;
        10)     pkgs_fn;;
        *)      fail_fn "Could not detect the Debian version. Line: ${LINENO}";;
    esac
}

ubuntu_ver_fn() {
    local pkgs_jammy pkgs_lunar

    pkgs_focal='libfontconfig1-dev libstdc++-10-dev'
    pkgs_jammy='libhwy-dev libcpu-features-dev libfontconfig-dev libstdc++-12-dev libsdl2-dev'
    pkgs_jammy+=' libgc1 libhwy-dev libmimalloc2.0 libmimalloc-dev'
    pkgs_lunar="$pkgs_jammy librust-jpeg-decoder-dev"

    case "$VER" in
        23.04)     pkgs_fn "$pkgs_lunar";;
        22.04)     pkgs_fn "$pkgs_jammy libhwy0";;
        20.04)     pkgs_fn "$pkgs_focal";;
        18.04)     pkgs_fn;;
        *)         fail_fn "Could not detect the Ubuntu version. Line: ${LINENO}";;
    esac
}

find_lsb_release="$(sudo find /usr -type f -name 'lsb_release')"

if [ -f '/etc/os-release' ]; then
    source '/etc/os-release'
    OS_TMP="$NAME"
    VER_TMP="$VERSION_ID"
    OS="$(echo "$OS_TMP" | awk '{print $1}')"
    VER="$(echo "$VER_TMP" | awk '{print $1}')"
elif [ -n "$find_lsb_release" ]; then
    OS="$(lsb_release -d | awk '{print $2}')"
    VER="$(lsb_release -r | awk '{print $2}')"
else
    fail_fn "Failed to define the \$OS and/or \$VER variables. Line: ${LINENO}"
fi

#
# DISCOVER WHAT VERSION OF LINUX WE ARE RUNNING (DEBIAN OR UBUNTU)
#

case "$OS" in
    Arch)       echo;;
    Debian)     debian_ver_fn;;
    Ubuntu)     ubuntu_ver_fn;;
    *)          fail_fn "Could not detect the OS architecture. Line: ${LINENO}";;
esac

#
# INSTALL OFFICIAL IMAGEMAGICK LIBS
#

git_ver_fn 'imagemagick/imagemagick' '1' 'T'
if build 'magick-libs' "$g_ver"; then
    if [ ! -d "$packages"/deb-files ]; then
        mkdir -p "$packages"/deb-files
    fi
    cd "$packages"/deb-files || exit 1
    if ! curl -A "$user_agent" -m 10 -Lso "magick-libs-$g_ver.rpm" "https://imagemagick.org/archive/linux/CentOS/x86_64/ImageMagick-libs-$g_ver.x86_64.rpm"; then
        fail_fn "Failed to download the magick-libs file. Line: ${LINENO}"
    fi
    sudo alien -d ./*.rpm
    if ! sudo dpkg -i ./*.deb; then
        sudo dpkg --configure -a
        sudo apt --fix-broken install
        sudo apt update
        sudo dpkg -i ./*.deb
    fi
    build_done 'magick-libs' "$g_ver"
fi

#
# INSTALL AUTOTRACE
#

# AUTOTRACE FAILS ON DEBIAN 12
case "$OS" in
    Ubuntu)
                install_autotrace_fn
                autotrace_flag=true
                ;;
esac
if [[ "$autotrace_flag" == 'true' ]]; then
    set_autotrace='--with-autotrace'
else
    set_autotrace='--without-autotrace'
fi

#
# INSTALL COMPOSER TO COMPILE GRAPHVIZ
#

if [ ! -f '/usr/bin/composer' ]; then
    EXPECTED_CHECKSUM="$(php -r 'copy("https://composer.github.io/installer.sig", "php://stdout");')"
    php -r "copy('https://getcomposer.org/installer', 'composer-setup.php');"
    ACTUAL_CHECKSUM="$(php -r "echo hash_file('sha384', 'composer-setup.php');")"

    if [ "$EXPECTED_CHECKSUM" != "$ACTUAL_CHECKSUM" ]; then
        >&2 echo 'ERROR: Invalid installer checksum'
        rm 'composer-setup.php'
        return 1
    fi
    if ! sudo php composer-setup.php --install-dir='/usr/bin' --filename=composer --quiet; then
        fail_fn "Failed to install: /usr/bin/composer. Line: ${LINENO}"
    fi
    rm 'composer-setup.php'
fi

#
# INSTALL LIBJXL FROM DEBIAN FILES
#

if build 'libjxl' '0.8.2'; then
    dl_libjxl_fn
    build_done 'libjxl' '0.8.2'
fi

#
# BEGIN BUILDING FROM SOURCE CODE
#

if build 'm4' 'latest'; then
    download 'https://ftp.gnu.org/gnu/m4/m4-latest.tar.xz'
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" \
                        --disable-nls \
                        --enable-c++ \
                        --enable-threads=posix
    execute make "-j$cpu_threads"
    execute make install
    build_done 'm4' 'latest'
fi

case "$VER" in
    12|23.04)                   lt_ver='2.4.7';;
    10|11|18.04|20.04|22.04)    lt_ver='2.4.6';;
    *)                          fail_fn "Unable to get the OS version. Line: ${LINENO}"
esac

if build 'libtool' "$lt_ver"; then
    download "https://ftp.gnu.org/gnu/libtool/libtool-$lt_ver.tar.xz"
    execute ./configure --prefix="$workspace" \
                        --with-pic \
                        M4="$workspace"/bin/m4
    execute make "-j$cpu_threads"
    execute make install
    build_done 'libtool' "$lt_ver"
fi

git_ver_fn 'libsdl-org/libtiff' '1' 'T'
if build 'libtiff' "$g_ver"; then
    download "https://codeload.github.com/libsdl-org/libtiff/tar.gz/refs/tags/v$g_ver" "libtiff-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --enable-cxx \
                        --with-pic
    execute make "-j$cpu_threads"
    execute make install
    build_done 'libtiff' "$g_ver"
fi

if build 'jpeg-turbo' 'git'; then
    download_git 'https://github.com/imageMagick/jpeg-turbo.git'
    execute cmake -S . \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DENABLE_SHARED=ON \
                  -DENABLE_STATIC=ON \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads"
    execute ninja "-j$cpu_threads" install
    build_done 'jpeg-turbo' 'git'
fi

if build 'libfpx' 'git'; then
    download_git 'https://github.com/imageMagick/libfpx.git'
    execute autoreconf -fi
    execute ./configure --prefix="$workspace" \
                        --with-pic
    execute make "-j$cpu_threads"
    execute make install
    build_done 'libfpx' 'git'
fi

if build 'ghostscript' '10.02.1'; then
    download 'https://github.com/ArtifexSoftware/ghostpdl-downloads/releases/download/gs10021/ghostscript-10.02.1.tar.xz'
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --with-libiconv=native
    execute make "-j$cpu_threads"
    execute make install
    build_done 'ghostscript' '10.02.1'
fi

if build 'png12' '1.2.59'; then
    download 'https://github.com/glennrp/libpng/archive/refs/tags/v1.2.59.tar.gz' 'libpng-1.2.59.tar.gz'
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --with-pic
    execute make "-j$cpu_threads"
    execute make install
    build_done 'png12' '1.2.59'
fi

if build 'libwebp' 'git'; then
    download_git 'https://chromium.googlesource.com/webm/libwebp' 'libwebp-git'
    execute autoreconf -fi
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_SHARED_LIBS=ON \
                  -DZLIB_INCLUDE_DIR=/usr \
                  -DWEBP_BUILD_ANIM_UTILS=OFF \
                  -DWEBP_BUILD_CWEBP=ON \
                  -DWEBP_BUILD_DWEBP=ON \
                  -DWEBP_BUILD_VWEBP=OFF \
                  -DWEBP_BUILD_EXTRAS=OFF \
                  -DWEBP_BUILD_GIF2WEBP=OFF \
                  -DWEBP_BUILD_IMG2WEBP=OFF \
                  -DWEBP_BUILD_LIBWEBPMUX=OFF \
                  -DWEBP_BUILD_WEBPINFO=OFF \
                  -DWEBP_BUILD_WEBPMUX=OFF \
                  -DWEBP_ENABLE_SWAP_16BIT_CSP=OFF \
                  -DWEBP_LINK_STATIC=ON \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done 'libwebp' 'git'
fi

git_ver_fn '7950' '2'
g_ver="${g_ver#VER-}"
g_ver1="${g_ver//-/.}"
if build 'freetype' "$g_ver1"; then
    download "https://gitlab.freedesktop.org/freetype/freetype/-/archive/VER-$g_ver/freetype-VER-$g_ver.tar.bz2" "freetype-$g_ver1.tar.bz2"
    extracmds=('-D'{harfbuzz,png,bzip2,brotli,zlib,tests}'=disabled')
    execute ./autogen.sh
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done 'freetype' "$g_ver1"
fi
ffmpeg_libraries+=('--enable-libfreetype')

git_ver_fn '890' '2'
fc_dir="$packages/fontconfig-$g_ver"
if build 'fontconfig' "$g_ver"; then
    download "https://gitlab.freedesktop.org/fontconfig/fontconfig/-/archive/$g_ver/fontconfig-$g_ver.tar.bz2"
    LDFLAGS+=' -DLIBXML_STATIC'
    sed -i 's|Cflags:|& -DLIBXML_STATIC|' fontconfig.pc.in
    execute ./autogen.sh --noconf
    execute ./configure --prefix="$workspace" \
                        --disable-docbook \
                        --disable-docs \
                        --disable-shared \
                        --disable-nls \
                        --enable-iconv \
                        --enable-libxml2 \
                        --enable-static \
                        --with-arch="$(uname -m)" \
                        --with-libiconv-prefix=/usr \
                        --with-pic
    execute make "-j$cpu_threads"
    execute make install
    build_done 'fontconfig' "$g_ver"
fi

if build 'c2man' 'git'; then
    download_git 'https://github.com/fribidi/c2man.git'
    execute ./Configure -desO \
                        -D bash="$(type -P bash)" \
                        -D bin="$workspace"/bin \
                        -D cc='/usr/bin/cc' \
                        -D d_gnu='/usr/lib/x86_64-linux-gnu' \
                        -D find="$(type -P find)" \
                        -D gcc='/usr/bin/gcc' \
                        -D gzip="$(type -P gzip)" \
                        -D installmansrc="$workspace"/share/man \
                        -D ldflags="$LDFLAGS" \
                        -D less="$(type -P less)" \
                        -D libpth='/lib /usr/lib' \
                        -D locincpth="$workspace/include /usr/local/include /usr/include" \
                        -D loclibpth="$workspace/lib /usr/local/lib" \
                        -D make="$(type -P make)" \
                        -D more="$(type -P more)" \
                        -D osname="$OS" \
                        -D perl="$(type -P perl)" \
                        -D prefix="$workspace" \
                        -D privlib="$workspace"/lib/c2man \
                        -D privlibexp="$workspace"/lib/c2man \
                        -D sleep="$(type -P sleep)" \
                        -D tail="$(type -P tail)" \
                        -D tar="$(type -P tar)" \
                        -D tr="$(type -P tr)" \
                        -D troff="$(type -P troff)" \
                        -D uniq="$(type -P uniq)" \
                        -D uuname="$(uname -s)" \
                        -D vi="$(type -P vi)" \
                        -D yacc="$(type -P yacc)" \
                        -D zip="$(type -P zip)"
    execute make depend
    execute make "-j$cpu_threads"
    execute sudo make install
    build_done 'c2man' 'git'
fi

git_ver_fn 'fribidi/fribidi' '1' 'T'
if build 'fribidi' "$g_ver"; then
    download "https://github.com/fribidi/fribidi/archive/refs/tags/v$g_ver.tar.gz" "fribidi-$g_ver.tar.gz"
    extracommands=('-D'{docs,tests}'=false')
    execute autoreconf -fi
        execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                               "${extracommands[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done 'fribidi' "$g_ver"
fi

git_ver_fn 'harfbuzz/harfbuzz' '1' 'T'
if build 'harfbuzz' "$g_ver"; then
    download "https://github.com/harfbuzz/harfbuzz/archive/refs/tags/$g_ver.tar.gz" "harfbuzz-$g_ver.tar.gz"
    extracmds=('-D'{benchmark,cairo,docs,glib,gobject,icu,introspection,tests}'=disabled')
    execute ./autogen.sh
    execute meson setup build --prefix="$workspace" \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              "${extracmds[@]}"
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done 'harfbuzz' "$g_ver"
fi

git_ver_fn 'host-oman/libraqm' '1' 'T'
if build 'raqm' "$g_ver"; then
    download "https://codeload.github.com/host-oman/libraqm/tar.gz/refs/tags/v$g_ver" "raqm-$g_ver.tar.gz"
    execute meson setup build --prefix="$workspace" \
                              --includedir="$workspace"/include \
                              --buildtype=release \
                              --default-library=static \
                              --strip \
                              -Ddocs=false
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done 'raqm' "$g_ver"
fi

git_ver_fn 'jemalloc/jemalloc' '1' 'T'
if build 'jemalloc' "$g_ver"; then
    download "https://github.com/jemalloc/jemalloc/archive/refs/tags/$g_ver.tar.gz" "jemalloc-$g_ver.tar.gz"
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --disable-debug \
                        --disable-doc \
                        --disable-fill \
                        --disable-log \
                        --disable-prof \
                        --disable-stats \
                        --enable-autogen \
                        --enable-static \
                        --enable-xmalloc
    execute make "-j$cpu_threads"
    execute make install
    build_done 'jemalloc' "$g_ver"
fi

if build 'opencl-sdk' 'git'; then
    download_git 'https://github.com/KhronosGroup/OpenCL-SDK.git' 'opencl-sdk-git' 'R'
    execute cmake \
            -S . \
            -B build \
            -DCMAKE_INSTALL_PREFIX="$workspace" \
            -DCMAKE_BUILD_TYPE=Release \
            -DBUILD_SHARED_LIBS=ON \
            -DBUILD_TESTING=OFF \
            -DBUILD_DOCS=OFF \
            -DBUILD_EXAMPLES=OFF \
            -DOPENCL_SDK_BUILD_SAMPLES=ON \
            -DOPENCL_SDK_TEST_SAMPLES=OFF \
            -DCMAKE_C_FLAGS="$CFLAGS" \
            -DCMAKE_CXX_FLAGS="$CXXFLAGS" \
            -DOPENCL_HEADERS_BUILD_CXX_TESTS=OFF \
            -DOPENCL_ICD_LOADER_BUILD_SHARED_LIBS=ON\
            -DOPENCL_SDK_BUILD_OPENGL_SAMPLES=OFF \
            -DOPENCL_SDK_BUILD_SAMPLES=OFF \
            -DOPENCL_SDK_TEST_SAMPLES=OFF \
            -DTHREADS_PREFER_PTHREAD_FLAG=ON \
            -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done 'opencl-sdk' 'git'
fi

git_ver_fn 'uclouvain/openjpeg' '1' 'T'
if build 'openjpeg' "$g_ver"; then
    download "https://codeload.github.com/uclouvain/openjpeg/tar.gz/refs/tags/v$g_ver" "openjpeg-$g_ver.tar.gz"
    execute cmake -B build \
                  -DCMAKE_INSTALL_PREFIX="$workspace" \
                  -DCMAKE_BUILD_TYPE=Release \
                  -DBUILD_TESTING=OFF \
                  -DBUILD_SHARED_LIBS=ON \
                  -DBUILD_THIRDPARTY=ON \
                  -DCPACK_BINARY_DEB=ON \
                  -DCPACK_BINARY_FREEBSD=ON \
                  -DCPACK_BINARY_IFW=ON \
                  -DCPACK_BINARY_NSIS=ON \
                  -DCPACK_BINARY_RPM=ON \
                  -DCPACK_BINARY_TBZ2=ON \
                  -DCPACK_BINARY_TXZ=ON \
                  -DCPACK_SOURCE_RPM=ON \
                  -DCPACK_SOURCE_ZIP=ON \
                  -DCMAKE_EXPORT_COMPILE_COMMANDS=ON \
                  -G Ninja -Wno-dev
    execute ninja "-j$cpu_threads" -C build
    execute ninja -C build install
    build_done 'openjpeg' "$g_ver"
fi

if build 'lcms' 'git'; then
    download_git 'https://github.com/ImageMagick/lcms.git'
    execute ./autogen.sh
    execute ./configure --prefix="$workspace" \
                        --disable-shared \
                        --with-jpeg="$workspace" \
                        --with-tiff="$workspace" \
                        --with-fastfloat \
                        --with-threaded
    execute make "-j$cpu_threads"
    execute make install
    build_done 'lcms' 'git'
fi

if build 'dejavu-fonts' 'git'; then
    download_git 'https://github.com/dejavu-fonts/dejavu-fonts.git'
    wget -cqU "$user_agent" -P 'resources' 'http://www.unicode.org/Public/UNIDATA/UnicodeData.txt' 'http://www.unicode.org/Public/UNIDATA/Blocks.txt'
    execute ln -sf "$fc_dir"/fc-lang 'resources/fc-lang'
    execute make "-j$cpu_threads" full-ttf
    build_done 'dejavu-fonts' 'git'
fi

#
# BEGIN BUILDING IMAGEMAGICK
#

echo
box_out_banner_magick() {
    input_char=$(echo "$@" | wc -c)
    line=$(for i in $(seq 0 $input_char); do printf '-'; done)
    tput bold
    line="$(tput setaf 3)$line"
    space=${line//-/ }
    echo " $line"
    printf '|' ; echo -n "$space" ; printf "%s\n" '|';
    printf '| ' ;tput setaf 4; echo -n "$@"; tput setaf 3 ; printf "%s\n" ' |';
    printf '|' ; echo -n "$space" ; printf "%s\n" '|';
    echo " $line"
    tput sgr 0
}
box_out_banner_magick 'Build ImageMagick'

# FIND ANY MANUALLY INSTALLED ACLOCAL FOLDERS
aclocal_dir="$(sudo find /usr/ -type d -name 'aclocal' | sort | head -n1)"

git_ver_fn 'ImageMagick/ImageMagick' '1' 'T'
if build 'ImageMagick' '7.1.1-23'; then
    download 'https://github.com/ImageMagick/ImageMagick/archive/refs/tags/7.1.1-23.tar.gz' 'imagemagick-7.1.1-23.tar.gz'
    autoreconf -fi -I "${aclocal_dir}"
    mkdir build
    cd build || exit 1
    ../configure --prefix="$install_dir" \
                 --enable-ccmalloc \
                 --enable-delegate-build \
                 --enable-hdri \
                 --enable-hugepages \
                 --enable-legacy-support \
                 --enable-opencl \
                 --with-dejavu-font-dir=/usr/share/fonts/truetype/dejavu \
                 --with-dmalloc \
                 --with-fontpath=/usr/share/fonts \
                 --with-fpx \
                 --with-gcc-arch=native \
                 --with-gslib \
                 --with-gvc \
                 --with-heic \
                 --with-jemalloc \
                 --with-modules \
                 --with-perl \
                 --with-pic \
                 --with-pkgconfigdir="$workspace"/lib/pkgconfig \
                 --with-quantum-depth=16 \
                 --with-rsvg \
                 --with-tcmalloc \
                 --with-urw-base35-font-dir=/usr/share/fonts/type1/urw-base35 \
                 --with-utilities \
                 "$set_autotrace" \
                 CPPFLAGS="$CPPFLAGS" \
                 CXXFLAGS="$CXXFLAGS" \
                 CFLAGS="$CFLAGS" \
                 LDFLAGS="$LDFLAGS" \
                 PKG_CONFIG="$(type -P pkg-config)"
    execute make "-j$cpu_threads"
    execute sudo make install
fi

# LDCONFIG MUST BE RUN NEXT IN ORDER TO UPDATE FILE CHANGES OR THE MAGICK COMMAND WILL NOT WORK
sudo ldconfig "$install_dir/lib"

# SHOW THE NEWLY INSTALLED MAGICK VERSION
show_ver_fn

# PROMPT THE USER TO CLEAN UP THE BUILD FILES
cleanup_fn

# SHOW EXIT MESSAGE
exit_fn
