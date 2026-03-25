-module(loginHer).
-include("protoMsg.hrl").
-include("common.hrl").
-include("gateway.hrl").
-include("player.hrl").
-include("error_code.hrl").

-export([handleMsg/2]).

handleMsg(#cs_handshake{encrypt1 = Encrypt1, encrypt2 = Encrypt2}, #gatewayState{gwStatus = ?GWVerify} = State) ->
	Expected = ((Encrypt1 bxor ?EncryptMagic1) + ?EncryptMagic2) band 16#FFFFFFFF,
	case Expected == Encrypt2 of
		true ->
			utCom:cancel_timer(get(?pdHandshakeTimer)),
			put(?pdCheckTimer, erlang:send_after(?CheckInterval, self(), eGwCheck)),
			{ok, #sc_handshake{result = 0}, State#gatewayState{gwStatus = ?GWPass}};
		false ->
			?Debug("Handshake failed: Encrypt1=~p, Encrypt2=~p, Expected=~p~n", [Encrypt1, Encrypt2, Expected]),
			{stop, {shutdown, invalid_connect}, State}
	end;


handleMsg(#cs_heartbeat{}, State) ->
	put(?pdHeartbeatLastTime, utTime:nowMs()),
	{ok, #sc_heartbeat{}, State};

handleMsg(#cs_login{name = Name}, #gatewayState{gwStatus = ?GWPass} =  State) ->
    case player:findPlayer(Name) of
        {ok, Pid} ->
            case player:setGatewayPid(Pid, self()) of
                ok ->
                    PlayerId = integer_to_list(erlang:phash2(Pid)),
                    {ok, {Score, Wins, Losses}} = player:getStatistics(Pid),
                    Resp = #sc_login{
                        result = 0,
                        playerId = PlayerId,
                        player = #playerInfo{
                            index = 0,
                            name = Name,
                            score = Score,
                            wins = Wins,
                            losses = Losses,
                            status = 1
                        }
                    },
                    {ok, Resp, State#gatewayState{playerPid = Pid, player_id = PlayerId, gwStatus = ?GWLogin}};
                {error, _Reason} ->
                    doCreatePlayer(Name, State)
            end;
        not_found ->
            doCreatePlayer(Name, State)
    end;

handleMsg(Msg, State) ->
	?Warn("receive login unknow msg or state not right Msg:~p State:~p~n", [Msg, State]),
	{ok, State}.

doCreatePlayer(Name, State) ->
    case player_sup:start_player(Name, self()) of
        {ok, Pid} ->
            PlayerId = integer_to_list(erlang:phash2(Pid)),
            {ok, {Score, Wins, Losses}} = player:getStatistics(Pid),
            Resp = #sc_login{
                result = 0,
                playerId = PlayerId,
                player = #playerInfo{
                    index = 0,
                    name = Name,
                    score = Score,
                    wins = Wins,
                    losses = Losses,
                    status = 1
                }
            },
            {ok, Resp, State#gatewayState{playerPid = Pid, player_id = PlayerId, gwStatus = ?GWLogin}};
        {error, {already_started, Pid}} ->
            case player:setGatewayPid(Pid, self()) of
                ok ->
                    PlayerId = integer_to_list(erlang:phash2(Pid)),
                    {ok, {Score, Wins, Losses}} = player:getStatistics(Pid),
                    Resp = #sc_login{
                        result = 0,
                        playerId = PlayerId,
                        player = #playerInfo{
                            index = 0,
                            name = Name,
                            score = Score,
                            wins = Wins,
                            losses = Losses,
                            status = 1
                        }
                    },
                    {ok, Resp, State#gatewayState{playerPid = Pid, player_id = PlayerId, gwStatus = ?GWLogin}};
                {error, Reason} ->
                    {error, ?ERR_LOGIN_FAILED, io_lib:format("set_gateway failed: ~p", [Reason]), State}
            end;
        {error, {already_registered, _}} ->
            case player:findPlayer(Name) of
                {ok, ExistPid} ->
                    case player:setGatewayPid(ExistPid, self()) of
                        ok ->
                            PlayerId = integer_to_list(erlang:phash2(ExistPid)),
                            {ok, {Score, Wins, Losses}} = player:getStatistics(ExistPid),
                            Resp = #sc_login{
                                result = 0,
                                playerId = PlayerId,
                                player = #playerInfo{
                                    index = 0,
                                    name = Name,
                                    score = Score,
                                    wins = Wins,
                                    losses = Losses,
                                    status = 1
                                }
                            },
                            {ok, Resp, State#gatewayState{playerPid = ExistPid, player_id = PlayerId, gwStatus = ?GWLogin}};
                        {error, Reason} ->
                            {error, ?ERR_LOGIN_FAILED, io_lib:format("set_gateway failed: ~p", [Reason]), State}
                    end;
                not_found ->
                    {error, ?ERR_PLAYER_NOT_FOUND, "player not found after already_registered", State}
            end;
        {error, Reason} ->
            {error, ?ERR_LOGIN_FAILED, io_lib:format("create player failed: ~p", [Reason]), State}
    end.
