# Freifunk Weimar Firmware Builder

*Work in Progress* 

Builds Images with Freifunk Firmware :)

This is based on the firmware building code from [Freifunk Berlin](https://github.com/freifunk-berlin/firmware).



## Images

Successful builds end up at http://weimarnetz.segfault.gq/firmwares

```
:: Folder Structure

/firmwares/<version>/<target>/<packagelist> 
              ^         ^          ^
              |         |          | kalua         - git master from weimarnetz
              |         |          | kalua_bittorf - git master from bittorf/kalua
              |         |
              |         | ar71xx - most routers
              |         | ... 
              |         | x86    - 32bit x86 + vm images
              |         | uml    - user mode linux
              |         | 
              |
              | git describe --always from this repo + LEDE revision + shorthash

```

# Development 

How does this stuff work? 

The idea is to download LEDE via git, patch it with all patches in the `patches` folder and configure it according to the configuration snippets in `configs`. 
Then use the LEDE buildsystem to build all packages and the Imagebuilder and use the latter to assemble the final image with lists of packages in `packages` for the router. 

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

config.mk             - LEDE git repository, revision, select what package lists to build
feeds.conf            - LEDE feeds.conf that is used for the package feeds during build

patches               - Patches against the LEDE directory 
packages              - Package Lists 
profiles              - List of router profiles for each architecture - names come from the Imagebuilder

:: Building 

Makefile              - Does all the stuff. Cloning and Updating LEDE, patching, running make
assemble_firmware.sh  - Script for running the Imagebuilder for a target


:: Result 

firmwares             - Folder where the build images end up
```

