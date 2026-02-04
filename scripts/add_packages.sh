#!/bin/bash

# {{ Add luci-app-diskman
(cd friendlywrt && {
    mkdir -p package/luci-app-diskman
    wget https://raw.githubusercontent.com/lisaac/luci-app-diskman/master/applications/luci-app-diskman/Makefile.old -O package/luci-app-diskman/Makefile
})
cat >> configs/rockchip/01-nanopi <<EOL
CONFIG_PACKAGE_luci-app-diskman=y
CONFIG_PACKAGE_luci-app-diskman_INCLUDE_btrfs_progs=y
CONFIG_PACKAGE_luci-app-diskman_INCLUDE_lsblk=y
CONFIG_PACKAGE_luci-i18n-diskman-zh-cn=y
CONFIG_PACKAGE_smartmontools=y
EOL
# }}

# {{ Add luci-theme-argon
(cd friendlywrt/package && {
    [ -d luci-theme-argon ] && rm -rf luci-theme-argon
    git clone https://github.com/jerrykuku/luci-theme-argon.git --depth 1 -b master
})
echo "CONFIG_PACKAGE_luci-theme-argon=y" >> configs/rockchip/01-nanopi
sed -i -e 's/function init_theme/function old_init_theme/g' friendlywrt/target/linux/rockchip/armv8/base-files/root/setup.sh
cat > /tmp/appendtext.txt <<EOL
function init_theme() {
    if uci get luci.themes.Argon >/dev/null 2>&1; then
        uci set luci.main.mediaurlbase="/luci-static/argon"
        uci commit luci
    fi
}
EOL
sed -i -e '/boardname=/r /tmp/appendtext.txt' friendlywrt/target/linux/rockchip/armv8/base-files/root/setup.sh
# }}

# {{ Add luci-app-lucky
(cd friendlywrt/package && {
    [ -d luci-app-lucky ] && rm -rf luci-app-lucky
    git clone https://github.com/gdy666/luci-app-lucky.git --depth 1
})
cat >> configs/rockchip/01-nanopi <<EOL
CONFIG_PACKAGE_luci-compat=y
CONFIG_PACKAGE_luci-lua-runtime=y
CONFIG_PACKAGE_luci-base=y
CONFIG_PACKAGE_luci-app-lucky=y
EOL
# }}

# {{ Add luci-app-openclash
(cd friendlywrt/package && {
    [ -d OpenClash ] && rm -rf OpenClash
    git clone https://github.com/vernesong/OpenClash.git --depth 1
})
cat >> configs/rockchip/01-nanopi <<EOL
CONFIG_PACKAGE_bash=y
CONFIG_PACKAGE_curl=y
CONFIG_PACKAGE_ruby=y
CONFIG_PACKAGE_ruby-yaml=y
CONFIG_PACKAGE_unzip=y
CONFIG_PACKAGE_luci-app-openclash=y
EOL
# }}

# {{ Add luci-app-nikki
(cd friendlywrt/package && {
    [ -d OpenWrt-nikki ] && rm -rf OpenWrt-nikki
    git clone https://github.com/nikkinikki-org/OpenWrt-nikki --depth 1
})
cat >> configs/rockchip/01-nanopi <<EOL
CONFIG_PACKAGE_luci-app-nikki=y
EOL
# }}

# {{ Add luci-app-nikki
(cd friendlywrt/package && {
    [ -d luci-app-vlmcsd ] && rm -rf luci-app-vlmcsd
    git clone https://github.com/DokiDuck/luci-app-vlmcsd.git --depth 1
})
cat >> configs/rockchip/01-nanopi <<EOL
CONFIG_PACKAGE_luci-app-vlmcsd=y
EOL
# }}

cat >> configs/rockchip/01-nanopi <<EOL
CONFIG_PACKAGE_luci-app-ttyd=y
CONFIG_PACKAGE_luci-app-upnp=y
CONFIG_PACKAGE_luci-app-uhttpd=y

CONFIG_PACKAGE_luci-app-aria2=n
CONFIG_PACKAGE_luci-app-ddns=n
CONFIG_PACKAGE_luci-app-minidlna=n
CONFIG_PACKAGE_luci-app-samba4=n
EOL
