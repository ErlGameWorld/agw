-module(gatewayWs).
-behavior(wsHer).

-include("common.hrl").
-include("protoMsg.hrl").
-include("gateway.hrl").
-include("error_code.hrl").
-include_lib("eWSrv/include/eWSrv.hrl").

-export([
   start_link/2,
	init/1,
	handle/3,
	handleWs/3,
	handleCall/3,
	handleCast/2,
	handleInfo/2,
	terminate/2
]).

start_link(Socket, ConnArgs) ->
   wsHttp:start_link(Socket, ConnArgs).

init(Args) ->
	process_flag(trap_exit, true),
	process_flag(min_heap_size, 10240),
	process_flag(min_bin_vheap_size, 524288),
	process_flag(fullsweep_after, 2048),

	Socket = ?Case(Args, {Sock, _ConnArgs}, Sock, _, Args),
	put(?pdHandshakeTimer, erlang:send_after(?HandshakeTime, self(), eHandshakeCheck)),
	put(?pdHeartbeatLastTime, utTime:nowMs()),
	put(?pdPacketCnt, 0),
	put(?pdPacketFastCnt, 0),
	?Info("accept gameServer socket[~p] gameServerPID[~p] ConArgs:~p ~n", [Socket, self(), Args]),
	{ok, #gatewayState{socket = Socket}}.

-spec handle(Method :: wsMethod(), Path :: binary(), Req :: wsReq()) -> wsHer:response().
handle('GET', <<"/">>, WsReq) ->
	case wsWebSocket:tryWsUpgrade(WsReq) of
		{ok, Headers} ->
			{wsUpgrade, Headers};
		{error, Reason} ->
			{502, [], Reason}
	end;

handle(Method, Path, Req) ->
	?Error("handle unknow msg: ~p ~p~n ", [{Method, Path, Req}, self()]),
	{404, [], <<"Not Found">>}.

-spec handleWs(WsOpCode :: wsOpCode(), Data :: binary(), WebState :: term()) -> wsHer:wsResponse().
handleWs(?WsOpBinary, Data, State) ->
	put(?pdPacketCnt, get(?pdPacketCnt) + 1),
	try
		{MsgHer, MsgRec} = protoMsg:decode(Data),
		case MsgHer of
			loginHer ->
				case loginHer:handleMsg(MsgRec, State) of
					{ok, RtMsg, NewState} ->
						sendMsg(State#gatewayState.socket, RtMsg),
						{ok, NewState};
					{ok, NewState} ->
						{ok, NewState};
					{error, ErrorCode, NewState} ->
						sendError(State#gatewayState.socket, ErrorCode, ""),
						{ok, NewState};
					{error, ErrorCode, ErrArgs, NewState} ->
						sendError(State#gatewayState.socket, ErrorCode, ErrArgs),
						{ok, NewState};
					{stop, StReason, NewState} ->
						{stop, StReason, NewState}
				end;
			_ ->
				case State#gatewayState.playerPid of
					undefined ->
						?Warn("handleWs player_pid is undefined, but receive msg: ~p~n", [MsgRec]),
						sendError(State#gatewayState.socket, ?ERR_INVALID_REQUEST, "player_pid is undefined"),
						{ok, State};
					Pid ->
						Pid ! {eCliMsg, MsgHer, MsgRec},
						{ok, State}
				end
		end
	catch
		throw:{error, TErrorCode} ->
			sendError(State#gatewayState.socket, TErrorCode, ""),
			{ok, State};
		throw:{error, TErrorCode, TErrArgs} ->
			sendError(State#gatewayState.socket, TErrorCode, TErrArgs),
			{ok, State};
		throw:Reason ->
			?Error("Failed to handle message throw error: ~p~n", [Reason]),
			{ok, State};
		Class:Reason:Stacktrace ->
			?Error("Failed to handle message: ~p, reason: ~p ~p ~p~n", [Data, Class, Reason, Stacktrace]),
			{ok, State}
	end;

handleWs(?WsOpText, _Data, State) ->
	{ok, State};

handleWs(?WsOpPing, _Payload, State) ->
	{ok, State};

handleWs(?WsOpClose, _Payload, State) ->
	{close, normal, State};

handleWs(WsOpCode, Data, State) ->
	?Warn("handleWs unknow msg: ~p~n ", [{WsOpCode, Data, State}]),
	{ok, State}.

-spec handleCall(Request :: term(), WebState :: term(), From :: {pid(), Tag :: term()}) ->
	kpS |
	{reply, Reply :: term()} |
	{reply, Reply :: term(), NewState :: term()} |
	{noreply, NewState :: term()} |
	{mayReply, Reply :: term()} |
	{mayReply, Reply :: term(), NewState :: term()} |
	{stop, Reason :: term(), NewState :: term()} |
	{stopReply, Reason :: term(), Reply :: term(), NewState :: term()}.
handleCall(_Request, _WebState, _From) ->
	?Warn("handleCall unknow msg: ~p ~p~n ", [_Request, _WebState]),
	kpS.

-spec handleCast(Request :: term(), WebState :: term()) ->
	kpS |
	{noreply, NewState :: term()} |
	{stop, Reason :: term(), NewState :: term()}.
handleCast(_Request, _WebState) ->
	?Warn("handleCast unknow msg: ~p ~p~n ", [_Request, _WebState]),
	kpS.

-spec handleInfo(Info :: timeout | term(), WebState :: term()) ->
	kpS |
	{noreply, NewState :: term()} |
	{stop, Reason :: term(), NewState :: term()}.
handleInfo({eSendCli, Msg}, State = #gatewayState{socket = Socket}) ->
	sendMsg(Socket, Msg),
	{noreply, State};

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

handleInfo({'EXIT', Pid, _Reason}, State = #gatewayState{playerPid = Pid}) ->
	?Info("Player ~p exited, gateway closing~n", [Pid]),
	{stop, {shutdown, player_exit}, State};
handleInfo({'EXIT', _Pid, _Reason}, State) ->
	{noreply, State};

handleInfo(eKickByRelogin, State) ->
	?Info("Kicked by relogin, gateway closing~n", []),
	{stop, {shutdown, kicked_by_relogin}, State};

handleInfo(_Info, State) ->
	{noreply, State}.

-spec terminate(Reason :: timeout, WebState :: timeout) -> ignore.
terminate(_Reason, #gatewayState{}) ->
	utCom:cancel_timer(get(?pdCheckTimer)),
	ok.

sendMsg(Socket, Msg) when is_binary(Msg) ->
	wsWebSocket:sendFrame(Socket, ?WsOpBinary, Msg);
sendMsg(Socket, Msg) ->
	Bin = protoMsg:encodeBin(Msg),
	wsWebSocket:sendFrame(Socket, ?WsOpBinary, Bin).

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