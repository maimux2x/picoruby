#
# libmruby.a will include only mruby/c VM objects.
#
MRuby::Build.new do |conf|

  conf.toolchain

  conf.mrubyc :minimum # or :default

  # conf.cc.defines << "MRBC_ALLOC_LIBC"

end
