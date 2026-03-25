-module(system_sup).
-behaviour(supervisor).

-include("game.hrl").

-export([start_link/0, init/1]).
-export([system_status/0]).


%% 获取系统状态
system_status() ->
    [{supervisor, ?MODULE},
     {children, supervisor:which_children(?MODULE)},
     {memory, erlang:memory()},
     {process_count, erlang:system_info(process_count)}].

start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

init([]) ->
	ets:new(?assetsCache, [set, named_table, public, {read_concurrency, true}]),
    SupFlags = #{
        strategy => one_for_one,
        intensity => 10,
        period => 60
    },
    
    Children = [
        #{
            id => room_manager,
            start => {room_manager, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [room_manager]
        },
        #{
            id => score_system,
            start => {score_system, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => worker,
            modules => [score_system]
        },
        #{
            id => ai_supervisor,
            start => {ai_supervisor, start_link, []},
            restart => permanent,
            shutdown => 5000,
            type => supervisor,
            modules => [ai_supervisor]
        }
    ],
    
    {ok, {SupFlags, Children}}.