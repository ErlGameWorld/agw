-module(gateway).

-include("server.hrl").
-include("gateway.hrl").

-export([
	start/0
	, startTcp/3
	, startWs/3
	, startHttp/2
	, close/1
]).

start() ->
	case ?devopsCfg:getV(port) of
		Port when Port > 0 ->
			gateway:startTcp(gatewayTcpSup, gatewayTcpListener, Port);
		_ ->
			ignore
	end,
	case ?devopsCfg:getV(ws_port) of
		WsPort when WsPort > 0 ->
			gateway:startWs(gatewayWsSup, gatewayWsListener, WsPort);
		_ ->
			ignore
	end,
	case ?devopsCfg:getV(web_port) of
		WebPort when WebPort > 0 ->
			gateway:startHttp(gatewayHttpListener, WebPort);
		_ ->
			ignore
	end.

startTcp(GateWaySupName, ListenName, Port) ->
	TcpMgrSupSpec = #{
		id => GateWaySupName,
		start => {gatewaySup, start_link, [GateWaySupName, gatewayTcp]},
		restart => permanent,
		shutdown => infinity,
		type => supervisor,
		modules => [gatewaySup]
	},
	{ok, _SupPid} = supervisor:start_child(?SrvSup, TcpMgrSupSpec),
	eNet:openTcp(ListenName, Port, [{conMod, gatewayTcp}, {conArgs, GateWaySupName}, {aptCnt, 32}, {tcpOpts, ?LTcpOpts}]).

startWs(GateWaySupName, ListenName, Port) ->
	TcpMgrSupSpec = #{
		id => GateWaySupName,
		start => {gatewaySup, start_link, [GateWaySupName, gatewayWs]},
		restart => permanent,
		shutdown => infinity,
		type => supervisor,
		modules => [gatewaySup]
	},
	{ok, _SupPid} = supervisor:start_child(?SrvSup, TcpMgrSupSpec),
	eWSrv:openSrv(ListenName, Port, [{wsMod, gatewayWs}, {aptCnt, 32}, {wsSupName, GateWaySupName}, {maxSize, ?GatewayMaxSize}]).

startHttp(ListenName, Port) ->
	eWSrv:openSrv(ListenName, Port, [{aptCnt, 32}, {wsMod, gatewayHttp}, {maxSize, ?GatewayMaxSize}]).

close(ListenName) ->
	eNet:close(ListenName).