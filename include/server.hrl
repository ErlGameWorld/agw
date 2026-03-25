-ifndef(__server_h__).
-define(__server_h__, true).

-record(childSpec, {
	id :: term(),                          %% 子进程标识，在supervisor中唯一
	start :: {module(), atom(), [term()]}, %% 启动函数 {Module, Function, Args}
	restart = transient :: permanent | transient | temporary,  %% 重启策略: permanent(总是重启) | transient(异常时重启) | temporary(不重启)
	shutdown = 5000 :: non_neg_integer() | infinity | brutal_kill, %% 关闭超时时间(毫秒) | infinity(无限等待) | brutal_kill(强制杀死)
	type = worker :: worker | supervisor,  %% 进程类型: worker(工作进程) | supervisor(监控进程)
	modules :: [module()] | dynamic        %% 模块列表，用于代码热更新; dynamic表示动态模块
}).

%% 游戏的基础的sup
-define(SrvSup, agw_sup).

%% 所有的服务器类型字符串
-define(SrvTypeGame, game).
-define(SrvTypeCenter, center).
-define(SrvTypeCross, cross).
-define(GameTypeStr, <<"Game">>).
-define(CenterTypeStr, <<"Center">>).
-define(CrossTypeStr, <<"Cross">>).
-define(AlLSrvTypeStr, [?GameTypeStr, ?CenterTypeStr, ?CrossTypeStr]).

%% 运维配置文件名beam模块
-define(devopsCfg, devopsCfg).
%% 运维配置的文件名
-define(devopsNameBase, <<"devops">>).
-define(devopsNameExt, <<".cfg">>).
%% 运维配置首先在当前路径查找 其次在当前路径该的文件夹下查找
-define(devopsDir, <<"config">>).

-endif.
