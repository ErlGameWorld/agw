-module(playerMgrSrv).
-behaviour(gen_server).

-include("common.hrl").
-include("player.hrl").

-export([start_link/0]).
-export([getOnlineCount/0, getAllPlayers/0, kickPlayer/1, broadcast/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

-record(state, {online_count = 0}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

getOnlineCount() ->
    gen_server:call(?MODULE, eGetOnlineCount).

getAllPlayers() ->
    ets:tab2list(?etsPlayerRegistry).

kickPlayer(Name) ->
    gen_server:cast(?MODULE, {eKickPlayer, Name}).

broadcast(Msg) ->
    gen_server:cast(?MODULE, {eBroadcast, Msg}).

init([]) ->
    process_flag(trap_exit, true),
	ets:new(?etsPlayerRegistry, [set, named_table, public, {keypos, 1}, {read_concurrency, true}]),
    {ok, #state{}}.

handle_call(eGetOnlineCount, _From, State) ->
    Count = ets:info(?etsPlayerRegistry, size),
    {reply, Count, State#state{online_count = Count}};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast({eKickPlayer, Name}, State) ->
    case player:findPlayer(Name) of
        {ok, Pid} ->
            Pid ! eKickByRelogin,
            ?Info("Kick player ~s by GM~n", [Name]);
        not_found ->
            ?Warn("Kick player ~s failed: not found~n", [Name])
    end,
    {noreply, State};

handle_cast({eBroadcast, Msg}, State) ->
    Players = ets:tab2list(?etsPlayerRegistry),
    lists:foreach(fun({_Name, Pid}) ->
        case is_process_alive(Pid) of
            true -> Pid ! {eSendClient, Msg};
            false -> ok
        end
    end, Players),
    {noreply, State};

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
