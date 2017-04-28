#!/bin/bash
#
# mkliwixi.sh: generate a liwixi .zip archive that users can unzip to
# a factory-fresh vfat-formatted SD card.  That card will boot directly
# on the Raspberry Pi.
#
# (C) John Brzustowski
#
# Info:   https://github.com/jbrzusto/liwixi
#
# License: CC BY-SA  or  GPL  or  MIT

BRAND=$1
DEST=$2
TEMP=$3
if [[ -z "$TEMP" ]]; then
    TEMP=$DEST
fi

if [[ -z "$DEST" || ! -z "$4" ]]; then
    cat <<EOF
Usage:

   mkliwixi.sh BRAND DEST [TEMP]

create a .zip archive with a bootable linux image and associated
files that a user can copy to a VFAT SD card to boot a Raspberry Pi.
The file will be called $DEST/${BRAND}_LIWIXI.ZIP

BRAND: a string identifying your linux distribution, however you wish
       to do so.  Use embedded whitespace at your own risk.

DEST: the path to a directory which will hold the archive.  It must
      be large enough to store the compressed archive containing
      image and boot files.

TEMP: temporary storage large enough to store the uncompressed image
      and boot files

EOF
    exit 1;
fi
export BRAND=COOLSTUFF

# We make the image the same size as *used* by the current root file system,
# with an additional 25% to accomodate logfile growth etc.

export IMAGE_MB=$(( `df -BM --output=used / | tail -1l | tr -d 'M'` * 5 / 4))

echo "This image will occupy $IMAGE_MB MB.\n"
echo "Hit enter to continue, or Ctrl-C to quit and do something else..."

read _ignore_

# generate an initramfs in $TEMP

export INITRAMFS=${BRAND}_LIWIXI_INITRAMFS_DO_NOT_DELETE
sudo mkinitramfs -o $TEMP/$INITRAMFS

# generate the image file in $TEMP

export IMAGE_FILENAME=${BRAND}_LIWIXI_IMAGE_DO_NOT_DELETE
dd if=/dev/zero count=1 size=$IMAGE_MB of=$TEMP/$IMAGE_FILENAME
LOOPDEV=`losetup -f`
losetup $LOOPDEV $TEMP/$IMAGE_FILENAME
mkfs -t ext4 $LOOPDEV
mkdir /tmp/$IMAGE_FILENAME
export IMAGE_MOUNT_POINT=/tmp/$IMAGE_FILENAME
mount $LOOPDEV $IMAGE_MOUNT_POINT
rsync -av --exclude /proc/** --exclude /sys/** --exclude /var/run/** \
          --exclude /tmp/** --exclude /boot/** --exclude /media/**   \
          --exclude /mnt/** --exclude /run/**                        \
          / $IMAGE_MOUNT_POINT

# fix the fstab entry for the root device

sed -i -e '/ \/ /s/^[^ ]*/\/dev\/loop0/' $IMAGE_MOUNT_POINT/etc/fstab

echo "You should verify that the new etc/fstab"
echo "shows /dev/loop0 as the device on which '/' is mounted"
echo "Here's the new fstab:"
echo
cat  $IMAGE_MOUNT_POINT/etc/fstab
echo
echo "Hit enter to continue, or Ctrl-C to quit and fix this script..."

read _ignore_

echo "Okay, proceeding to create the .zip archive"

# unmount the image
umount $IMAGE_MOUNT_POINT
losetup -d $LOOPDEV

# add a line to config.txt in temporary storage so that it loads the
# initramfs

cp /boot/config.txt $TEMP/
echo "initramfs $INITRAMFS" >> $/TEMP/config.txt

# change the kernel command line in cmdline.txt on temporary storage
# so it uses the new image as its root filesystem

cat /boot/cmdline.txt | sed -e 's/ root=[^ ]+ / root=/dev/loop0 /' > $TEMP/cmdline.txt

# create the liwixi archive (I'm using zip; you're of course free to use a
# better program to create a smaller archive if you are willing to teach
# your users how to extract it!)

export ARCHIVE=${BRAND}_LIWIXI.ZIP
## copy files from the /boot directory, except for cmdline.txt and config.txt
## for which we already have modified copies in $TEMP

pushd /boot
zip -r ${DEST}/$ARCHIVE * -x ${ARCHIVE} -x cmdline.txt -x config.txt
cd $TEMP
zip -m ${DEST}/$ARCHIVE * -x ${ARCHIVE}
popd

echo Done:
ls -al ${DEST}/$ARCHIVE
