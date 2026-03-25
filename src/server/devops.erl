-module(devops).

-include("common.hrl").
-include("server.hrl").

-export([
	loadDevopsCfg/0
	, getSrvType/0
]).

%% 加载运维相关配置
loadDevopsCfg() ->
	NodeAtom = node(),
	WholeNodeName = atom_to_binary(NodeAtom),
	[NodeName, _] = binary:split(WholeNodeName, <<"@">>),
	case binary:match(NodeName, ?AlLSrvTypeStr) of
		{StartIndex, _Len} ->
			DevopsCfgPre = binary:part(NodeName, StartIndex, byte_size(NodeName) - StartIndex),
			%% 首先在当前路径下查找
			DevopsCfgName = <<"./", (?devopsNameBase)/binary, DevopsCfgPre/binary, (?devopsNameExt)/binary>>,
			case filelib:is_file(DevopsCfgName) andalso file:consult(DevopsCfgName) of
				{ok, Terms} ->
					utKvsToBeam:load(?devopsCfg, Terms);
				false ->
					ODevopsCfgName = <<"./", (?devopsDir)/binary, "/", (?devopsNameBase)/binary, DevopsCfgPre/binary, (?devopsNameExt)/binary>>,
					case filelib:is_file(ODevopsCfgName) andalso file:consult(ODevopsCfgName) of
						{ok, Terms} ->
							utKvsToBeam:load(?devopsCfg, Terms);
						false ->
							?Error("not found the devops file:~s please check~n", [DevopsCfgName]),
							throw(badDevopsCfg);
						{error, Reason} ->
							?Error("read the devops file:~p error:~p~n", [ODevopsCfgName, Reason]),
							throw(badDevopsCfg)
					end;
				{error, Reason} ->
					?Error("read the devops file:~s error:~p~n", [DevopsCfgName, Reason]),
					throw(badDevopsCfg)
			end,
			ok;
		_ ->
			?Error("use bad name node: ~p, it's should include the server type~n", [NodeAtom]),
			throw(badNodeName)
	end.

getSrvType() ->
	?devopsCfg:getV(type).