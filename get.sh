#!/bin/bash

set -eEo pipefail

required_bin() (
    set -eEo pipefail
    local loc="$(which "$1")"
    if [ "$loc" = "" ]; then
        echo "ERROR: Binary "'"'$1'"'" is required, but not found in PATH"
        exit 1
    fi
)
required_bins() (
    set -eEo pipefail
    for name in "$@"; do 
        required_bin $name
    done
)

download() (
    set -eEo pipefail
    local url="$1"
    local name="$2"
    local download_status=$( curl "$url" -D /dev/stdout -o "$name" -sL | grep -F 'HTTP/' 2>&1 | tail -1 | sed -r "s/^.*HTTP\/[0-9\.]+ ([0-9]+).*$/\1/" )
    echo "$download_status"
)

required_bins curl grep tail sed cat rm mkdir basename

main() {
    set -eEo pipefail

    echo "- Getting the latest Tor version..."
    #local ver=$( cat ver.txt )
    local ver=$( curl "https://dist.torproject.org/torbrowser/" -m 10 2>&1 | grep -E '<a href="[0-9]+\.[0-9]+\.[0-9]+/"' 2>&1 | tail -1 2>&1 | sed -r 's/^.*<a href=\"([0-9]+\.[0-9]+\.[0-9]+)\/\".*/\1/' )
    if [[ "$ver" == "" ]]; then
        echo "Possibly blocked by ISP"
        exit 1
    fi
    if [[ -f ver.txt ]]; then rm ver.txt || exit 1; fi
    echo "$ver" >> ver.txt || exit 1
    export TOR_VER="$ver"
    
    echo "- Downloading Tor latest ($ver) release..."
    if [[ -d downloads ]]; then rm -rf downloads || exit 1; fi
    if [[ ! -d downloads ]]; then mkdir downloads || exit 1; fi
    cd downloads || exit 1
    local names=()
    names+=("tor-browser-android-aarch64-$ver.apk")
    names+=("tor-browser-android-armv7-$ver.apk")
    names+=("tor-browser-android-x86-$ver.apk")
    names+=("tor-browser-android-x86_64-$ver.apk")
    names+=("tor-browser-linux-i686-$ver.tar.xz")
    names+=("tor-browser-linux-x86_64-$ver.tar.xz")
    names+=("tor-browser-macos-$ver.dmg")
    names+=("tor-browser-windows-i686-portable-$ver.exe")
    names+=("tor-browser-windows-x86_64-portable-$ver.exe")
    local names_len=${#names[@]}
    for name in "${names[@]}"; do
        if [[ -f "$name" ]]; then
            echo "  - $name already exists ..."
            continue
        fi
        echo "  - Downloading $name ..."
        local url="https://dist.torproject.org/torbrowser/$ver/$name"
        download_status="$( download "$url" "$name" )"
        if [[ "$download_status" != 200 ]]; then
            echo "ERROR: Wrong respone status code ($download_status), check your internet connection & file ($url) availability"
            exit 1
        fi
    done

    echo "- Get latest Orbot version ..."
    local release_url=$(curl "https://github.com/guardianproject/orbot/releases/latest/" -Ls -o /dev/null -w %{url_effective} 2>&1 )
    local orbot_ver=$(basename "$release_url")
    export ORBOT_VER="$orbot_ver"
    
    echo "- Downloading Orbot latest ($orbot_ver) release..."
    local or_arches=()
    or_arches+=("universal")
    or_arches+=("arm64-v8a")
    for arch in "${or_arches[@]}"; do
        local name="Orbot-$orbot_ver-fullperm-$arch-release.apk"
        if [[ -f "$name" ]]; then
            echo "  - $name already exists ..."
            continue
        fi
        echo "  - Downloading $name ..."
        local url="https://github.com/guardianproject/orbot/releases/download/$orbot_ver/$name"
        download_status="$( download "$url" "$name" )"
        if [[ "$download_status" != 200 ]]; then
            echo "ERROR: Wrong respone status code ($download_status), check your internet connection & file ($url) availability"
            exit 1
        fi
        names+=($name)
        names_len=${#names[@]}
    done

    echo "- Uploading to fotolub ..."
    echo "  - Gettings fotolub cookies ..."
    curl "https://fotolub.com/en" -c cookies.txt -s > /dev/null
    cat cookies.txt
    key=$( cat cookies.txt 2>&1 | grep -F "fileset_id" | sed -r "s/.*fileset_id[ \t]+([a-zA-Z0-9]+).*/\1/g" )
    if [ "${#key}" != 5 ]; then
        echo "fotolub failed to create, key: \"$key\""
        exit 1
    fi
    echo "  - Url: fotolub.com/$key"
    export F_KEY="$key"
    for name in "${names[@]}"; do
        echo "  - Uploading $name ..."
        resp=$(curl -b cookies.txt -X POST -H "X-Requested-With: XMLHttpRequest" -F "file=@$name" "https://fotolub.com/upload.php" -sL)
        ok=$( echo "$resp" | grep -E '"success"\s*:\s*true' )
        if [[ "$ok" == "" ]]; then
            echo "ERROR: Wrong upload respone status ($resp)"
            exit 1
        fi
    done
    rm cookies.txt || exit 1
    cd .. || exit 1
    echo "SUCCESS"
    echo "  - fotulub: fotolub.com/$key"
}

main "$@" || exit 1
