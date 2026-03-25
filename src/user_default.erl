-module(user_default).

-include("common.hrl").

-export([tlog/0]).

tlog() ->
   ?Warn("verify timeout1111111111"),
   ?Debug("verify timeout222222222"),
   ?Debug("verify timeout333333333", []),
   ?Debug("verify timeout444444444"),


   % ?Warn("verify timeout1 ~p~n", [11]),
   % ?Debug("verify timeout2 ~p~n", [22]),
   % ?Info("verify timeout2 ~p~n", [33]),
   okk.
