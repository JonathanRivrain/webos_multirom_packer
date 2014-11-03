#!/bin/bash
DEF_ADDR="http://build.webos-ports.org/webos-ports/images/grouper/"
DATE=""
DEF_ROOT="webos-ports-dev-image-grouper.tar.gz"
DEF_ZIMAGE="zImage-grouper.bin"
DEF_INITRD="initramfs-android-image-grouper.cpio.gz"
DEF_MODULES="modules-grouper.tgz"
INIT_PATCH="init.patch"
BLKID="blkid"

ROOT_DEST="zip_root/rom"
ZIP_ROOT="zip_root"
ZIP_DEST="webos_"

function echo_b {
    echo -e "\e[01;34m$1\e[00m"
}

function fail {
    echo -e "\e[01;31mFAILED: $1\e[00m"
    exit 1
}

if [ "$(whoami)" != "root" ] ; then
    echo "This script must be executed with root permissions!"
    exit 1
fi

skip_download=0
for i in $* ; do 
    case $i in
        --help)
            echo "Usage: $0 [options]"
            echo ""
            echo "Options:"
            echo "    --clean          - clean everything"
            echo "    --skip           - skip download"
            exit 0
            ;;
        --clean)
            echo_b "Cleaning working folder..."
            rm -r root
            rm "$ROOT_DEST"/root.tar.gz
            exit 0
            ;;
        --skip)
            skip_download=1
            echo_b "Skipping download..."
            ;;
    esac
done

if [ $skip_download != 1 ] && [ -d "root" ]; then 
    echo_b "Removing old root folder..."
    rm -rf root || fail "Failed to remove old root folder!"
fi

mkdir -p root
cd root

if [ $skip_download != 1 ]; then
    echo_b "Downloading image..."
  curl -L $DEF_ADDR$DEF_ROOT | tar --numeric-owner -xz || fail "Failed to download the image!"

    echo_b "Downloading modules..."
    curl -L $DEF_ADDR$DEF_MODULES | tar --numeric-owner -xz || fail "Failed to download the modules!"

    echo_b "Downloading zImage..."
    curl -L $DEF_ADDR$DEF_ZIMAGE -o "boot/zImage-grouper.bin" || fail "Failed to download zImage!"

    echo_b "Downloading initrd..."
    curl -L $DEF_ADDR$DEF_INITRD -o "boot/initrd.cpio.gz" || fail "Failed to download initrd!"
fi

echo_b "Patching init..."
if [ -d boot/initrd ]; then
    rm -r boot/initrd
fi
mkdir boot/initrd
cd boot/initrd
cp ../initrd.cpio.gz ./
gzip -d initrd.cpio.gz || fail "Failed to unpack initrd (gzip)"
cpio -i < initrd.cpio || fail "Failed to unpack initrd (cpio)"
rm initrd.cpio

# WebOS busybox does not have blkid. Thank god it has traceroute.
cp -a ../../../$BLKID bin/blkid
patch -p1 < ../../../$INIT_PATCH || fail "Failed to patch init!"
(find | sort | cpio --quiet -o -H newc ) | gzip > ../initrd.img || fail "Failed to pack initrd!"
cd ../..
rm -r boot/initrd

echo_b "Creating /var/luna/preferences/ran-first-use..."
mkdir -p var/luna/preferences/
touch var/luna/preferences/ran-first-use

echo_b "Compressing the root..."
if [ -e ../"$ROOT_DEST"/root.tar.gz ] ; then
    rm ../"$ROOT_DEST"/root.tar.gz || fail "Failed to remove old root.tar.gz!"
fi
tar --numeric-owner -zpcf ../"$ROOT_DEST"/root.tar.gz ./* || fail "Failed to compress the root!"

echo_b "Packing installation zip..."
cd "../$ZIP_ROOT" || fail "Failed to cd into ZIP\'s root!"
zip_name="../${ZIP_DEST}$(date +%Y%m%d).mrom"
if [ -r $zip_name ]; then 
    rm $zip_name
fi
zip -0 -r $zip_name ./* || fail "Failed to create final ZIP!"

echo_b "Success!"
