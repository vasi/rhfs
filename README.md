rhfs
====
*Ruby tools for manipulating HFS and HFS+ sparsebundles*

[SheepShaver](http://sheepshaver.cebix.net/) and [BasiliskII](http://basilisk.cebix.net/) let you emulate old Macs, and recent versions support Apple's [sparsebundle](http://www.thexlab.com/faqs/sparsebundledefined.html) disk image format. Sparsebundles use less space than raw disk images, but can be harder to manage...until now.

Installation
============
Just clone the repository with git, and run ```./rhfs```

Requirements:
- Ruby 1.9.3 or later. You really need 1.9.3, **1.8.x will not work**
	- On Debian/Ubuntu, run `apt-get install ruby1.9.1`.
	  Yes, this really gives you 1.9.3, not 1.9.1.
	- On OS X, you can use [rvm](https://rvm.io/). Install rvm, then
	  `rvm install 2.0.0` and `rvm use 2.0.0`.
- Ruby gems trollop, bindata, and plist
	- Remember to install them with ruby 1.9 or 2.0, not with 1.8

Usage
=====
Creating a new sparsebundle
---------------------------
**rhfs create [options] SIZE PATH**

The SIZE may use the suffixes K, M, G or T for kilobytes, megabytes, etc. If you want to use Apple's tools with the new image, you should probably name it something.sparsebundle .

Options:
* --band SIZE

  Set the size of each segment of the sparsebundle. The default is 8M. Smaller band sizes mean less wasted space, but may be very slightly slower.

* --format    *(OS X only)*
  
  Create a (non-bootable) HFS+ filesystem on the sparsebundle.

  If you do not use this option, the first time your emulated OS sees the sparsebundle, it will offer to format it for you, and it will be bootable.

* --partition

  Give the new image a partition table, instead of making it just a single volume. SheepShaver and BasiliskII currently can only use the first partition on a disk image, so you probably don't want to do this.


Reclaiming unused space
-----------------------
**rhfs compact [options] PATH**

Sparsebundles automatically grow in size as needed, but they don't automatically shrink when you delete files. This sub-command detects unused space on HFS and HFS+ filesystems, and shrinks the sparsebundle by reclaiming that space.

Options:
* --search

  Searches for space that is full of zeros, and reclaims that too, at the cost of speed. This will even work on non-HFS filesystems, though you'll need some specialized tool to zero out free space before compacting. It is only rarely useful on HFS or HFS+.

* --apple    *(OS X only)*

  Uses Apple's 'hdiutil' utility for reclaiming disk space, instead of our pure-Ruby implementation. This also massages the disk first, to avoid a situation where hdiutil is known to fail.


Converting disk image formats
-----------------------------
**rhfs convert [options] INPUT OUTPUT**

Supports sparsebundles, as well as the other disk format supported by SheepShaver and BasiliskII, a raw byte-for-byte copy of the disk. The input format is auto-detected.

Options:
* --raw
  
  Convert to a raw disk image.

* --sparsebundle

  Convert to a sparsebundle.

* --band SIZE

  Set the band size of the output sparsebundle. The input may be a sparsebundle of a different band size, or any other image.


Accessing files on an HFS+ partition
------------------------------------
**rhfs access [options] IMAGE PATH**

Outputs the content of a single file from an HFS+ sparsebundle. This is probably only useful if you have no other way to mount the filesystem. 

The PATH should use forward slashes as the directory separator, eg: "System/Preferences/My Prefs". Currently this only gets the data fork of the file. It also only works on HFS+, not old HFS.

Options:
* --output OUT

  Send the output to OUT, instead of to standard output.


Getting help
------------
**rhfs help [COMMAND]**

Prints help on any rhfs subcommand. With no argument, prints a list of subcommands.


Related software
================

[SheepShaver](http://sheepshaver.cebix.net/)
-------
Emulator for PowerPC Macs, from Mac OS 7.5 through 9.0. The main motivation for this project. Supports sparsebundles since March 
2013.

[BasiliskII](http://basilisk.cebix.net/)
-------
Emulator for Motorola 680x0 Macs, from System 1 through 8.1. Also supports sparsebundles.

[hdiutil](http://developer.apple.com/library/mac/#documentation/Darwin/Reference/ManPages/man1/hdiutil.1.html)
-------
Apple's utility for managing disk images. It can do many more things than rhfs, including handling a multitude of formats, mounting disk, resizing disks, and more. However, it suffers from some limitations:

* Only runs on Mac OS X.
* Has a bug that prevents compacting certain filesystems, including most HFS+ filesystems that have been used to boot SheepShaver.
* Doesn't make it easy to set band sizes.
* Is closed source.

[sparsebundlefs](https://github.com/torarnv/sparsebundlefs)
-------
Allows sparsebundles to be mounted on Linux, and potentially other OSes, using [FUSE](http://en.wikipedia.org/wiki/Filesystem_in_Userspace).

An example of using sparsebundlefs:
```
# Create a place to mount the bundle and the filesystem
mkdir mnt-bundle mnt-hfs

# Mount the bundle, making sure root can access it
sparsebundlefs -o allow_root test.sparsebundle mnt-bundle

# Scan for partitions in the bundle (if necessary)
sudo kpartx -a mnt-bundle/sparsebundle.dmg

# Mount the HFS+ partition
sudo mount -t hfsplus /dev/loop0p3 mnt-hfs
```

[makesparse](https://github.com/amscanne/makesparse)
-------
Finds areas of zeros in a file, and makes the file sparse. This doesn't require the use of a sparsebundle, it works on raw disk images.

It does require a host filesystem that supports sparse files, like Linux's ext4, but not Mac OS X's HFS+. It also requires some way of zeroing out the unused parts of the disk image, if you want to reclaim space.

[Burn](http://www.gryphel.com/c/sw/sysutils/burn/index.html)
-------
Zeroes out unused disk space, in System 7 through 9. You can run this in an emulator, followed by makesparse in the host. It's much easier to just run ```rhfs compact```, though!

Extras
======
* utils/sparsebundle-compact.c

  A tool to search for zeros in a sparsebundle, and compact it. It is slower than ```rhfs compact``` when rhfs can parse the filesystem, but faster than ```rhfs compact -s```.

* example/hfsplus-list.rb
  
  rhfs includes a Ruby implementation of much of HFS+, though it's incomplete, read-only, and slow. This is a sample program that makes use of this support to list all the files in an HFS+ filesystem.

Licensing
=========
Simplified BSD License
----------------------
rhfs (C) Copyright 2013 Dave Vasilevsky  
All rights reserved.

Redistribution and use in source and binary forms, with or without modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this list of conditions and the following disclaimer.

2. Redistributions in binary form must reproduce the above copyright notice, this list of conditions and the following disclaimer in the documentation and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
