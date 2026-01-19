#!/bin/bash

#修改默认主题
THEME_FILES=$(find ./feeds/luci/collections/ -type f -name "Makefile" 2>/dev/null)
if [ -n "$THEME_FILES" ]; then
	for f in $THEME_FILES; do
		sed -i "s/luci-theme-bootstrap/luci-theme-$WRT_THEME/g" "$f"
	done
fi
#修改immortalwrt.lan关联IP
FLASH_JS=$(find ./feeds/luci/modules/luci-mod-system/ -type f -name "flash.js" 2>/dev/null)
if [ -n "$FLASH_JS" ]; then
	for f in $FLASH_JS; do
		sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$f"
	done
fi
#添加编译日期标识
SYSTEM_JS=$(find ./feeds/luci/modules/luci-mod-status/ -type f -name "10_system.js" 2>/dev/null)
if [ -n "$SYSTEM_JS" ]; then
	for f in $SYSTEM_JS; do
		sed -i "s/(\(luciversion || ''\))/(\1) + (' \/ $WRT_MARK-$WRT_DATE')/g" "$f"
	done
fi

WIFI_SH=$(find ./target/linux/{mediatek/filogic,qualcommax}/base-files/etc/uci-defaults/ -type f -name "*set-wireless.sh" 2>/dev/null | head -n 1)
WIFI_UC="./package/network/config/wifi-scripts/files/lib/wifi/mac80211.uc"
if [ -n "$WIFI_SH" ] && [ -f "$WIFI_SH" ]; then
	#修改WIFI名称
	sed -i "s/BASE_SSID='.*'/BASE_SSID='$WRT_SSID'/g" $WIFI_SH
	#修改WIFI密码
	sed -i "s/BASE_WORD='.*'/BASE_WORD='$WRT_WORD'/g" $WIFI_SH
elif [ -f "$WIFI_UC" ]; then
	#修改WIFI名称
	sed -i "s/ssid='.*'/ssid='$WRT_SSID'/g" $WIFI_UC
	#修改WIFI密码
	sed -i "s/key='.*'/key='$WRT_WORD'/g" $WIFI_UC
	#修改WIFI地区
	sed -i "s/country='.*'/country='CN'/g" $WIFI_UC
	#修改WIFI加密
	sed -i "s/encryption='.*'/encryption='psk2+ccmp'/g" $WIFI_UC
fi

CFG_FILE="./package/base-files/files/bin/config_generate"
if [ -f "$CFG_FILE" ]; then
	#修改默认IP地址
	sed -i "s/192\.168\.[0-9]*\.[0-9]*/$WRT_IP/g" "$CFG_FILE"
	#修改默认主机名
	sed -i "s/hostname='.*'/hostname='$WRT_NAME'/g" "$CFG_FILE"
else
	echo "Warning: config_generate not found, skipping IP and hostname modification."
fi

#配置文件修改
echo "CONFIG_PACKAGE_luci=y" >> ./.config
echo "CONFIG_LUCI_LANG_zh_Hans=y" >> ./.config
echo "CONFIG_PACKAGE_luci-theme-$WRT_THEME=y" >> ./.config
echo "CONFIG_PACKAGE_luci-app-$WRT_THEME-config=y" >> ./.config

# 若启用了 luci-app-frpc / luci-app-frps，确保核心 frpc / frps 包也被选中，
# 避免因为依赖未显式选中在 defconfig 阶段被裁减。
grep -q '^CONFIG_PACKAGE_luci-app-frpc=y' ./.config && {
	grep -q '^CONFIG_PACKAGE_frpc=y' ./.config || echo 'CONFIG_PACKAGE_frpc=y' >> ./.config
}
grep -q '^CONFIG_PACKAGE_luci-app-frps=y' ./.config && {
	grep -q '^CONFIG_PACKAGE_frps=y' ./.config || echo 'CONFIG_PACKAGE_frps=y' >> ./.config
}

