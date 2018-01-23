# Freifunk Weimar Firmware Builder

*Work in Progress* 

Builds Images with Freifunk Firmware :)

This is based on the firmware building code from [Freifunk Berlin](https://github.com/freifunk-berlin/firmware). Most of the documentation also applies here. 



## Images

```
:: Folder Structure

/firmwares/<version>/<target>/<packagelist> 
              ^         ^          ^
              |         |          | weimarnetz         - git master from weimarnetz
              |         |
              |         | ar71xx       - most routers with Atheros SoCs
	      |		| ar71xx-tiny  - 4mb flash modells
              |         | ... 
              |         | x86      - 32bit x86 + vm images
              |         | uml      - user mode linux
              |         | ramips_* - most Mediatek SoCs
              |
              | git describe --always from this repo + OpenWRT revision + shorthash

```

# Development 

How does this stuff work? 

The idea is to download OpenWRT via git, patch it with all patches in the `patches` folder and configure it according to the configuration snippets in `configs`. 
Then use the OpenWRT buildsystem to build all packages and the Imagebuilder and use the latter to assemble the final image with lists of packages in `packages` for the router. 

## Dependencies 

Only tested on Linux. 

```
:: Debian / Ubuntu: 

# apt-get install sudo git subversion build-essential libncurses5-dev zlib1g-dev \
    gawk unzip libxml-perl flex wget gawk libncurses5-dev gettext \ 
    quilt python libssl-dev rsync 
```

## Structure  

Where can I change something? What does these files do? 

```
:: Settings

config.mk             - OpenWRT git repository, revision, select what package lists to build
feeds.conf            - OpenWRT feeds.conf that is used for the package feeds during build

patches/              - Patches against the OpenWRT directory 
packages/             - Package Lists 
profiles/             - List of router profiles for each architecture - names come from the Imagebuilder

:: Building 

Makefile              - Does all the stuff. Cloning and Updating OpenWRT, patching, running make
assemble_firmware.sh  - Script for running the Imagebuilder for a target


:: Images  

firmwares/            - Folder where the final images end up 

```

## Usage 

```
$ git clone https://github.com/weimarnetz/firmware
$ cd firmware
// build all images for ar71xx
// $ make (+OpenWRT build flags i.e. -j$(nproc), V=s ...)
$ make TARGET=ar71xx PKG_LIST=weimarnetz -j$(nproc)
// build all images for 4mb devices 
$ make TARGET=ar71xx-tiny PKG_LIST=weimarnetz
// build for x86
$ make TARGET=x86
// build for ramips_mt7268 
$ make TARGET=ramips_mt7268
// build a different package list
$ make PKG_LIST=weimarnetz_usbtether

find your image in firmwares/xxx/branch/target/... 
...
``` 

### UML 

User Mode Linux is basically a Linux kernel as an ELF-Binary. 

```
$ make TARGET=uml -j$(nproc) 
...
$ cd firmwares/v0.4.1-3-gd598b2d-dirty+lede-r3018-2b84dfa/uml/kalua
$ ./weimarnetz-snapshot-v0.4.1-3-gd598b2d-dirty+lede-r3018-2b84dfa-uml-vmlinux \ 
        ubd0=weimarnetz-snapshot-v0.4.1-3-gd598b2d-dirty+lede-r3018-2b84dfa-uml-ext4.img
        Core dump limits :
	soft - 0
	hard - NONE
Checking that ptrace can change system call numbers...OK
Checking syscall emulation patch for ptrace...OK
Checking advanced syscall emulation patch for ptrace...OK
Checking environment variables for a tempdir...none found
Checking if /dev/shm is on tmpfs...OK
Checking PROT_EXEC mmap in /dev/shm...OK
Adding 17874944 bytes to physical memory to account for exec-shield gap
[    0.000000] Linux version 4.4.42 (riso3860@webis3) (gcc version 5.4.0 20160609 (Ubuntu 5.4.0-6ubuntu1~16.04.4) ) #0 Wed Jan 18 07:54:58 2017
[    0.000000] Built 1 zonelists in Zone order, mobility grouping on.  Total pages: 12384
[    0.000000] Kernel command line: ubd0=weimarnetz-snapshot-v0.4.1-3-gd598b2d-dirty+lede-r3018-2b84dfa-uml-ext4.img root=98:0
``` 

Networking is possible. [Some docs](https://vincent.bernat.im/en/blog/2011-uml-network-lab.html#networking)

### Networking with Ubuntu and NetworkManager 

1. Add `tap0` interface via NetworkManager 

```
$ nmcli connection add type tun ifname tap0 con-name mytap0 \
                        mode tap owner `id -u` ip4 192.168.254.1/24
```

2. Start interface 

```
$ nmcli connection up mytap0
```


3. Setup Forwarding and Masquerading 

```
# sysctl -w net.ipv4.ip_forward=1 
# iptables -t nat -A POSTROUTING -o eth0 -j MASQUERADE
```


4. Install `uml_switch` 

```
# apt install uml-utils
```


5. Start `uml_switch` and use `tap0` for outside connectifity

```
$ uml_switch -tap tap0
```


6. Start UML Image 

```
$ ./weimarnetz-uml ubd0=img eth0=daemon 
```


7. Configure `/etc/config/network` WAN section: 


```
config interface 'wan' 
   option ifname eth0 
   option proto static 
   option ipaddr 192.168.254.100
   option gateway 192.168.254.1
   option netmask 255.255.255.0
```


## Adding a package 

Run a build first and `cd` in the `lede` folder and use `make menuconfig` to the select the package you want. If it's not in the default `feeds.conf` add the package feed for that package. 

Use `./scripts/diffconfig.sh` in the `lede` folder to the symbol for the package or grep for the name in `lede/.config` 

Add the symbol to `configs/common.config` 

i.e. `echo "CONFIG_PACKAGE_tmux=m" >> configs/common.config`

You can now use the package name in the package list file. 

## Adding a new router model to an existing architecture

Everything that is in the [ToH](https://lede-project.org/toh/start) should work at least in theory. Wifi should be ath9k / ath10k. mt76 also appears to work. 

You can use the Imagebuilder to get a list of all supported models for a platform. You can also look in the [source](https://git.lede-project.org/?p=source.git;a=tree;f=target/linux/ar71xx/image) for model names. 

Just put the name in the `/profiles/<target>.profiles` and it should work. 

## Add, modify or delete a patch

In order to add, modify or delete a patch run:

    $ make clean pre-patch

Then switch to the OpenWRT directory:

    $ cd build/lede

Now you can use the quilt commands as described in the [OpenWrt wiki](https://wiki.openwrt.org/doc/devel/patches).

### Refresh Patches 

See: https://wiki.debian.org/UsingQuilt

```
$ cd build/lede 
$ quilt next # forward to patch 
$ quilt push -f 
$ quilt refresh # refresh patch 
```

### Example: add a patch

```
quilt push -a                 # apply all patches
quilt new 008-awesome.patch   # tell quilt to create a new patch
quilt edit somedir/somefile1  # edit files
quilt edit somedir/somefile2
quilt refresh                 # creates/updates the patch file
```

...
