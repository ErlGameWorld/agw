-module(player).
-behaviour(gen_server).

-include("../../include/protoMsg.hrl").
-include("common.hrl").
-include("game.hrl").
-include("player.hrl").

-export([start_link/2, getName/1, getStatistics/1, setGamePid/2, setIndex/2, setRoom/2, getIndex/1, setGatewayPid/2, getGatewayPid/1, stop/1]).
-export([findPlayer/1]).
-export([init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).

findPlayer(Name) ->
	case ets:lookup(?etsPlayerRegistry, Name) of
		[{Name, Pid}] ->
			case is_process_alive(Pid) of
				true -> {ok, Pid};
				false ->
					ets:delete_object(?etsPlayerRegistry, {Name, Pid}),
					not_found
			end;
		[] ->
			not_found
	end.

register_player(Name, Pid) ->
	ets:insert_new(?etsPlayerRegistry, {Name, Pid}).

unregister_player(Name) ->
	ets:delete(?etsPlayerRegistry, Name).

start_link(Name, WsHandlerPid) ->
    gen_server:start_link(?MODULE, [Name, WsHandlerPid], []).

setGatewayPid(PlayerPid, GatewayPid) ->
    try gen_server:call(PlayerPid, {eSetGatewayPid, GatewayPid}, 5000) of
        ok -> ok
    catch
        exit:{timeout, _} -> {error, timeout};
        exit:{noproc, _} -> {error, player_not_found};
        exit:{normal, _} -> {error, player_stopped};
        _:Reason -> {error, Reason}
    end.

getGatewayPid(PlayerPid) ->
    gen_server:call(PlayerPid, eGetGatewayPid).

stop(PlayerPid) ->
    gen_server:stop(PlayerPid).

setGamePid(PlayerPid, GamePid) ->
    gen_server:cast(PlayerPid, {eSetGamePid, GamePid}).

setIndex(PlayerPid, Index) ->
    gen_server:cast(PlayerPid, {eSetIndex, Index}).

setRoom(PlayerPid, RoomId) ->
    gen_server:cast(PlayerPid, {eSetRoom, RoomId}).

getName(PlayerPid) ->
    gen_server:call(PlayerPid, eGetName).

getStatistics(PlayerPid) ->
    gen_server:call(PlayerPid, eGetStatistics).

getIndex(PlayerPid) ->
    gen_server:call(PlayerPid, eGetIndex).

init([Name, WsHandlerPid]) ->
    process_flag(trap_exit, true),
    link(WsHandlerPid),
    case register_player(Name, self()) of
        true ->
            {ok, {Score, Wins, Losses}} = score_system:getScore(Name),
            {ok, #playerState{name = Name, gatewayPid = WsHandlerPid, score = Score, wins = Wins, losses = Losses}};
        false ->
            unlink(WsHandlerPid),
            {stop, {shutdown, {already_registered, Name}}}
    end.

handle_call(eGetName, _From, State) ->
    {reply, {ok, State#playerState.name}, State};
handle_call(eGetStatistics, _From, State) ->
    Stats = {State#playerState.score, State#playerState.wins, State#playerState.losses},
    {reply, {ok, Stats}, State};
handle_call(eGetIndex, _From, State) ->
    {reply, {ok, State#playerState.index}, State};
handle_call(eGetGatewayPid, _From, State) ->
    {reply, {ok, State#playerState.gatewayPid}, State};
handle_call({eSetGatewayPid, NewGatewayPid}, _From, #playerState{gatewayPid = GatewayPid} = State) ->
    case GatewayPid of
        undefined -> 
            link(NewGatewayPid),
            {reply, ok, State#playerState{gatewayPid = NewGatewayPid}};
        OldGatewayPid when OldGatewayPid /= NewGatewayPid ->
            ?Info("Kicking old gateway ~p for player ~s~n", [OldGatewayPid, State#playerState.name]),
            unlink(OldGatewayPid),
            OldGatewayPid ! eKickByRelogin,
            link(NewGatewayPid),
			utCom:cancel_timer(get(?pdReconnectTimer)),
			erase(?pdReconnectTimer),
            {reply, ok, State#playerState{gatewayPid = NewGatewayPid}};
        _ -> 
            {reply, ok, State}
    end;
handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast({eGameEnd, Winner}, State = #playerState{name = Name}) ->
    Points = calculate_points(Winner, State#playerState.name),
    GameResult = case Name =:= Winner of
        true -> win;
        false -> loss
    end,
    {ok, {NewScore, NewWins, NewLosses}} =
        score_system:updateScore(Name, GameResult, Points),
    {noreply, State#playerState{
        score = NewScore,
        wins = NewWins,
        losses = NewLosses
    }};

handle_cast({eSetGamePid, GamePid}, State) ->
    {noreply, State#playerState{game_pid = GamePid}};

handle_cast({eSetIndex, Index}, State) ->
    {noreply, State#playerState{index = Index}};

handle_cast({eSetRoom, RoomId}, State) ->
    {noreply, State#playerState{room_id = RoomId}};

handle_cast({eSetRole, Role}, State) ->
    {noreply, State#playerState{role = Role}};

handle_cast(_Msg, State) ->
    {noreply, State}.


handle_info({eCliMsg, MsgHer, MsgRec}, State) ->
    try
        case MsgHer:handleMsg(MsgRec, State) of
            {ok, RtMsg, NewState} ->
                sendGateway(State#playerState.gatewayPid, RtMsg),
                {noreply, NewState};
            {ok, NewState} ->
                {noreply, NewState};
            {error, ErrCode, NewState} ->
                sendGateway(State#playerState.gatewayPid, #sc_error{code = ErrCode}),
                {noreply, NewState};
            {error, ErrCode, ErrArgs, NewState} ->
                sendGateway(State#playerState.gatewayPid, #sc_error{code = ErrCode, msg = ErrArgs}),
                {noreply, NewState};
            {stop, StReason, NewState} ->
                {stop, StReason, NewState}
        end
    catch
		throw:{error, TErrorCode} ->
			sendGateway(State#playerState.gatewayPid, #sc_error{code = TErrorCode}),
			{noreply, State};
        throw:{error, TErrorCode, TErrArgs} ->
            sendGateway(State#playerState.gatewayPid, #sc_error{code = TErrorCode, msg = TErrArgs}),
            {noreply, State};
        throw:Reason ->
            ?Error("Failed to handle message throw error: ~p~n", [Reason]),
            {noreply, State};
        Class:Reason:Stacktrace ->
            ?Error("Failed to handle message: ~p, reason: ~p ~p ~p~n", [MsgRec, Class, Reason, Stacktrace]),
            {noreply, State}
    end;

handle_info({eSendClient, Msg}, State) ->
	sendGateway(State#playerState.gatewayPid, Msg),
    {noreply, State};

handle_info({eGameStart, Cards, FirstBidder}, State) ->
    ProtoCards = convert_cards(Cards),
    Msg = #sc_game_start{cards = ProtoCards, firstBidder = FirstBidder},
	sendGateway(State#playerState.gatewayPid, Msg),
    {noreply, State#playerState{cards = Cards}};

handle_info({eTurnToBid, NextTurn, Bids}, State) ->
    BidScores = [Score || {_, Score} <- Bids],
    Msg = #sc_turn_to_bid{nextTurn = NextTurn, currentBids = BidScores},
	sendGateway(State#playerState.gatewayPid, Msg),
    {noreply, State};

handle_info({eBidMade, BidderIdx, Score}, State) ->
    Msg = #sc_bid_made{playerIdx = BidderIdx, score = Score},
	sendGateway(State#playerState.gatewayPid, Msg),
    {noreply, State};

handle_info({eLandlordSelected, LandlordIdx, LandlordCards, BaseScore}, State = #playerState{index = MyIndex, cards = MyCards}) ->
    ProtoCards = convert_cards(LandlordCards),
    Msg = #sc_landlord_selected{landlordIdx = LandlordIdx, landlordCards = ProtoCards, baseScore = BaseScore},
	sendGateway(State#playerState.gatewayPid, Msg),
    NewRole = if MyIndex =:= LandlordIdx -> landlord; true -> peasant end,
    NewCards = if MyIndex =:= LandlordIdx -> MyCards ++ LandlordCards; true -> MyCards end,
    {noreply, State#playerState{role = NewRole, cards = NewCards}};

handle_info({eTurnToPlay, NextTurn, LastPlay}, State) ->
    ProtoCards = convert_cards(LastPlay),
    Msg = #sc_turn_to_play{nextTurn = NextTurn, lastPlay = ProtoCards},
	sendGateway(State#playerState.gatewayPid, Msg),
    {noreply, State};

handle_info({ePlayerPlayed, PlayerIdx, Cards}, State = #playerState{index = MyIndex, cards = MyCards}) ->
    ProtoCards = convert_cards(Cards),
    Msg = #sc_player_played{playerIdx = PlayerIdx, cards = ProtoCards},
	sendGateway(State#playerState.gatewayPid, Msg),
    NewCards = if PlayerIdx =:= MyIndex ->
        lists:filter(fun(C) -> not lists:member(C, Cards) end, MyCards);
    true -> MyCards end,
    {noreply, State#playerState{cards = NewCards}};

handle_info({ePlayerPassed, PlayerIdx}, State) ->
    Msg = #sc_player_passed{playerIdx = PlayerIdx},
	sendGateway(State#playerState.gatewayPid, Msg),
    {noreply, State};

handle_info({ePlayerReady, PlayerIdx, Ready, AllReady}, State) ->
    ReadyVal = case Ready of true -> 1; false -> 0 end,
    AllReadyVal = case AllReady of true -> 1; false -> 0 end,
    Msg = #sc_player_ready{playerIdx = PlayerIdx, ready = ReadyVal, allReady = AllReadyVal},
	sendGateway(State#playerState.gatewayPid, Msg),
    {noreply, State};

handle_info({eGameOver, WinnerIdx, Scores}, State) ->
    ProtoScores = lists:map(fun({Idx, Name, Points, Result}) ->
        ResStr = atom_to_list(Result),
        #scoreInfo{index = Idx, name = Name, score = Points, result = ResStr}
    end, Scores),
    Msg = #sc_game_over{winnerIdx = WinnerIdx, scores = ProtoScores},
	sendGateway(State#playerState.gatewayPid, Msg),
    {noreply, State#playerState{cards = [], role = none}};

handle_info({eGameRestart}, State) ->
    {noreply, State#playerState{cards = [], role = none}};

handle_info({'EXIT', GatewayPid, _Reason}, State = #playerState{gatewayPid = GatewayPid}) ->
    ?Info("Gateway ~p exited, waiting ~p ms for reconnect~n", [GatewayPid, ?ReconnectTimeout]),
    TimerRef = erlang:send_after(?ReconnectTimeout, self(), eGatewayTimeout),
    put(?pdReconnectTimer, TimerRef),
    {noreply, State#playerState{gatewayPid = undefined}};

handle_info({'EXIT', _Pid, _Reason}, State) ->
    {noreply, State};

handle_info(eGatewayTimeout, State) ->
    ?Info("Reconnect timeout, player ~s exiting~n", [State#playerState.name]),
    erase(?pdReconnectTimer),
    {stop, {shutdown, eGatewayTimeout}, State};

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, #playerState{name = Name}) ->
    unregister_player(Name),
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

calculate_points(Winner, PlayerName) ->
    case {Winner =:= PlayerName, is_landlord(PlayerName)} of
        {true, true} -> 3;
        {true, false} -> 2;
        {false, true} -> -3;
        {false, false} -> -2
    end.

is_landlord(_PlayerName) ->
    false.

convert_cards(Cards) ->
    [#card{suit = Suit, value = Value} || {Suit, Value} <- Cards].

sendGateway(GatewayPid, Msg) ->
	GatewayPid /= undefined andalso GatewayPid ! {eSendCli, Msg}.