# 修复 luci-app-frpc/frps 与上游 frpc/frps 包的文件冲突
# 问题：两者都包含 /etc/config/frpc 和 /etc/init.d/frpc，导致 opkg 安装失败
# 解决：删除上游 frpc/frps 包中的冲突文件定义，让 luci-app 版本优先
# 注意：上游 frp 包使用模板定义，frpc 和 frps 都在同一个 Makefile 中
FRP_PACKAGES_PATH="./feeds/packages/net"
# 首先尝试统一的 frp 目录（OpenWrt/immortalwrt 结构）
if [ -d "$FRP_PACKAGES_PATH/frp" ]; then
	FRP_MAKEFILE="$FRP_PACKAGES_PATH/frp/Makefile"
	if [ -f "$FRP_MAKEFILE" ]; then
		# 上游使用模板: $(INSTALL_CONF) ./files/$(2).config $(1)/etc/config/$(2)
		# 需要注释掉配置文件和 init 脚本的安装行
		sed -i 's|\$(INSTALL_CONF) \./files/\$(2)\.config \$(1)/etc/config/\$(2)|# Removed: conflicts with luci-app-frpc/frps|g' "$FRP_MAKEFILE"
		sed -i 's|\$(INSTALL_BIN) \./files/\$(2)\.init \$(1)/etc/init\.d/\$(2)|# Removed: conflicts with luci-app-frpc/frps|g' "$FRP_MAKEFILE"
		echo "frp: Removed conflicting config/init files from upstream package"
	fi
fi
# 备选：检查分离的 frpc/frps 目录（某些分支可能使用此结构）
if [ -d "$FRP_PACKAGES_PATH/frpc" ]; then
	FRP_MAKEFILE="$FRP_PACKAGES_PATH/frpc/Makefile"
	if [ -f "$FRP_MAKEFILE" ]; then
		sed -i 's|\$(INSTALL_CONF).*etc/config/frpc|# Removed: conflicts with luci-app-frpc|g' "$FRP_MAKEFILE"
		sed -i 's|\$(INSTALL_BIN).*etc/init\.d/frpc|# Removed: conflicts with luci-app-frpc|g' "$FRP_MAKEFILE"
		echo "frpc: Removed conflicting config/init files from upstream package"
	fi
fi
if [ -d "$FRP_PACKAGES_PATH/frps" ]; then
	FRP_MAKEFILE="$FRP_PACKAGES_PATH/frps/Makefile"
	if [ -f "$FRP_MAKEFILE" ]; then
		sed -i 's|\$(INSTALL_CONF).*etc/config/frps|# Removed: conflicts with luci-app-frps|g' "$FRP_MAKEFILE"
		sed -i 's|\$(INSTALL_BIN).*etc/init\.d/frps|# Removed: conflicts with luci-app-frps|g' "$FRP_MAKEFILE"
		echo "frps: Removed conflicting config/init files from upstream package"
	fi
fi

#手动调整的插件
if [ -n "$WRT_PACKAGE" ]; then
	echo -e "$WRT_PACKAGE" >> ./.config
fi

#高通平台调整
DTS_PATH="./target/linux/qualcommax/files/arch/arm64/boot/dts/qcom/"
if [[ "${WRT_TARGET^^}" == *"QUALCOMMAX"* ]]; then
	#启用nss相关feed
	echo "CONFIG_FEED_nss_packages=y" >> ./.config
	echo "CONFIG_FEED_sqm_scripts_nss=y" >> ./.config
	#开启sqm-nss插件
	echo "CONFIG_PACKAGE_luci-app-sqm=y" >> ./.config
	echo "CONFIG_PACKAGE_sqm-scripts-nss=y" >> ./.config
	#设置NSS版本
	echo "CONFIG_NSS_FIRMWARE_VERSION_11_4=n" >> ./.config
	if [[ "${WRT_CONFIG,,}" == *"ipq50"* ]]; then
		echo "CONFIG_NSS_FIRMWARE_VERSION_12_2=y" >> ./.config
	else
		echo "CONFIG_NSS_FIRMWARE_VERSION_12_5=y" >> ./.config
	fi
	#无WIFI配置调整Q6大小
	if [[ "${WRT_CONFIG,,}" == *"wifi"* && "${WRT_CONFIG,,}" == *"no"* ]]; then
		if [ -d "$DTS_PATH" ]; then
			find "$DTS_PATH" -type f ! -iname '*nowifi*' -exec sed -i 's/ipq\(6018\|8074\).dtsi/ipq\1-nowifi.dtsi/g' {} +
			echo "qualcommax set up nowifi successfully!"
		else
			echo "Warning: DTS path $DTS_PATH not found, skipping nowifi setup."
		fi
	fi
fi
