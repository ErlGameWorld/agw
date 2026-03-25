-module(rate_lib).
-export([get_random_rate/1, parse_rate_config/1, get_random_average/1, parse_average_config/1]).

%% @doc 根据机率配置获取随机机率值
%% 示例: {type, [rate,10,3,30,5,50,10]} 表示
%% 0-10的机率加3点星级
%% 11-30的机率加5点星级
%% 31-50的机率加10点星级
%% 大于50则不改变
get_random_rate(Config) ->
    case parse_rate_config(Config) of
        {error, Reason} ->
            {error, Reason};
        {ok, Rates} ->
            RandomNum = generate_random_number(0, 100),
            get_rate_by_random(RandomNum, Rates)
    end.

%% @doc 解析机率配置
%% 返回格式: {ok, [{MaxValue, Value}]}
%% 例如: {ok, [{10, 3}, {30, 5}, {50, 10}]}
parse_rate_config({type, [rate | Rest]}) ->
    parse_rate_pairs(Rest, []);
parse_rate_config(_) ->
    {error, invalid_config_format}.

%% @private 解析机率配对
parse_rate_pairs([], Acc) ->
    {ok, lists:reverse(Acc)};
parse_rate_pairs([MaxValue, Value | Rest], Acc) ->
    case is_integer(MaxValue) andalso MaxValue > 0 andalso is_integer(Value) of
        true ->
            parse_rate_pairs(Rest, [{MaxValue, Value} | Acc]);
        false ->
            {error, invalid_rate_value}
    end;
parse_rate_pairs(_, _) ->
    {error, invalid_config_format}.

%% @private 根据随机数获取对应的机率值
get_rate_by_random(_, []) ->
    {ok, no_change};
get_rate_by_random(RandomNum, [{MaxValue, Value} | Rest]) ->
    if
        RandomNum =< MaxValue -> {ok, Value};
        true -> get_rate_by_random(RandomNum, Rest)
    end.

%% @private 生成指定范围内的随机数
generate_random_number(Min, Max) ->
    % 确保随机数生成器已初始化
    _ = case erlang:whereis(random_seed) of
        undefined -> rand:seed(exsplus);
        _ -> ok
    end,
    Min + rand:uniform(Max - Min + 1) - 1.

%% @doc 根据平均值配置获取随机平均值
%% 示例: {type, [average,3,4,2]} 表示
%% 从列表[3,4,2]中随机选择一个值
get_random_average(Config) ->
    case parse_average_config(Config) of
        {error, Reason} ->
            {error, Reason};
        {ok, Values} ->
            RandomIndex = generate_random_number(1, length(Values)),
            {ok, lists:nth(RandomIndex, Values)}
    end.

%% @doc 解析平均值配置
%% 返回格式: {ok, [Value1, Value2, ...]}
%% 例如: {ok, [3, 4, 2]}
parse_average_config({type, [average | Rest]}) ->
    parse_average_values(Rest, []);
parse_average_config(_) ->
    {error, invalid_config_format}.

%% @private 解析平均值列表
parse_average_values([], Acc) ->
    {ok, lists:reverse(Acc)};
parse_average_values([Value | Rest], Acc) ->
    case is_integer(Value) of
        true ->
            parse_average_values(Rest, [Value | Acc]);
        false ->
            {error, invalid_average_value}
    end.

%% @doc 测试函数
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

parse_average_config_test() ->
    Config = {type, [average, 3, 4, 2]},
    ?assertEqual({ok, [3, 4, 2]}, parse_average_config(Config)),
    
    InvalidConfig1 = {wrong_type, [average, 3, 4, 2]},
    ?assertEqual({error, invalid_config_format}, parse_average_config(InvalidConfig1)),
    
    InvalidConfig2 = {type, [wrong_keyword, 3, 4, 2]},
    ?assertEqual({error, invalid_config_format}, parse_average_config(InvalidConfig2)),
    
    InvalidConfig3 = {type, [average, 3, "4", 2]},
    ?assertEqual({error, invalid_average_value}, parse_average_config(InvalidConfig3)).

get_random_average_test() ->
    % 由于随机性，我们只能测试返回值是否在预期列表中
    Config = {type, [average, 3, 4, 2]},
    {ok, Result} = get_random_average(Config),
    ?assert(lists:member(Result, [3, 4, 2])).

parse_rate_config_test() ->
    Config = {type, [rate, 10, 3, 30, 5, 50, 10]},
    ?assertEqual({ok, [{10, 3}, {30, 5}, {50, 10}]}, parse_rate_config(Config)),
    
    InvalidConfig1 = {wrong_type, [rate, 10, 3, 30, 5, 50, 10]},
    ?assertEqual({error, invalid_config_format}, parse_rate_config(InvalidConfig1)),
    
    InvalidConfig2 = {type, [wrong_keyword, 10, 3, 30, 5, 50, 10]},
    ?assertEqual({error, invalid_config_format}, parse_rate_config(InvalidConfig2)),
    
    InvalidConfig3 = {type, [rate, -10, 3, 30, 5, 50, 10]},
    ?assertEqual({error, invalid_rate_value}, parse_rate_config(InvalidConfig3)),
    
    InvalidConfig4 = {type, [rate, 10, 3, 30]},
    ?assertEqual({error, invalid_config_format}, parse_rate_config(InvalidConfig4)).

get_rate_by_random_test() ->
    Rates = [{10, 3}, {30, 5}, {50, 10}],
    ?assertEqual({ok, 3}, get_rate_by_random(0, Rates)),
    ?assertEqual({ok, 3}, get_rate_by_random(10, Rates)),
    ?assertEqual({ok, 5}, get_rate_by_random(11, Rates)),
    ?assertEqual({ok, 5}, get_rate_by_random(30, Rates)),
    ?assertEqual({ok, 10}, get_rate_by_random(31, Rates)),
    ?assertEqual({ok, 10}, get_rate_by_random(50, Rates)),
    ?assertEqual({ok, no_change}, get_rate_by_random(51, Rates)),
    ?assertEqual({ok, no_change}, get_rate_by_random(100, Rates)).
-endif.