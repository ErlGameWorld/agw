-module(gatewaySup).

-behaviour(supervisor).

-export([start_link/2]).
-export([init/1]).

-define(SERVER, ?MODULE).

start_link(ServerName, SimpleMod) ->
	supervisor:start_link({local, ServerName}, ?MODULE, {ServerName, SimpleMod}).

init({ServerName, SimpleMod}) ->
	SupFlags = #{strategy => simple_one_for_one, intensity => 100, period => 3600},
	ChildSpecs = [#{id => {ServerName, SimpleMod}, start => {SimpleMod, start_link, []}, restart => temporary, shutdown => infinity, type => worker, modules => [SimpleMod]}],
	{ok, {SupFlags, ChildSpecs}}.
