-module(card_checker).
-include("game.hrl").

%% API exports
-export([
    check_card_type/1,         % 检查牌型
    compare_cards/2,           % 比较两手牌
    is_valid_play/2,          % 验证出牌是否合法
    format_cards/1,           % 格式化牌的显示
    validate_cards/1          % 验证牌的合法性
]).

-type card() :: {integer(), atom()}.
-type cards() :: [card()].
-type card_type() :: atom().
-type card_value() :: integer().

%% API 函数实现

%% @doc 检查一组牌的类型
-spec check_card_type(cards()) -> {ok, card_type(), card_value()} | {error, invalid_type}.
check_card_type(Cards) when length(Cards) > 0 ->
    SortedCards = sort_cards(Cards),
    case identify_type(SortedCards) of
        {ok, _Type, _Value} = Result -> Result;
        Error -> Error
    end;
check_card_type([]) ->
    {error, invalid_type}.

%% @doc 比较两手牌的大小
-spec compare_cards(cards(), cards()) -> greater | lesser | invalid.
compare_cards(Cards1, Cards2) ->
    case {check_card_type(Cards1), check_card_type(Cards2)} of
        {{ok, Type1, Value1}, {ok, Type2, Value2}} ->
            compare_types_and_values(Type1, Value1, Type2, Value2);
        _ ->
            invalid
    end.

%% @doc 验证当前出牌是否合法（相对于上一手牌）
-spec is_valid_play(cards(), cards() | undefined) -> boolean().
is_valid_play(_NewCards, undefined) -> 
    true;
is_valid_play(NewCards, LastCards) ->
    case {check_card_type(NewCards), check_card_type(LastCards)} of
        {{ok, Type1, Value1}, {ok, Type2, Value2}} ->
            can_beat(Type1, Value1, Type2, Value2);
        _ ->
            false
    end.

%% @doc 格式化牌的显示
-spec format_cards(cards()) -> string().
format_cards(Cards) ->
    lists:map(fun format_card/1, Cards).

%% @private 统计值的出现次数
count_values(Values) ->
    Sorted = lists:sort(Values),
    count_values(Sorted, [], 0, none).

count_values([], Acc, _Count, _Value) when _Value =/= none, _Count > 0 ->
    lists:reverse([{_Value, _Count} | Acc]);
count_values([], Acc, _, _) ->
    lists:reverse(Acc);
count_values([H|T], Acc, _Count, none) ->
    count_values(T, Acc, 1, H);
count_values([H|T], Acc, Count, H) ->
    count_values(T, Acc, Count + 1, H);
count_values([H|T], Acc, Count, Value) ->
    count_values(T, [{Value, Count} | Acc], 1, H).

%% @private 格式化单张牌
format_card({Value, Suit}) ->
    SuitStr = case Suit of
        hearts -> "♥";
        diamonds -> "♦";
        clubs -> "♣";
        spades -> "♠";
        joker -> "J"
    end,
    ValueStr = case Value of
        ?CARD_VALUE_BIG_JOKER -> "BJ";
        ?CARD_VALUE_SMALL_JOKER -> "SJ";
        ?CARD_VALUE_2 -> "2";
        ?CARD_VALUE_A -> "A";
        ?CARD_VALUE_K -> "K";
        ?CARD_VALUE_Q -> "Q";
        ?CARD_VALUE_J -> "J";
        10 -> "10";
        N when N >= 3, N =< 9 -> integer_to_list(N)
    end,
    SuitStr ++ ValueStr.

%% @doc 验证牌的合法性
-spec validate_cards(cards()) -> boolean().
validate_cards(Cards) ->
    is_valid_card_list(Cards) andalso
    no_duplicate_cards(Cards) andalso
    all_cards_valid(Cards).

%% 内部函数

%% @private 识别牌型
identify_type(Cards) ->
    case length(Cards) of
        1 -> {ok, ?CARD_TYPE_SINGLE, get_card_value(hd(Cards))};
        2 -> check_pair_or_rocket(Cards);
        3 -> check_three(Cards);
        4 -> check_four_or_three_one(Cards);
        5 -> check_three_two(Cards);
        _ -> check_sequence_types(Cards)
    end.

%% @private 检查对子或火箭
check_pair_or_rocket([{V1, _S1}, {V2, _S2}]) ->
    if
        V1 =:= V2 -> {ok, ?CARD_TYPE_PAIR, V1};
        V1 =:= ?CARD_VALUE_SMALL_JOKER, V2 =:= ?CARD_VALUE_BIG_JOKER -> 
            {ok, ?CARD_TYPE_ROCKET, ?CARD_VALUE_BIG_JOKER};
        true -> {error, invalid_type}
    end.

%% @private 检查三张
check_three([{V, _}, {V, _}, {V, _}]) ->
    {ok, ?CARD_TYPE_THREE, V};
check_three(_) ->
    {error, invalid_type}.

%% @private 检查四张或三带一
check_four_or_three_one(Cards) ->
    Values = [V || {V, _} <- Cards],
    case count_values(Values) of
        [{V, 4}] -> 
            {ok, ?CARD_TYPE_BOMB, V};
        [{V, 3}, {_, 1}] -> 
            {ok, ?CARD_TYPE_THREE_ONE, V};
        [{_, 1}, {V, 3}] -> 
            {ok, ?CARD_TYPE_THREE_ONE, V};
        _ -> 
            {error, invalid_type}
    end.

