## UNWIND ##

ifneq ($(USE_BINARYBUILDER_LIBUNWIND),1)
UNWIND_OPTS := $(CMAKE_COMMON) -DLIBUNWIND_ENABLE_PEDANTIC=OFF

$(SRCCACHE)/libunwind-$(UNWIND_VER).tar.xz: | $(SRCCACHE)
	$(JLDOWNLOAD) $@ https://github.com/llvm/llvm-project/releases/download/llvmorg-$(UNWIND_VER)/libunwind-$(UNWIND_VER).src.tar.xz

$(SRCCACHE)/libunwind-$(UNWIND_VER)/source-extracted: $(SRCCACHE)/libunwind-$(UNWIND_VER).tar.xz
	$(JLCHECKSUM) $<
	cd $(dir $<) && $(TAR) xf $<
	mv $(SRCCACHE)/libunwind-$(UNWIND_VER).src $(SRCCACHE)/libunwind-$(UNWIND_VER)
	echo 1 > $@

checksum-libunwind: $(SRCCACHE)/libunwind-$(UNWIND_VER).tar.xz
	$(JLCHECKSUM) $<

$(BUILDDIR)/libunwind-$(UNWIND_VER)/build-configured: $(SRCCACHE)/libunwind-$(UNWIND_VER)/source-extracted
	mkdir -p $(dir $@)
	cd $(dir $@) && \
	$(CMAKE) $(dir $<) $(UNWIND_OPTS)
	echo 1 > $@

$(BUILDDIR)/libunwind-$(UNWIND_VER)/build-compiled: $(BUILDDIR)/libunwind-$(UNWIND_VER)/build-configured
	$(MAKE) -C $(dir $<)
	echo 1 > $@

$(eval $(call staged-install, \
	unwind,libunwind-$(UNWIND_VER), \
	MAKE_INSTALL,,,))

clean-libunwind:
	-rm $(BUILDDIR)/libunwind-$(UNWIND_VER)/build-configured $(BUILDDIR)/libunwind-$(UNWIND_VER)/build-compiled
	-$(MAKE) -C $(BUILDDIR)/libunwind-$(UNWIND_VER) clean

distclean-libunwind:
	-rm -rf $(SRCCACHE)/libunwind-$(UNWIND_VER).tar.xz \
		$(SRCCACHE)/libunwind-$(UNWIND_VER) \
		$(BUILDDIR)/libunwind-$(UNWIND_VER)

get-libunwind: $(SRCCACHE)/libunwind-$(UNWIND_VER).tar.xz
extract-libunwind: $(SRCCACHE)/libunwind-$(UNWIND_VER)/source-extracted
configure-libunwind: $(BUILDDIR)/libunwind-$(UNWIND_VER)/build-configured
compile-libunwind: $(BUILDDIR)/libunwind-$(UNWIND_VER)/build-compiled
fastcheck-libunwind: check-libunwind
check-libunwind: # no test/check provided by Makefile

else # USE_BINARYBUILDER_LIBUNWIND

$(eval $(call bb-install,unwind,UNWIND,false))

endif
