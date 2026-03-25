-module(ai_supervisor).
-behaviour(supervisor).

-export([start_link/0, init/1]).
-export([start_ai/1, stop_ai/1]).
-export([
    list_active_ais/0,
    get_ai_statistics/0,
    restart_ai/1,
    start_multiple_ais/1,
    stop_multiple_ais/1,
    monitor_ai_health/0,
    get_ai_configuration/1,
    update_ai_configuration/2,
    get_supervisor_status/0,
    get_message_queue_len/1,
    get_process_memory/1
]).

%% API
start_link() ->
    supervisor:start_link({local, ?MODULE}, ?MODULE, []).

%% 启动一个AI玩家
start_ai(Name) ->
    supervisor:start_child(?MODULE, [Name]).

%% 停止一个AI玩家
stop_ai(AiPid) ->
    supervisor:terminate_child(?MODULE, AiPid).

%% Callbacks
init([]) ->
    SupFlags = #{strategy => simple_one_for_one,
                 intensity => 10,
                 period => 60},
    
    ChildSpecs = [
        #{id => ai_agent,
          start => {ai_agent, start_link, []},
          restart => temporary,
          shutdown => 5000,
          type => worker,
          modules => [ai_agent]}
    ],
    
    {ok, {SupFlags, ChildSpecs}}.

%% ========== 扩展功能 ==========

%% 获取所有活跃的AI玩家
list_active_ais() ->
    Children = supervisor:which_children(?MODULE),
    lists:filtermap(
        fun({Id, Pid, _Type, _Modules}) ->
            case is_process_alive(Pid) of
                true -> {true, {Id, Pid}};
                false -> false
            end
        end,
        Children
    ).

%% 获取AI玩家统计信息
get_ai_statistics() ->
    ActiveAIs = list_active_ais(),
    #{
        total_active => length(ActiveAIs),
        ai_processes => ActiveAIs,
        supervisor_status => get_supervisor_status()
    }.

%% 重启指定的AI玩家
restart_ai(AiPid) ->
    case supervisor:terminate_child(?MODULE, AiPid) of
        ok ->
            supervisor:restart_child(?MODULE, AiPid);
        {error, Reason} ->
            {error, Reason}
    end.

%% 批量启动AI玩家
start_multiple_ais(Difficulties) ->
    lists:map(
        fun(Difficulty) ->
            start_ai(Difficulty)
        end,
        Difficulties
    ).

%% 批量停止AI玩家
stop_multiple_ais(AiPids) ->
    lists:foreach(
        fun(AiPid) ->
            stop_ai(AiPid)
        end,
        AiPids
    ).

%% 监控AI玩家状态
monitor_ai_health() ->
    ActiveAIs = list_active_ais(),
    lists:map(
        fun({Id, Pid}) ->
            #{
                id => Id,
                pid => Pid,
                is_alive => is_process_alive(Pid),
                message_queue_len => get_message_queue_len(Pid),
                memory_usage => get_process_memory(Pid)
            }
        end,
        ActiveAIs
    ).

%% 获取AI玩家配置
get_ai_configuration(AiPid) ->
    case is_process_alive(AiPid) of
        true ->
            try
                ai_player:get_configuration(AiPid)
            catch
                _:_ -> {error, process_not_ai_player}
            end;
        false ->
            {error, process_not_alive}
    end.

%% 更新AI玩家配置
update_ai_configuration(AiPid, NewConfig) ->
    case is_process_alive(AiPid) of
        true ->
            try
                ai_player:update_configuration(AiPid, NewConfig)
            catch
                _:_ -> {error, process_not_ai_player}
            end;
        false ->
            {error, process_not_alive}
    end.

%% ========== 辅助函数 ==========

get_supervisor_status() ->
    #{
        name => ?MODULE,
        strategy => simple_one_for_one,
        intensity => 10,
        period => 60
    }.

get_message_queue_len(Pid) ->
    case process_info(Pid, message_queue_len) of
        {message_queue_len, Len} -> Len;
        _ -> 0
    end.

get_process_memory(Pid) ->
    case process_info(Pid, memory) of
        {memory, Bytes} -> Bytes;
        _ -> 0
    end.