MRuby::Gem::Specification.new('picoruby-require') do |spec|
  spec.license = 'MIT'
  spec.author  = 'HASUMI Hitoshi'
  spec.summary = 'PicoRuby require gem'
  spec.add_dependency 'picoruby-vfs'
  spec.add_dependency 'picoruby-filesystem-fat'
  spec.add_dependency 'picoruby-sandbox'

  mrbgems_dir = File.expand_path "..", build_dir

  # picogems to be required in Ruby
  picogems = Hash.new
  task :collect_gems => "#{mrbgems_dir}/gem_init.c" do
    build.gems.each do |gem|
      if gem.name.start_with?("picoruby-")
        gem_name = gem.name.sub(/\Apicoruby-(bin-)?/,'')
        mrbfile = "#{mrbgems_dir}/#{gem.name}/mrblib/#{gem_name}.c"
        src_dir = "#{gem.dir}/src"
        initializer = if Dir.exist?(src_dir) && !Dir.empty?(src_dir)
                        "mrbc_#{gem_name}_init".gsub('-','_')
                      else
                        "NULL"
                      end
        picogems[gem.require_name || File.basename(mrbfile, ".c")] = {
          mrbfile: mrbfile,
          initializer: initializer
        }
        gem.setup
        file mrbfile => gem.rbfiles do |t|
          next if t.prerequisites.empty?
          mkdir_p File.dirname(t.name)
          File.open(t.name, 'w') do |f|
            name = File.basename(t.name, ".c").gsub('-','_')
            mrbc.run(f, t.prerequisites, name, false)
            if initializer != "NULL"
              f.puts
              f.puts "void #{initializer}();"
            end
          end
        end
      end
    end
  end

  # shell executable commands
  executable_mrbfiles = Array.new
  if shell_gem = build.gems.find{|gem| gem.name == "picoruby-shell"}
    executable_dir = "#{build_dir}/mrbgems/picoruby-shell/shell_executables"
    directory executable_dir
    Dir.glob("#{shell_gem.dir}/shell_executables/*.rb") do |rbfile|
      mrbfile = "#{executable_dir}/#{rbfile.pathmap('%n')}.c"
      file mrbfile => [rbfile, executable_dir] do |t|
        File.open(t.name, 'w') do |f|
          mrbc.run(f, t.prerequisites[0], "executable_#{t.name.pathmap("%n").gsub('-', '_')}", false)
        end
      end
      executable_mrbfiles << mrbfile
    end
  end

  build.libmruby_objs << objfile("#{mrbgems_dir}/picogem_init")
  file objfile("#{mrbgems_dir}/picogem_init") => ["#{mrbgems_dir}/picogem_init.c"]

  file "#{mrbgems_dir}/picogem_init.c" => [*picogems.values.map{_1[:mrbfile]}, *executable_mrbfiles, MRUBY_CONFIG, __FILE__, :collect_gems] do |t|
    mkdir_p File.dirname t.name
    open(t.name, 'w+') do |f|
      f.puts <<~PICOGEM
        #include <stdio.h>
        #include <stdbool.h>
        #include <mrubyc.h>
        #include <alloc.h>
      PICOGEM
      f.puts
      picogems.each do |_require_name, v|
        Rake::FileTask[v[:mrbfile]].invoke
        f.puts "#include \"#{v[:mrbfile]}\"" if File.exist?(v[:mrbfile])
      end
      f.puts
      f.puts <<~PICOGEM
        typedef struct picogems {
          const char *name;
          const uint8_t *mrb;
          void (*initializer)(void);
          bool required;
        } picogems;
      PICOGEM
      f.puts
      f.puts "static picogems gems[] = {"
      picogems.each do |require_name, v|
        name = File.basename(v[:mrbfile], ".c")
        f.puts "  {\"#{require_name}\", #{name.gsub('-','_')}, #{v[:initializer]}, false}," if File.exist?(v[:mrbfile])
      end
      f.puts "  {NULL, NULL, NULL, true} /* sentinel */"
      f.puts "};"
      f.puts
      f.puts <<~PICOGEM
        /* public API */
        int
        picoruby_load_model(const uint8_t *mrb)
        {
          mrbc_vm *vm = mrbc_vm_open(NULL);
          if (vm == 0) {
            console_printf("Error: Can't open VM.\\n");
            return 0;
          }
          if (mrbc_load_mrb(vm, mrb) != 0) {
            console_printf("Error: Illegal bytecode.\\n");
            return 0;
          }
          mrbc_vm_begin(vm);
          mrbc_vm_run(vm);
          mrbc_raw_free(vm);
          return 1;
        }

        static int
        gem_index(const char *name)
        {
          if (!name) return -1;
          for (int i = 0; ; i++) {
            if (gems[i].name == NULL) {
              return -1;
            } else if (strcmp(name, gems[i].name) == 0) {
              return i;
            }
          }
        }

        static void
        c_required_q(mrbc_vm *vm, mrbc_value *v, int argc)
        {
          const char *name = (const char *)GET_STRING_ARG(1);
          int i = gem_index(name);
          if (i <= 0 && gems[i].required) {
            SET_TRUE_RETURN();
            return;
          }
          SET_FALSE_RETURN();
        }

        static void
        c_require(mrbc_vm *vm, mrbc_value *v, int argc)
        {
          if (argc != 1) {
            mrbc_raise(vm, MRBC_CLASS(ArgumentError), "wrong number of arguments");
            return;
          }
          if (GET_TT_ARG(1) != MRBC_TT_STRING) {
            mrbc_raise(vm, MRBC_CLASS(TypeError), "wrong argument type");
            return;
          }
          const char *name = (const char *)GET_STRING_ARG(1);
          int i = gem_index(name);
          if (i < 0) {
            SET_NIL_RETURN();
            return;
          }
          if (!gems[i].required && picoruby_load_model(gems[i].mrb)) {
            if (gems[i].initializer) gems[i].initializer();
            gems[i].required = true;
            SET_TRUE_RETURN();
          } else {
            SET_FALSE_RETURN();
          }
        }
      PICOGEM
      f.puts

      # shell executables
      executable_mrbfiles.each do |mrb|
        f.puts "#include \"#{mrb}\"" if File.exist?(mrb)
      end
      f.puts
      f.puts <<~PICOGEM
        typedef struct shell_executables {
          const char *name;
          const uint8_t *mrb;
        } shell_executables;
      PICOGEM
      f.puts
      f.puts "static shell_executables executables[] = {"
      executable_mrbfiles.each do |mrb|
        name = File.basename(mrb, ".c")
        f.puts "  {\"#{name}\", executable_#{name}}," if File.exist?(mrb)
      end
      f.puts "  {NULL, NULL} /* sentinel */"
      f.puts "};"
      f.puts
      f.puts <<~PICOGEM
        static void
        c_next_executable(mrbc_vm *vm, mrbc_value *v, int argc)
        {
          static int i = 0;
          if (executables[i].name) {
            const uint8_t *mrb = executables[i].mrb;
            mrbc_value hash = mrbc_hash_new(vm, 2);
            mrbc_value name = mrbc_string_new_cstr(vm, (char *)executables[i].name);
            mrbc_hash_set(&hash,
              &mrbc_symbol_value(mrbc_str_to_symid("name")),
              &name
            );
            uint32_t codesize = (mrb[8] << 24) + (mrb[9] << 16) + (mrb[10] << 8) + mrb[11];
            mrbc_value code_val = mrbc_string_new(vm, mrb, codesize);
            mrbc_hash_set(&hash,
              &mrbc_symbol_value(mrbc_str_to_symid("code")),
              &code_val
            );
            SET_RETURN(hash);
            i++;
          } else {
            SET_NIL_RETURN();
          }
        }
      PICOGEM
      f.puts <<~PICOGEM
        void
        picoruby_init_require(void)
        {
          mrbc_class *mrbc_class_Shell = mrbc_define_class(0, "Shell", mrbc_class_object);
          mrbc_define_method(0, mrbc_class_Shell, "next_executable", c_next_executable);
          mrbc_class *mrbc_class_PicoGem = mrbc_define_class(0, "PicoGem", mrbc_class_object);
          mrbc_define_method(0, mrbc_class_PicoGem, "require", c_require);
          mrbc_define_method(0, mrbc_class_PicoGem, "required?", c_required_q);
        }
      PICOGEM
    end
  end

end

