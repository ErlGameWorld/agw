set ERL_LIBS=_build/default/lib
erl  -name agwGame@127.0.0.1 -args_file "./config/vm.args" -config "./config/sys.config"