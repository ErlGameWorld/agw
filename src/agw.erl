-module(agw).

-include("common.hrl").
-include("server.hrl").

-export([
	start/0
	, start/1
	, stop/0
	, stop/1
	, childSpec/1
]).

%% 定义管理不同类型的类型的服务器启动不同的app
%% App格式 appName Fun
%% 基础的app
-define(BaseApp, [
	eLog
	, fun devops:loadDevopsCfg/0
	, os_mon
	, eGbh
	, eUtils
	, jiffy
	, eFaw
	, ibrowse

]).

%% 中心服的app
-define(CenterApp, [
	agw
]).

%% 游戏服的SupOrSrv
-define(CenterSupSrv, [

]).

%% 跨服的app
-define(CrossApp, [
	agw
]).
%% 游戏服的SupOrSrv
-define(CrossSupSrv, [
]).

%% 游戏服的app
-define(GameApp, [
	eNet
	, eWSrv
	, agw
	, fun gateway:start/0
]).
%% 游戏服的SupOrSrv
-define(GameSupSrv, [
	#childSpec{id = player_sup, start ={player_sup, start_link, []}, restart = temporary, shutdown = infinity, type = supervisor, modules = [player_sup]},
	#childSpec{id = system_sup, start ={system_sup, start_link, []}, restart = temporary, shutdown = infinity, type = supervisor, modules = [system_sup]},
	#childSpec{id = playerMgrSrv, start ={playerMgrSrv, start_link, []}, restart = transient, shutdown = infinity, type = worker, modules = [playerMgrSrv]}
]).

%% 启动服务器
start() ->
	[doStartApp(OneApp) || OneApp <- ?BaseApp],
	start(devops:getSrvType()).

start(?SrvTypeGame) ->
	[doStartApp(OneApp) || OneApp <- ?GameApp],
	ok;
start(?SrvTypeCenter) ->
	[doStartApp(OneApp) || OneApp <- ?CenterApp],
	ok;
start(?SrvTypeCross) ->
	[doStartApp(OneApp) || OneApp <- ?CrossApp],
	ok.

%% 关闭服务器
stop() ->
	stop(devops:getSrvType()).

stop(?SrvTypeGame) ->
	doStopApp(agw),
	%% init:stop(),
	ok;
stop(?SrvTypeCross) ->
	doStopApp(agw),
	%% init:stop(),
	ok;
stop(?SrvTypeCenter) ->
	doStopApp(agw),
	%% init:stop(),
	ok.

childSpec(?SrvTypeCenter) ->
	[childSpecToMap(OneSupSrv) || OneSupSrv <- ?CenterSupSrv];
childSpec(?SrvTypeCross) ->
	[childSpecToMap(OneSupSrv) || OneSupSrv <- ?CrossSupSrv];
childSpec(?SrvTypeGame) ->
	[childSpecToMap(OneSupSrv) || OneSupSrv <- ?GameSupSrv].

childSpecToMap(#childSpec{} = Spec) ->
	#{
		id => Spec#childSpec.id,
		start => Spec#childSpec.start,
		restart => Spec#childSpec.restart,
		shutdown => Spec#childSpec.shutdown,
		type => Spec#childSpec.type,
		modules => Spec#childSpec.modules
	}.

doStartApp(FunOrApp) ->
	try
		case case is_function(FunOrApp) of true -> FunOrApp(); _ -> application:ensure_all_started(FunOrApp) end of
			{error, AppErrReason} ->
				?Error("start the app:~p error:~p~n", [FunOrApp, AppErrReason]),
				exit({error, AppErrReason});
			_ ->
				?Info("start app ~w~n", [FunOrApp])
		end
	catch C:R:S ->
		?Error("start the app:~p CRS:~p~n", [FunOrApp, {C, R, S}]),
		exit({error, {FunOrApp, {C, R, S}}})
	end.

doStopApp(FunOrApp) ->
	try
		case case is_function(FunOrApp) of true -> FunOrApp(); _ -> application:stop(FunOrApp) end of
			{error, AppErrReason} ->
				?Error("stop the app:~p error:~p~n", [FunOrApp, AppErrReason]);
			_ ->
				?Info("stop app ~w~n", [FunOrApp])
		end
	catch C:R:S ->
		?Error("stop the app:~p CRS:~p~n", [FunOrApp, {C, R, S}])
	end.
