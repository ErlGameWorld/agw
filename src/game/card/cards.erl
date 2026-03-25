-module(cards).
-export([init_cards/0, shuffle_cards/1, deal_cards/1, sort_cards/1, card_to_string/1]).

%% 初始化一副牌
%% Card structure: {Suit, Value}
%% Suits: 1=Spade, 2=Heart, 3=Club, 4=Diamond, 0=None
%% Values: 3-15 (3-2), 16 (Small Joker), 17 (Big Joker)
init_cards() ->
    Suits = [1, 2, 3, 4],
    Values = lists:seq(3, 15),
    Cards = [{Suit, Value} || Suit <- Suits, Value <- Values],
    [{0, 16}, {0, 17}] ++ Cards.

%% 洗牌
shuffle_cards(Cards) ->
    List = [{rand:uniform(), Card} || Card <- Cards],
    [Card || {_, Card} <- lists:sort(List)].

%% 发牌 - 返回{Player1Cards, Player2Cards, Player3Cards, LandlordCards}
deal_cards(Cards) ->
    {First17, Rest} = lists:split(17, Cards),
    {Second17, Rest2} = lists:split(17, Rest),
    {Third17, LandlordCards} = lists:split(17, Rest2),
    {sort_cards(First17), sort_cards(Second17), sort_cards(Third17), sort_cards(LandlordCards)}.

%% 排序牌 - 根据大小排序 (Descending: Big to Small)
sort_cards(Cards) ->
    lists:sort(
        fun({_, V1}, {_, V2}) ->
            V1 > V2
        end,
        Cards).

%% 转换为字符串显示
card_to_string({0, 16}) -> "Small Joker";
card_to_string({0, 17}) -> "Big Joker";
card_to_string({Suit, Value}) ->
    S = case Suit of
        1 -> "♠";
        2 -> "♥";
        3 -> "♣";
        4 -> "♦"
    end,
    V = case Value of
        11 -> "J";
        12 -> "Q";
        13 -> "K";
        14 -> "A";
        15 -> "2";
        N -> integer_to_list(N)
    end,
    S ++ V.
