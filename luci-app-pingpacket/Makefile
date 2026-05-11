include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-pingpacket
PKG_VERSION:=1.0.0
PKG_RELEASE:=12
PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Pingpacket
  PKGARCH:=all
  DEPENDS:=+luci-base +luci-lua-runtime +luci-compat +curl
endef

define Package/$(PKG_NAME)/description
 LuCI web interface for Pingpacket monitoring.
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luasrc/controller/pingpacket.lua $(1)/usr/lib/lua/luci/controller/pingpacket.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/pingpacket
	$(INSTALL_DATA) ./luasrc/view/pingpacket/status.htm $(1)/usr/lib/lua/luci/view/pingpacket/status.htm
	$(INSTALL_DATA) ./luasrc/view/pingpacket/logs.htm $(1)/usr/lib/lua/luci/view/pingpacket/logs.htm

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/pingpacket $(1)/etc/init.d/pingpacket

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./root/usr/bin/pingpacket.sh $(1)/usr/bin/pingpacket.sh

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-pingpacket.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-pingpacket.json
endef

define Package/$(PKG_NAME)/postinst
ensure_config_file() { \
	local target="$$1"; \
	[ -f "$$target" ] && return 0; \
	mkdir -p "$$(dirname "$$target")"; \
	printf "%s\n" \
		"config pingpacket 'config'" \
		"	option enabled '0'" \
		"	option domestic_target ''" \
		"	option foreign_target ''" \
		"	option foreign_proxy_type 'socks5'" \
		"	option foreign_proxy_host ''" \
		"	option foreign_proxy_port ''" \
		> "$$target"; \
}; \
if [ -n "$${IPKG_INSTROOT}" ]; then \
	ensure_config_file "$${IPKG_INSTROOT}/etc/config/pingpacket"; \
	exit 0; \
fi; \
[ ! -f /etc/config/pingpacket ] && [ -f /etc/config/pingpacket-opkg ] && mv /etc/config/pingpacket-opkg /etc/config/pingpacket; \
ensure_config_file "/etc/config/pingpacket"; \
if [ -f /etc/config/pingpacket-opkg ]; then \
	rm -f /etc/config/pingpacket-opkg; \
fi; \
changed=0; \
	if [ -z "$$(uci -q get pingpacket.config.domestic_target)" ]; then \
		uci set pingpacket.config.domestic_target='www.baidu.com'; \
		changed=1; \
	fi; \
	if [ -z "$$(uci -q get pingpacket.config.foreign_target)" ]; then \
		uci set pingpacket.config.foreign_target='www.google.com'; \
		changed=1; \
	fi; \
	if [ -z "$$(uci -q get pingpacket.config.foreign_proxy_type)" ]; then \
		uci set pingpacket.config.foreign_proxy_type='socks5'; \
		changed=1; \
	fi; \
	[ "$$changed" = "1" ] && uci commit pingpacket; \
	rm -f /tmp/luci-indexcache.*; \
	rm -rf /tmp/luci-modulecache/; \
	/etc/init.d/rpcd reload 2>/dev/null; \
	exit 0
endef

define Package/$(PKG_NAME)/prerm
[ -n "$${IPKG_INSTROOT}" ] || { \
	[ -f /etc/init.d/pingpacket ] && /bin/sh /etc/init.d/pingpacket disable 2>/dev/null; \
	[ -f /etc/init.d/pingpacket ] && /bin/sh /etc/init.d/pingpacket stop 2>/dev/null; \
	exit 0; \
}
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
