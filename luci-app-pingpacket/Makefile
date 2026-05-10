include $(TOPDIR)/rules.mk

PKG_NAME:=luci-app-pingpacket
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=Apache-2.0

include $(INCLUDE_DIR)/package.mk

define Package/$(PKG_NAME)
  SECTION:=luci
  CATEGORY:=LuCI
  SUBMENU:=3. Applications
  TITLE:=Ping Packet Loss Monitor
  PKGARCH:=all
  DEPENDS:=+luci-base +luci-lua-runtime +luci-compat
endef

define Package/$(PKG_NAME)/description
 LuCI web interface for monitoring ping latency and packet loss.
endef

define Package/$(PKG_NAME)/conffiles
/etc/config/pingpacket
endef

define Build/Compile
endef

define Package/$(PKG_NAME)/install
	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/controller
	$(INSTALL_DATA) ./luasrc/controller/pingpacket.lua $(1)/usr/lib/lua/luci/controller/pingpacket.lua

	$(INSTALL_DIR) $(1)/usr/lib/lua/luci/view/pingpacket
	$(INSTALL_DATA) ./luasrc/view/pingpacket/status.htm $(1)/usr/lib/lua/luci/view/pingpacket/status.htm

	$(INSTALL_DIR) $(1)/etc/config
	$(INSTALL_DATA) ./root/etc/config/pingpacket $(1)/etc/config/pingpacket

	$(INSTALL_DIR) $(1)/etc/init.d
	$(INSTALL_BIN) ./root/etc/init.d/pingpacket $(1)/etc/init.d/pingpacket

	$(INSTALL_DIR) $(1)/usr/bin
	$(INSTALL_BIN) ./root/usr/bin/pingpacket.sh $(1)/usr/bin/pingpacket.sh

	$(INSTALL_DIR) $(1)/usr/share/rpcd/acl.d
	$(INSTALL_DATA) ./root/usr/share/rpcd/acl.d/luci-app-pingpacket.json \
		$(1)/usr/share/rpcd/acl.d/luci-app-pingpacket.json
endef

define Package/$(PKG_NAME)/postinst
[ -n "$${IPKG_INSTROOT}" ] || { \
	rm -f /tmp/luci-indexcache.*; \
	rm -rf /tmp/luci-modulecache/; \
	/etc/init.d/rpcd reload 2>/dev/null; \
	exit 0; \
}
endef

define Package/$(PKG_NAME)/prerm
[ -n "$${IPKG_INSTROOT}" ] || { \
	[ -f /etc/init.d/pingpacket ] && /bin/sh /etc/init.d/pingpacket disable 2>/dev/null; \
	[ -f /etc/init.d/pingpacket ] && /bin/sh /etc/init.d/pingpacket stop 2>/dev/null; \
	exit 0; \
}
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
