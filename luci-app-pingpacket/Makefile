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

	$(CP) ./root/* $(1)/
endef

define Package/$(PKG_NAME)/postinst
[ -n "$${IPKG_INSTROOT}" ] || { \
	rm -f /tmp/luci-indexcache.*; \
	rm -rf /tmp/luci-modulecache/; \
	/etc/init.d/rpcd reload 2>/dev/null; \
	exit 0; \
}
endef

$(eval $(call BuildPackage,$(PKG_NAME)))
