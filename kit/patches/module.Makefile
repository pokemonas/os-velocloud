.PATH:  ${SRCTOP}/sys/dev/vcigb
KMOD    = if_vcigb
SRCS    = device_if.h bus_if.h pci_if.h opt_ddb.h opt_inet.h \
	  opt_inet6.h opt_rss.h ifdi_if.h
SRCS    += if_em.c em_txrx.c e1000_osdep.c igb_txrx.c e1000_vc.c
SRCS    += e1000_api.c e1000_base.c e1000_phy.c e1000_nvm.c e1000_mac.c \
	   e1000_manage.c e1000_vf.c e1000_mbx.c e1000_i210.c \
	   e1000_80003es2lan.c e1000_ich8lan.c e1000_82571.c e1000_82575.c \
	   e1000_82540.c e1000_82542.c e1000_82541.c e1000_82543.c

CFLAGS += -I${SRCTOP}/sys/dev/vcigb
# host clang (not FreeBSD base clang) reaches __stack_chk_guard through the
# GOT, which the kernel linker cannot relocate
CFLAGS += -fno-stack-protector
# kernel source commit (12 hex digits, as in "uname -v") the module refuses
# to attach without; set by build-vcigb.sh
.if defined(VCIGB_KERNCOMMIT) && !empty(VCIGB_KERNCOMMIT)
CFLAGS += -DVCIGB_KERNCOMMIT=\"${VCIGB_KERNCOMMIT}\"
.endif

.include <bsd.kmod.mk>
