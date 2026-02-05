#!/bin/bash

PKG_PATH="$GITHUB_WORKSPACE/wrt/package/"

#预置HomeProxy数据
if [ -d "${PKG_PATH}homeproxy" ] || [ -d "${PKG_PATH}luci-app-homeproxy" ]; then
	HP_RULE="surge"
	HP_PATH="homeproxy/root/etc/homeproxy"

	echo "===== 开始配置 HomeProxy 数据 ====="

	# 确保目录存在
	mkdir -p ./$HP_PATH/resources/

	# 清理现有资源
	rm -rf ./$HP_PATH/resources/*

	echo "正在克隆 surge-rules..."
	if ! git clone -q --depth=1 --single-branch --branch "release" "https://github.com/Loyalsoldier/surge-rules.git" ./$HP_RULE/; then
		echo "克隆 surge-rules 失败，跳过 HomeProxy 数据配置"
	else
		cd ./$HP_RULE/ || { echo "无法进入 surge 目录"; exit 1; }
		RES_VER=$(git log -1 --pretty=format:'%s' | grep -o "[0-9]*" || echo "unknown")
		echo "surge-rules 版本: $RES_VER"

		echo $RES_VER | tee china_ip4.ver china_ip6.ver china_list.ver gfw_list.ver
		awk -F, '/^IP-CIDR,/{print $2 > "china_ip4.txt"} /^IP-CIDR6,/{print $2 > "china_ip6.txt"}' cncidr.txt
		sed 's/^\.//g' direct.txt > china_list.txt ; sed 's/^\.//g' gfw.txt > gfw_list.txt
		
		echo "正在移动资源文件..."
		mv -f ./{china_*,gfw_list}.{ver,txt} ../$HP_PATH/resources/

		cd .. && rm -rf ./$HP_RULE/

		echo "HomeProxy 数据已更新完成！"
	fi
fi

#修改argon主题字体和颜色
ARGON_DIR=$(find ./ -maxdepth 1 -type d -name "*luci-theme-argon*" | head -n 1)
if [ -n "$ARGON_DIR" ] && [ -d "$ARGON_DIR" ]; then
	cd "$ARGON_DIR"

	CSS_FILES=$(find . -type f -iname "*.css" 2>/dev/null)
	if [ -n "$CSS_FILES" ]; then
		for css in $CSS_FILES; do
			sed -i "/font-weight:/ { /important/! { /\/\*/! s/:.*/: var(--font-weight);/ } }" "$css"
		done
	fi
	ARGON_CONFIG=$(find ../  -maxdepth 2 -type f -path "*luci-app-argon-config/root/etc/config/argon" | head -n 1)
	if [ -n "$ARGON_CONFIG" ]; then
		sed -i "s/primary '.*'/primary '#31a1a1'/; s/'0.2'/'0.5'/; s/'none'/'bing'/; s/'600'/'normal'/" "$ARGON_CONFIG"
	fi

	cd $PKG_PATH && echo "theme-argon has been fixed!"
fi

#修改qca-nss-drv启动顺序
NSS_DRV="../feeds/nss_packages/qca-nss-drv/files/qca-nss-drv.init"
if [ -f "$NSS_DRV" ]; then
	sed -i 's/START=.*/START=85/g' $NSS_DRV

	cd $PKG_PATH && echo "qca-nss-drv has been fixed!"
fi

#修改qca-nss-pbuf启动顺序
NSS_PBUF="./kernel/mac80211/files/qca-nss-pbuf.init"
if [ -f "$NSS_PBUF" ]; then
	sed -i 's/START=.*/START=86/g' $NSS_PBUF

	cd $PKG_PATH && echo "qca-nss-pbuf has been fixed!"
fi

#移除Shadowsocks组件
PW_FILE=$(find ./ -maxdepth 3 -type f -wholename "*/luci-app-passwall/Makefile")
if [ -f "$PW_FILE" ]; then
	sed -i '/config PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev/,/x86_64/d' $PW_FILE
	sed -i '/config PACKAGE_$(PKG_NAME)_INCLUDE_ShadowsocksR/,/default n/d' $PW_FILE
	sed -i '/Shadowsocks_NONE/d; /Shadowsocks_Libev/d; /ShadowsocksR/d' $PW_FILE

	cd $PKG_PATH && echo "passwall has been fixed!"
