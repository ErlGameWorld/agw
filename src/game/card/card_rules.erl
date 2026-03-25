-module(card_rules).
-include("game.hrl").
-export([validate_play/2, get_card_type/1, compare_cards/2, sort_cards/1]).

%% 验证出牌是否合法
%% Cards: Attempted play
%% LastPlay: Previous play (empty list or undefined if first play)
validate_play(Cards, []) ->
    case get_card_type(Cards) of
        {invalid, _} -> false;
        _ -> true
    end;
validate_play(Cards, undefined) ->
    validate_play(Cards, []);
validate_play(Cards, LastPlay) ->
    Type1 = get_card_type(Cards),
    Type2 = get_card_type(LastPlay),
    
    case {Type1, Type2} of
        {{invalid, _}, _} -> false;
        {_, {invalid, _}} -> false; % Should not happen if LastPlay was valid
        
        {{rocket, _}, _} -> true; % Rocket beats everything
        
        {{bomb, _}, {rocket, _}} -> false;
        {{bomb, _}, {bomb, V2}} -> 
            {bomb, V1} = Type1,
            V1 > V2;
        {{bomb, _}, _} -> true; % Bomb beats everything except rocket and bigger bomb
        
        {{Type, V1}, {Type, V2}} -> % Same type comparison
            {Len1, _} = get_length_and_extra(Cards, Type),
            {Len2, _} = get_length_and_extra(LastPlay, Type),
            case Len1 == Len2 of
                true -> V1 > V2;
                false -> false % Different lengths (e.g. straights)
            end;
            
        _ -> false
    end.

%% 获取牌型
%% Returns: {Type, MainValue} or {invalid, Reason}
get_card_type(Cards) ->
    Len = length(Cards),
    Sorted = sort_cards(Cards),
    Values = [V || {_, V} <- Sorted],
    Counts = count_values(Values),
    
    case Len of
        1 -> {single, hd(Values)};
        2 -> 
            case Values of
                [?CARD_VALUE_BIG_JOKER, ?CARD_VALUE_SMALL_JOKER] -> {rocket, ?CARD_VALUE_BIG_JOKER};
                [V, V] -> {pair, V};
                _ -> {invalid, not_pair}
            end;
        3 ->
            case maps:size(Counts) of
                1 -> {triple, hd(Values)};
                _ -> {invalid, not_triple}
            end;
        4 ->
            case maps:keys(Counts) of
                [_] -> {bomb, hd(Values)};
                _ -> check_three_with_one(Counts)
            end;
        _ ->
            check_complex_types(Values, Counts, Len)
    end.

%% 检查三带一
check_three_with_one(Counts) ->
    case find_n_count(Counts, 3) of
        [TripleVal] -> {three_one, TripleVal};
        _ -> {invalid, not_three_one}
    end.

%% 检查复杂牌型
check_complex_types(Values, Counts, Len) ->
    % Check for Straight (Single Sequence)
    IsStraight = is_straight(Values),
    if IsStraight andalso Len >= 5 -> {straight, lists:max(Values)};
       true ->
           % Check for Pair Sequence
           case is_pair_sequence(Values, Counts) of
               {true, MaxVal} -> {straight_pair, MaxVal};
               false ->
                    % Check for Three with Two (Pair)
                    case Len == 5 of
                        true -> check_three_with_two(Counts);
                        false ->
                            % Check for Four with Two
                            case check_four_with_two(Counts, Len) of
                                {true, Type, V} -> {Type, V};
                                false ->
                                    % Check for Plane
                                    check_plane(Counts, Len)
                            end
                    end
           end
    end.

check_three_with_two(Counts) ->
    case find_n_count(Counts, 3) of
        [TripleVal] ->
            case find_n_count(Counts, 2) of
                [_PairVal] -> {three_two, TripleVal};
                _ -> {invalid, not_three_two}
            end;
        _ -> {invalid, not_three_two}
    end.

check_four_with_two(Counts, Len) ->
    Fours = find_n_count(Counts, 4),
    case Fours of
        [FourVal] ->
            if 
                Len == 6 -> {true, four_two_single, FourVal}; % 4 + 2 singles
                Len == 8 -> 
                    % 4 + 2 pairs
                    Pairs = find_n_count(Counts, 2),
                    case length(Pairs) of
                        2 -> {true, four_two_pair, FourVal};
                        _ -> false % Could be 4 singles, but standard rule usually requires pairs
                    end;
                true -> false
            end;
        _ -> false
    end.

