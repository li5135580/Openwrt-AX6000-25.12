include $(TOPDIR)/rules.mk

LUCI_TITLE:=GitHub Releases 在线升级
LUCI_DEPENDS:=+luci-lua-runtime +curl +ca-bundle
LUCI_PKGARCH:=all

PKG_NAME:=luci-app-github-updater
PKG_VERSION:=1.0.0
PKG_RELEASE:=1
PKG_LICENSE:=MIT
PKG_MAINTAINER:=li5135580

include $(TOPDIR)/feeds/luci/luci.mk

# call BuildPackage - OpenWrt buildroot signature
