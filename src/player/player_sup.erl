-module(player_sup).
-behaviour(supervisor).

-include("common.hrl").

-export([start_link/0, init/1]).
-export([start_player/2]).

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
    SupFlags = #{
        strategy => simple_one_for_one,
        intensity => 100,
        period => 10
    },
    ChildSpec = #{
        id => player,
        start => {player, start_link, []},
        restart => temporary,
        shutdown => 5000,
        type => worker,
        modules => [player]
    },
    {ok, {SupFlags, [ChildSpec]}}.

start_player(Name, GatewayPid) ->
    supervisor:start_child(?MODULE, [Name, GatewayPid]).