check_plane(Counts, Len) ->
    Triples = lists:sort(find_n_count(Counts, 3) ++ find_n_count(Counts, 4)), % 4 can be part of plane too if used as 3
    % Find longest consecutive triples sequence
    case find_longest_sequence(Triples) of
        [] -> {invalid, not_plane};
        Seqs ->
            % Try to match length
            % Plane basic: 3*N cards
            % Plane + 1: 3*N + N = 4*N cards
            % Plane + 2 (pairs): 3*N + 2*N = 5*N cards
            
            % Find a sequence that fits the length
            ValidSeq = lists:filter(fun(Seq) ->
                N = length(Seq),
                if
                    Len == N * 3 -> true; % Plane only
                    Len == N * 4 -> true; % Plane + singles
                    Len == N * 5 -> 
                        % Check if rest are pairs
                        check_plane_pairs(Counts, Seq, N);
                    true -> false
                end
            end, Seqs),
            
            case ValidSeq of
                [BestSeq | _] -> 
                    MaxVal = lists:max(BestSeq),
                    Type = if
                        Len == length(BestSeq) * 3 -> plane;
                        Len == length(BestSeq) * 4 -> plane_one;
                        Len == length(BestSeq) * 5 -> plane_two;
                        true -> invalid
                    end,
                    {Type, MaxVal};
                [] -> {invalid, bad_plane}
            end
    end.

check_plane_pairs(Counts, Seq, N) ->
    % For plane with pairs, we need N pairs in the rest
    % Seq are the values in the plane body (Triples)
    % We need to ensure that the remaining cards form exactly N pairs
    
    % 1. Create a copy of counts and remove the Plane body
    RemainingCounts = lists:foldl(fun(Val, Acc) ->
        maps:update_with(Val, fun(C) -> C - 3 end, Acc)
    end, Counts, Seq),
    
    % 2. Check if remaining cards form pairs
    % Filter out 0 counts first
    CleanCounts = maps:filter(fun(_, V) -> V > 0 end, RemainingCounts),
    
    % 3. Check if we have exactly N pairs
    Pairs = find_n_count(CleanCounts, 2),
    Fours = find_n_count(CleanCounts, 4), % 4 cards can be 2 pairs
    
    TotalPairs = length(Pairs) + length(Fours) * 2,
    
    % Also ensure no single cards or triples left (unless they form pairs, but here we check exact counts)
    % Simplified: Just check if TotalPairs == N and map is empty otherwise?
    % Actually, if CleanCounts has anything other than 2s and 4s, it's invalid.
    
    IsValidStructure = maps:fold(fun(_, V, Acc) ->
        Acc andalso (V == 2 orelse V == 4)
    end, true, CleanCounts),
    
    IsValidStructure andalso TotalPairs == N.

%% 辅助函数

%% Count occurrences of each value
count_values(Values) ->
    lists:foldl(fun(V, Acc) ->
        maps:update_with(V, fun(C) -> C + 1 end, 1, Acc)
    end, #{}, Values).

%% Find values that appear N times
find_n_count(Counts, N) ->
    maps:fold(fun(K, V, Acc) ->
        if V == N -> [K | Acc];
           true -> Acc
        end
    end, [], Counts).

%% Check straight (no 2, no Joker)
is_straight(Values) ->
    Max = lists:max(Values),
    Min = lists:min(Values),
    Len = length(Values),
    % No 2 (15) or Jokers (16, 17) in straight
    ValidVals = lists:all(fun(V) -> V < ?CARD_VALUE_2 end, Values),
    Unique = length(lists:usort(Values)) == Len,
    ValidVals andalso Unique andalso (Max - Min == Len - 1).

%% Check pair sequence (no 2, no Joker)
is_pair_sequence(Values, Counts) ->
    Pairs = find_n_count(Counts, 2),
    Len = length(Values),
    if 
        Len rem 2 /= 0 -> false;
        length(Pairs) /= Len div 2 -> false;
        length(Pairs) < 3 -> false;
        true ->
            SortedPairs = lists:sort(Pairs),
            Max = lists:max(SortedPairs),
            Min = lists:min(SortedPairs),
            PairLen = length(SortedPairs),
            ValidVals = lists:all(fun(V) -> V < ?CARD_VALUE_2 end, SortedPairs),
            IsSeq = (Max - Min == PairLen - 1),
            if 
                ValidVals andalso IsSeq -> {true, Max};
                true -> false
            end
    end.

%% Find consecutive sequences in a list of numbers
find_longest_sequence([]) -> [];
find_longest_sequence(List) ->
    Sorted = lists:usort(List),
    % Filter out 2 (15) and Jokers (16, 17) from plane triples
    Valid = lists:filter(fun(V) -> V < ?CARD_VALUE_2 end, Sorted),
    find_seqs(Valid).

find_seqs(List) ->
    find_seqs(List, [], []).

find_seqs([], Current, Acc) ->
    case length(Current) >= 2 of
        true -> [lists:reverse(Current) | Acc];
        false -> Acc
    end;
find_seqs([H|T], [], Acc) ->
    find_seqs(T, [H], Acc);
find_seqs([H|T], [Last|_CurrRest] = Current, Acc) ->
    if 
        H == Last + 1 -> find_seqs(T, [H|Current], Acc);
        true -> 
            NewAcc = case length(Current) >= 2 of
                true -> [lists:reverse(Current) | Acc];
                false -> Acc
            end,
            find_seqs(T, [H], NewAcc)
    end.

%% Helpers for validate_play
get_length_and_extra(Cards, _Type) ->
    {length(Cards), []}.

compare_cards(Cards1, Cards2) ->
    % This function is mainly for external use if needed
    % internal validate_play does the heavy lifting
    validate_play(Cards1, Cards2).

sort_cards(Cards) ->
    cards:sort_cards(Cards).
