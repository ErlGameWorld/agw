-module(weight_lib).
-export([get_random_weight/1, parse_weight_config/1]).

%% @doc 根据权重配置获取随机权重值
%% 示例: {type, [weight,50,3,30,5,40,10]} 表示
%% 1-50%的机率加3点星级
%% 51-80%的机率加5点星级
%% 81-100%的机率加10点星级
get_random_weight(Config) ->
    case parse_weight_config(Config) of
        {error, Reason} ->
            {error, Reason};
        {ok, Weights} ->
            RandomNum = generate_random_number(1, 100),
            get_weight_by_random(RandomNum, Weights, 0)
    end.

%% @doc 解析权重配置
%% 返回格式: {ok, [{Range, Value}]}
%% 例如: {ok, [{50, 3}, {30, 5}, {20, 10}]}
parse_weight_config({type, [weight | Rest]}) ->
    parse_weight_pairs(Rest, [], 0);
parse_weight_config(_) ->
    {error, invalid_config_format}.

%% @private 解析权重配对
parse_weight_pairs([], Acc, _) ->
    {ok, lists:reverse(Acc)};
parse_weight_pairs([Weight, Value | Rest], Acc, CurrentSum) ->
    case is_integer(Weight) andalso Weight > 0 andalso is_integer(Value) of
        true ->
            parse_weight_pairs(Rest, [{Weight, Value} | Acc], CurrentSum + Weight);
        false ->
            {error, invalid_weight_value}
    end;
parse_weight_pairs(_, _, _) ->
    {error, invalid_config_format}.

%% @private 根据随机数获取对应的权重值
get_weight_by_random(_, [], _) ->
    {error, no_matching_weight};
get_weight_by_random(RandomNum, [{Weight, Value} | Rest], AccWeight) ->
    NextWeight = AccWeight + Weight,
    if
        RandomNum =< NextWeight -> {ok, Value};
        true -> get_weight_by_random(RandomNum, Rest, NextWeight)
    end.

%% @private 生成指定范围内的随机数
generate_random_number(Min, Max) ->
    % 确保随机数生成器已初始化
    _ = case erlang:whereis(random_seed) of
        undefined -> rand:seed(exsplus);
        _ -> ok
    end,
    Min + rand:uniform(Max - Min + 1) - 1.

%% @doc 测试函数
-ifdef(TEST).
-include_lib("eunit/include/eunit.hrl").

parse_weight_config_test() ->
    Config = {type, [weight, 50, 3, 30, 5, 20, 10]},
    ?assertEqual({ok, [{50, 3}, {30, 5}, {20, 10}]}, parse_weight_config(Config)),
    
    InvalidConfig1 = {wrong_type, [weight, 50, 3, 30, 5, 20, 10]},
    ?assertEqual({error, invalid_config_format}, parse_weight_config(InvalidConfig1)),
    
    InvalidConfig2 = {type, [wrong_keyword, 50, 3, 30, 5, 20, 10]},
    ?assertEqual({error, invalid_config_format}, parse_weight_config(InvalidConfig2)),
    
    InvalidConfig3 = {type, [weight, -50, 3, 30, 5, 20, 10]},
    ?assertEqual({error, invalid_weight_value}, parse_weight_config(InvalidConfig3)),
    
    InvalidConfig4 = {type, [weight, 50, 3, 30]},
    ?assertEqual({error, invalid_config_format}, parse_weight_config(InvalidConfig4)).

get_weight_by_random_test() ->
    Weights = [{50, 3}, {30, 5}, {20, 10}],
    ?assertEqual({ok, 3}, get_weight_by_random(1, Weights, 0)),
    ?assertEqual({ok, 3}, get_weight_by_random(50, Weights, 0)),
    ?assertEqual({ok, 5}, get_weight_by_random(51, Weights, 0)),
    ?assertEqual({ok, 5}, get_weight_by_random(80, Weights, 0)),
    ?assertEqual({ok, 10}, get_weight_by_random(81, Weights, 0)),
    ?assertEqual({ok, 10}, get_weight_by_random(100, Weights, 0)).
-endif.