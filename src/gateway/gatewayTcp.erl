-module(gatewayTcp).
-behaviour(gen_srv).

-include_lib("eNet/include/eNet.hrl").
-include("protoMsg.hrl").
-include("common.hrl").
-include("gateway.hrl").
-include("server.hrl").
-include("error_code.hrl").


-export([
	newConn/2,
	start_link/2
]).

-export([
	init/1,
	handleCall/3,
	handleCast/2,
	handleInfo/2,
	terminate/2,
	code_change/3
]).

newConn(Socket, GateWaySupName) ->
	supervisor:start_child(GateWaySupName, [Socket, GateWaySupName]).

start_link(Socket, _Args) ->
	gen_srv:start_link(?MODULE, {Socket, _Args}, [{min_heap_size, 10240},{min_bin_vheap_size, 524288},{fullsweep_after, 2048}]).

init({Socket, _ConArgs}) ->
	process_flag(trap_exit, true),
	put(?pdHandshakeTimer, erlang:send_after(?HandshakeTime, self(), eHandshakeCheck)),
	put(?pdHeartbeatLastTime, utTime:nowMs()),
	put(?pdPacketCnt, 0),
	put(?pdPacketFastCnt, 0),
	{ok, #gatewayState{socket = Socket}}.

handleCall(_Req, _From, State) ->
	{reply, {error, unknown_call}, State}.

handleCast({send, Data}, #gatewayState{socket = Socket} = State) ->
	ntCom:asyncSend(Socket, Data),
	{noreply, State};

handleCast(_Msg, State) ->
	?Warn("handleCast unknow msg: ~p ~p~n ", [_Msg, State]),
	{noreply, State}.

handleInfo({?mSockReady, Socket}, State) ->
	ok = inet:setopts(Socket, ?CTcpOpts),
	{noreply, State};

handleInfo({tcp, Socket, DataBin}, #gatewayState{socket = Socket, playerPid = PlayerPid} = State) ->
	put(?pdPacketCnt, get(?pdPacketCnt) + 1),
	try
		{MsgHer, MsgRec} = protoMsg:decode(DataBin),
		case MsgHer of
			loginHer ->
				case loginHer:handleMsg(MsgRec, State) of
					{ok, RtMsg, NewState} ->
						sendMsg(State#gatewayState.socket, RtMsg),
						{noreply, NewState};
					{ok, NewState} ->
						{noreply, NewState};
					{error, ErrorCode, NewState} ->
						sendError(State#gatewayState.socket, ErrorCode, ""),
						{noreply, NewState};
					{error, ErrorCode, ErrArgs, NewState} ->
						sendError(State#gatewayState.socket, ErrorCode, ErrArgs),
						{noreply, NewState};
					{stop, StopReason, NewState} ->
						{stop, StopReason, NewState}
				end;
			_ ->
				case PlayerPid of
					undefined ->
						?Warn("handleTcp player_pid is undefined, but receive msg: ~p~n ", [MsgRec]),
						sendError(State#gatewayState.socket, 1, "player not login"),
						{noreply, State};
					Pid ->
						Pid ! {eCliMsg, MsgHer, MsgRec},
						{noreply, State}
				end
		end
	catch
		throw:{error, TErrorCode} ->
			sendError(State#gatewayState.socket, TErrorCode, ""),
			{noreply, State};
		throw:{error, TErrorCode, TErrArgs} ->
			sendError(State#gatewayState.socket, TErrorCode, TErrArgs),
			{noreply, State};
		throw:Reason ->
			?Error("Failed to handle message throw error: ~p~n", [Reason]),
			{noreply, State};
		Class:Reason:Stacktrace ->
			?Error("Failed to handle message: ~p, reason: ~p ~p ~p~n", [DataBin, Class, Reason, Stacktrace]),
			{noreply, State}
	end;
handleInfo({tcp_passive, Socket}, #gatewayState{socket = Socket} = State) ->
	inet:setopts(Socket, [{active, ?GwActive}]),
	{noreply, State};

handleInfo({eSendCli, Msg}, State = #gatewayState{socket = Socket}) ->
	sendMsg(Socket, Msg),
	{noreply, State};

handleInfo({tcp_closed, _Sock}, State) ->
	{stop, {shutdown, tcp_closed}, State};

handleInfo({tcp_error, _Sock, Reason}, State) ->
	?Error("Socket error:~w~n", [Reason]),
	{stop, {shutdown, tcp_error, Reason}, State};

handleInfo(eHandshakeCheck, #gatewayState{gwStatus = GwStatus} = State) ->
	case GwStatus of
		?GWVerify ->
			?Warn("verify timeout~n", []),
			{stop, {shutdown, verify_timeout}, State};
		_ ->
			erase(?pdHandshakeTimer),
			{noreply, State}
	end;

handleInfo(eGwCheck, State) ->
	Now = utTime:nowMs(),
	Elapsed = Now - get(?pdHeartbeatLastTime),
	maybe
		true ?= (Elapsed < ?HeartbeatTimeout) orelse {heartbeat_timeout, ?ERR_GATEWAY_TIMEOUT, "heartbeat_timeout"},
		PacketsPerSec = get(?pdPacketCnt) div (?CheckInterval div 1000),
		NewFastCount = checkPacketSpeed(PacketsPerSec, get(?pdPacketFastCnt)),
		true ?= (NewFastCount < ?PacketFastMaxCnt) orelse {packet_too_fast, ?ERR_PACKET_TOO_FAST, "packet_too_fast"},
		put(?pdPacketCnt, 0),
		put(?pdPacketFastCnt, NewFastCount),
		put(?pdCheckTimer, erlang:send_after(?CheckInterval, self(), eGwCheck)),
		{noreply, State}
	else
		{StopReason, ErrorCode, ErrorArgs} ->
			sendError(State#gatewayState.socket, ErrorCode, ErrorArgs),
			?Warn("Gateway check failed: ~p~n", [StopReason]),
			{stop, {shutdown, StopReason}, State}
	end;

handleInfo({'EXIT', Pid, _Reason}, #gatewayState{playerPid = Pid} = State) ->
	?Info("Player ~p exited, gateway closing~n", [Pid]),
	{stop, {shutdown, player_exit}, State};

handleInfo({'EXIT', _Pid, _Reason}, State) ->
	{noreply, State};

handleInfo(eKickByRelogin, State) ->
	?Info("Kicked by relogin, gateway closing~n", []),
	{stop, {shutdown, kicked_by_relogin}, State};

handleInfo({inet_reply, _Sock, ok}, State) ->
	{noreply, State};

handleInfo({inet_reply, _Sock, Result}, State) ->
	?Error("socket inet_reply error:~w~n", [Result]),
	{stop, {shutdown, {inet_reply_error, Result}}, State};

handleInfo({inet_reply, _Socket, ok, _MRef}, State) ->
	{noreply, State};

handleInfo({inet_reply, _Socket, Result, _MRef}, State) ->
	?Error("socket inet_reply error:~w~n", [Result]),
	{stop, {shutdown, {inet_reply_error, Result}}, State};


handleInfo(_Info, State) ->
	?Warn("handleInfo unknow msg: ~p ~p~n ", [_Info, State]),
	{noreply, State}.

code_change(_OldVsn, State, _Extra) ->
	{ok, State}.

terminate(Reason, #gatewayState{socket = Socket, ip = IP, port = Port}) ->
	?Debug("Gateway terminate: ~p, ~p:~p~n", [Reason, IP, Port]),
	utCom:cancel_timer(get(?pdCheckTimer)),
	try gen_tcp:close(Socket)
	catch
		_:_ -> ok
	end,
	ok.

sendMsg(Socket, Msg) when is_binary(Msg) ->
	ntCom:asyncSend(Socket, Msg);
sendMsg(Socket, Msg) ->
	Bin = protoMsg:encodeBin(Msg),
	ntCom:asyncSend(Socket, Bin).

sendError(Socket, Code, Msg) ->
	sendMsg(Socket, #sc_error{code = Code, msg = Msg}).

checkPacketSpeed(PacketsPerSec, FastCount) when PacketsPerSec >= ?PacketKickLimit ->
	FastCount + 3;
checkPacketSpeed(PacketsPerSec, FastCount) when PacketsPerSec >= ?PacketWarningLimit ->
	FastCount + 2;
checkPacketSpeed(PacketsPerSec, FastCount) when PacketsPerSec > ?PacketNormalLimit ->
	FastCount + 1;
checkPacketSpeed(_PacketsPerSec, _FastCount) ->
	0.