%% @private 检查三带二
check_three_two(Cards) ->
    Values = [V || {V, _} <- Cards],
    case count_values(Values) of
        [{V, 3}, {_, 2}] -> {ok, ?CARD_TYPE_THREE_TWO, V};
        [{_, 2}, {V, 3}] -> {ok, ?CARD_TYPE_THREE_TWO, V};
        _ -> {error, invalid_type}
    end.

%% @private 检查顺子类型
check_sequence_types(Cards) ->
    case length(Cards) of
        L when L >= 5 ->
            Values = [V || {V, _} <- Cards],
            cond_check_sequence_types(Values, Cards);
        _ ->
            {error, invalid_type}
    end.

%% @private 条件检查顺子类型
cond_check_sequence_types(Values, Cards) ->
    case is_straight(Values) of
        true -> 
            {ok, ?CARD_TYPE_STRAIGHT, lists:max(Values)};
        false ->
            case is_straight_pairs(Values) of
                true -> 
                    {ok, ?CARD_TYPE_STRAIGHT_PAIR, lists:max(Values)};
                false ->
                    check_plane_types(Cards)
            end
    end.

%% @private 检查飞机类型
check_plane_types(Cards) ->
    Values = [V || {V, _} <- Cards],
    case check_plane_pattern(Values) of
        {ok, MainValue, WithWings} ->
            PlaneType = case WithWings of
                true -> ?CARD_TYPE_PLANE_ONE;
                false -> ?CARD_TYPE_PLANE
            end,
            {ok, PlaneType, MainValue};
        false ->
            {error, invalid_type}
    end.

%% @private 检查是否是顺子
is_straight(Values) ->
    SortedVals = lists:sort(Values),
    length(SortedVals) >= 5 andalso
    lists:max(SortedVals) < ?CARD_VALUE_2 andalso
    is_consecutive(SortedVals).

%% @private 检查是否是连对
is_straight_pairs(Values) ->
    case count_values(Values) of
        Pairs when length(Pairs) >= 3 ->
            PairValues = [V || {V, 2} <- Pairs],
            length(PairValues) * 2 =:= length(Values) andalso
            lists:max(PairValues) < ?CARD_VALUE_2 andalso
            is_consecutive(lists:sort(PairValues));
        _ ->
            false
    end.

%% @private 检查飞机模式
check_plane_pattern(Values) ->
    Counts = count_values(Values),
    ThreeCounts = [{V, C} || {V, C} <- Counts, C =:= 3],
    case length(ThreeCounts) >= 2 of
        true ->
            ThreeValues = [V || {V, _} <- ThreeCounts],
            SortedThrees = lists:sort(ThreeValues),
            case is_consecutive(SortedThrees) of
                true ->
                    MainValue = lists:max(SortedThrees),
                    HasWings = length(Values) > length(ThreeValues) * 3,
                    {ok, MainValue, HasWings};
                false ->
                    false
            end;
        false ->
            false
    end.



%% @private 检查是否连续
is_consecutive([]) -> true;
is_consecutive([_]) -> true;
is_consecutive([A,B|Rest]) ->
    case B - A of
        1 -> is_consecutive([B|Rest]);
        _ -> false
    end.



%% @private 比较类型和值
compare_types_and_values(Type, Value, Type, Value2) ->
    if
        Value > Value2 -> greater;
        true -> lesser
    end;
compare_types_and_values(?CARD_TYPE_ROCKET, _, _, _) ->
    greater;
compare_types_and_values(_, _, ?CARD_TYPE_ROCKET, _) ->
    lesser;
compare_types_and_values(?CARD_TYPE_BOMB, Value1, Type2, Value2) ->
    case Type2 of
        ?CARD_TYPE_BOMB when Value1 > Value2 -> greater;
        ?CARD_TYPE_BOMB -> lesser;
        _ -> greater
    end;
compare_types_and_values(_Type1, _, ?CARD_TYPE_BOMB, _) ->
    lesser;
compare_types_and_values(_, _, _, _) ->
    invalid.

%% @private 检查是否能打过上一手牌
can_beat(Type1, Value1, Type2, Value2) ->
    case {Type1, Type2} of
        {Same, Same} -> Value1 > Value2;
        {?CARD_TYPE_ROCKET, _} -> true;
        {?CARD_TYPE_BOMB, OtherType} when OtherType =/= ?CARD_TYPE_ROCKET -> true;
        _ -> false
    end.

%% @private 检查是否是有效的牌列表
is_valid_card_list(Cards) ->
    is_list(Cards) andalso length(Cards) > 0.

%% @private 检查是否有重复的牌
no_duplicate_cards(Cards) ->
    length(lists:usort(Cards)) =:= length(Cards).

%% @private 检查所有牌是否合法
all_cards_valid(Cards) ->
    lists:all(fun is_valid_card/1, Cards).

%% @private 检查单张牌是否合法
is_valid_card({Value, Suit}) ->
    ((Value >= ?CARD_VALUE_3 andalso Value =< ?CARD_VALUE_2) andalso
     lists:member(Suit, [hearts, diamonds, clubs, spades])) orelse
    ((Value >= ?CARD_VALUE_SMALL_JOKER andalso Value =< ?CARD_VALUE_BIG_JOKER) andalso
     Suit =:= joker).

%% @private 排序牌
sort_cards(Cards) ->
    lists:sort(fun({V1, S1}, {V2, S2}) ->
        if
            V1 =:= V2 -> S1 =< S2;
            true -> V1 =< V2
        end
    end, Cards).

%% @private 获取牌的值
get_card_value({Value, _}) -> Value.