fi

SP_FILE=$(find ./ -maxdepth 3 -type f -wholename "*/luci-app-ssr-plus/Makefile")
if [ -f "$SP_FILE" ]; then
	sed -i '/default PACKAGE_$(PKG_NAME)_INCLUDE_Shadowsocks_Libev/,/libev/d' $SP_FILE
	sed -i '/config PACKAGE_$(PKG_NAME)_INCLUDE_ShadowsocksR/,/x86_64/d' $SP_FILE
	sed -i '/Shadowsocks_NONE/d; /Shadowsocks_Libev/d; /ShadowsocksR/d' $SP_FILE

	cd $PKG_PATH && echo "ssr-plus has been fixed!"
fi

#修复TailScale配置文件冲突
TS_FILE=$(find ../feeds/packages/ -maxdepth 3 -type f -wholename "*/tailscale/Makefile")
if [ -f "$TS_FILE" ]; then
	sed -i '/\/files/d' $TS_FILE

	cd $PKG_PATH && echo "tailscale has been fixed!"
fi

#修复Coremark编译失败
CM_FILE=$(find ../feeds/packages/ -maxdepth 3 -type f -wholename "*/coremark/Makefile")
if [ -f "$CM_FILE" ]; then
	sed -i 's/mkdir/mkdir -p/g' $CM_FILE

	cd $PKG_PATH && echo "coremark has been fixed!"
fi

#修复vlmcsd编译失败
vlmcsd_dir="$GITHUB_WORKSPACE/wrt/feeds/packages/net/vlmcsd"
vlmcsd_patch_src="$GITHUB_WORKSPACE/Patches/001-fix_compile_with_ccache.patch"
vlmcsd_patch_dest="$vlmcsd_dir/patches"

if [ -d "$vlmcsd_dir" ]; then
	# 检查补丁文件是否存在
	if [ ! -f "$vlmcsd_patch_src" ]; then
		echo "Warning: vlmcsd patch file $vlmcsd_patch_src not found, skipping." >&2
	else
		# 创建目标目录并复制补丁
		mkdir -p "$vlmcsd_patch_dest" || true
		cp -f "$vlmcsd_patch_src" "$vlmcsd_patch_dest" || true
		echo "vlmcsd: Patch copied successfully!"
	fi
else
	echo "Warning: vlmcsd directory $vlmcsd_dir not found, skipping patch."
fi

#为zerotier启用内置控制器
zerotier_dir="$GITHUB_WORKSPACE/wrt/feeds/packages/net/zerotier"
zerotier_patch="$GITHUB_WORKSPACE/Patches/020-zerotier-enable-controller.patch"

if [ -d "$zerotier_dir" ]; then
	echo "===== 为 ZeroTier 启用内置控制器 ====="
	
	# 方法1: 直接修改 Config.in 添加控制器选项
	if ! grep -q "ZEROTIER_ENABLE_CONTROLLER" "$zerotier_dir/Config.in" 2>/dev/null; then
		cat >> "$zerotier_dir/Config.in" << 'EOF'

config ZEROTIER_ENABLE_CONTROLLER
	bool "Enable built-in network controller"
	depends on PACKAGE_zerotier
	default y
	help
	  Enable the built-in ZeroTier network controller.
	  This allows creating and managing ZeroTier networks locally.
EOF
		echo "zerotier: Config.in patched!"
	fi
	
	# 方法2: 修改 Makefile 添加 ZT_CONTROLLER 编译选项
	if ! grep -q "ZT_CONTROLLER=1" "$zerotier_dir/Makefile" 2>/dev/null; then
		sed -i '/^MAKE_FLAGS.*ZT_EMBEDDED/,/OSTYPE.*Linux/{
			/OSTYPE.*Linux/a\
\
# Enable built-in network controller\
ifeq ($(CONFIG_ZEROTIER_ENABLE_CONTROLLER),y)\
MAKE_FLAGS += ZT_CONTROLLER=1\
endif
		}' "$zerotier_dir/Makefile"
		echo "zerotier: Makefile patched with ZT_CONTROLLER!"
	fi
	
	echo "zerotier: Built-in controller support enabled!"
else
	echo "Warning: zerotier directory $zerotier_dir not found, skipping controller patch."
fi
