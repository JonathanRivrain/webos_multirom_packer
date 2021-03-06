#!/bin/bash

def_model () {
echo "
  For what device do you want to create the rom ? 
  (choose number)

  1 - a500 (Acer Iconia A500)
  2 - grouper (Asus Nexus 7 2012)
  3 - maguro (Samsung Galaxy Nexus GSM)
  4 - mako (LG Nexus 4)
  0 - Cancel script
"

read device
case $device in 
  1) DEVICE=a500 ;;
  2) DEVICE=grouper ;;
  3) DEVICE=maguro ;;
  4) DEVICE=mako ;;
  0) exit 0 ;;
  *) echo "pick a number between 1 and 4..."
  exit 1 ;;
esac
}

os_variant () {
echo "
What variant of WebOS do you want ?
(choose number)

  1 - webos-ports
  2 - luneos-stable
  0 - Cancel script
  
 "
read variant
case $variant in 
  1) OS_VARIANT=webos-ports ;;
  2) OS_VARIANT=luneos-stable ;;
  0) exit 0 ;;
  *) echo "pick a number between 1 and 2..."
  exit 1 ;;
esac
}

if [ "$(whoami)" != "root" ] ; then
    echo "This script must be executed with root permissions!"
    exit 1
fi
def_model
os_variant


DEF_ADDR="http://build.webos-ports.org/$OS_VARIANT/images/$DEVICE/"
DATE=""
DEF_ROOT="webos-ports-dev-image-$DEVICE.tar.gz"
DEF_ZIMAGE="zImage-$DEVICE.bin"
DEF_INITRD="initramfs-android-image-$DEVICE.cpio.gz"
DEF_MODULES="modules-$DEVICE.tgz"
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
    echo_b "Downloading then upacking root filesystem image..."
    
    wget -c $DEF_ADDR$DEF_ROOT -T 30
    tar xvf $DEF_ROOT --numeric-owner
# was previously curl -L $DEF_ADDR$DEF_ROOT | tar --numeric-owner -xz || fail "Failed to download the image!"
# But it failed every second try with my irregular connexion. wget -c prevents this issue.
    echo_b "Downloading then unpacking modules..."
    wget -c $DEF_ADDR$DEF_MODULES -T 30
    tar xvf $DEF_MODULES --numeric-owner
    
    echo_b "Downloading zImage..."
    wget -c $DEF_ADDR$DEF_ZIMAGE -O "boot/zImage-grouper.bin" -T 30

    echo_b "Downloading initrd..."
    wget -c $DEF_ADDR$DEF_INITRD -O "boot/initrd.cpio.gz" -T 30
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
# I don't think this is still necessary
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
rm $DEF_MODULES $DEF_ROOT
zip -0 -r $zip_name ./* || fail "Failed to create final ZIP!"

echo_b "Success!"
