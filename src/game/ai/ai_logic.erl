-module(ai_logic).

-export([analyze_hand/1, choose_bid/4, choose_play/4]).

%% ====================================================================
%% Hand Analysis
%% ====================================================================

%% Analyze Hand: Breaks down cards into logical sets (Bombs, Sequences, Triples, Pairs, Singles)
analyze_hand(Cards) ->
    Sorted = card_rules:sort_cards(Cards),
    Values = [V || {_, V} <- Sorted],
    Counts = count_values(Values),
    
    % Identify structures
    Bombs = find_n(Counts, 4),
    Triples = find_n(Counts, 3),
    Pairs = find_n(Counts, 2),
    Singles = find_n(Counts, 1),
    
    % Advanced: Identify straights and planes (Simplified for now, can be expanded)
    
    #{
        cards => Sorted, 
        values => Values, 
        counts => Counts,
        bombs => Bombs,
        triples => Triples,
        pairs => Pairs,
        singles => Singles,
        hand_value => calculate_hand_value(Values, Counts)
    }.

%% Calculate Unknown Cards (Card Counting / Memory)
%% Returns a map of value counts for cards NOT in my hand and NOT played
analyze_unknown_cards(MyCards, PlayedHistory) ->
    AllCards = cards:init_cards(),
    KnownCards = MyCards ++ PlayedHistory,
    
    % Calculate Unknowns = All - Known
    Unknowns = lists:foldl(fun(Card, Acc) ->
        lists:delete(Card, Acc)
    end, AllCards, KnownCards),
    
    SortedUnknowns = card_rules:sort_cards(Unknowns),
    UnknownValues = [V || {_, V} <- SortedUnknowns],
    count_values(UnknownValues).

count_values(Values) ->
    lists:foldl(fun(V, Acc) ->
        maps:update_with(V, fun(C) -> C + 1 end, 1, Acc)
    end, #{}, Values).

find_n(Counts, N) ->
    lists:sort([V || {V, C} <- maps:to_list(Counts), C == N]). % Exact match for simple classification

%% ====================================================================
%% Bidding Logic
%% ====================================================================

choose_bid(Hand, Bids, MinBid, Context) ->
    Analysis = analyze_hand(Hand),
    BidScore = calculate_bid_score(Analysis) + bid_pressure(Bids) + bid_position_bonus(Context, Bids) + endgame_bid_boost(Analysis) + bid_context_adjustment(Analysis, Context),
    MyBid = if
        BidScore >= 19 -> 3;
        BidScore >= 13 -> 2;
        BidScore >= 8 -> 1;
        true -> 0
    end,
    if MyBid > MinBid -> MyBid;
       true -> 0
    end.

calculate_hand_value(Values, Counts) ->
    Score = lists:foldl(fun(V, Acc) ->
        case V of
            17 -> Acc + 4; % Big Joker
            16 -> Acc + 3; % Small Joker
            15 -> Acc + 2; % 2
            14 -> Acc + 1; % A
            _ -> Acc
        end
    end, 0, Values),
    
    BombScore = maps:fold(fun(_, Count, Acc) ->
        if Count == 4 -> Acc + 3;
           true -> Acc
        end
    end, 0, Counts),
    
    Score + BombScore.

calculate_bid_score(#{values := Values, counts := Counts, hand_value := BaseScore}) ->
    RocketScore = case has_rocket(Counts) of true -> 5; false -> 0 end,
    BombCount = length(find_n(Counts, 4)),
    BombScore = BombCount * 3,
    TripleCount = length(find_n(Counts, 3)),
    TripleScore = TripleCount * 2,
    HighCardScore = count_high_cards(Values),
    LowSinglePenalty = count_low_single_cards(Counts),
    BaseScore + RocketScore + BombScore + TripleScore + HighCardScore - LowSinglePenalty.

has_rocket(Counts) ->
    maps:get(16, Counts, 0) > 0 andalso maps:get(17, Counts, 0) > 0.

count_high_cards(Values) ->
    lists:foldl(fun(V, Acc) ->
        if
            V >= 16 -> Acc + 2;
            V == 15 -> Acc + 2;
            V == 14 -> Acc + 1;
            V == 13 -> Acc + 1;
            true -> Acc
        end
    end, 0, Values).

count_low_single_cards(Counts) ->
    maps:fold(fun(V, C, Acc) ->
        if
            C == 1 andalso V =< 8 -> Acc + 1;
            true -> Acc
        end
    end, 0, Counts).

%% ====================================================================
%% Play Logic
%% ====================================================================

%% Free Turn
choose_play(Hand, [], Role, Context) ->
    Analysis = analyze_hand(Hand),
    #{cards := _Cards} = Analysis,
    
    % Strategy:
    % 1. If I can win in one turn, do it. (Not implemented fully yet, need precise hand splitting)
    % 2. Play sequences (Straight, Plane) first.
    % 3. Play Triples with kickers.
    % 4. Play Pairs.
    % 5. Play Singles.
    
    % Role-Specific Tweaks:
    % - Landlord: Aggressive.
    % - Peasant: 
    %   - If teammate (other peasant) has few cards (<=2), play small single/pair to help them.
    
    IsTeammateCritical = is_teammate_critical(Context, Role),
    
    if 
        IsTeammateCritical ->
            % Teammate needs help! Play smallest single/pair.
            play_smallest_unit(Analysis);
        true ->
            play_standard_opening(Analysis, Context)
    end;

%% Follow Turn
choose_play(Hand, LastPlay, Role, Context) ->
    Analysis = analyze_hand(Hand),
    Type = card_rules:get_card_type(LastPlay),
    
    PossibleMoves = find_moves(Analysis, LastPlay, Type),
    
    case PossibleMoves of
        [] ->
            fallback_pressure_move(Analysis, Role, Context);
        Moves ->
            best_response(Moves, LastPlay, Role, Context, Analysis)
    end.

%% ====================================================================
%% Strategy Helpers
%% ====================================================================

is_teammate_critical(#{players_cards := PlayerCards, my_index := MyIdx, landlord_index := LandlordIdx}, peasant) ->
    % Find teammate index
    TeammateIdx = find_teammate_index(MyIdx, LandlordIdx),
    TeammateCount = maps:get(TeammateIdx, PlayerCards, 17),
    TeammateCount =< 2;
is_teammate_critical(_, _) -> false.

find_teammate_index(MyIdx, LandlordIdx) ->
    % Indexes are 1, 2, 3.
    % If I am 1, Landlord 2 -> Teammate 3.
    lists:nth(1, [I || I <- [1,2,3], I /= MyIdx, I /= LandlordIdx]).

play_smallest_unit(#{singles := Singles, pairs := Pairs, cards := Cards} = _Analysis) ->
    PreferredSingles = prefer_non_control_singles(Singles),
    case PreferredSingles of
        [MinSingle | _] -> get_n_cards(Cards, MinSingle, 1);
        [] -> 
            case Pairs of
                [MinPair | _] -> get_n_cards(Cards, MinPair, 2);
                [] -> play_standard_opening(_Analysis, #{played_history => []}) % Fallback (should not happen if helper is used correctly, pass empty history for safe default)
            end
    end.

play_standard_opening(#{cards := Cards, counts := Counts} = Analysis, Context) ->
    History = maps:get(played_history, Context, []),
    UnknownCounts = analyze_unknown_cards(Cards, History),
    LeadControl = should_lead_control_card(Context),
    HighestSingle = find_highest_sure_single(Counts, UnknownCounts),
    
    case HighestSingle of
        {ok, HighCardVal} when LeadControl ->
            get_n_cards(Cards, HighCardVal, 1);
        none ->
            play_standard_structure(Analysis);
        _ ->
            play_standard_structure(Analysis)
    end.

find_highest_sure_single(MyCounts, UnknownCounts) ->
    check_boss(17, MyCounts, UnknownCounts).

check_boss(Val, _, _) when Val < 3 -> none;
check_boss(Val, MyCounts, UnknownCounts) ->
    MyCount = maps:get(Val, MyCounts, 0),
    _UnknownCount = maps:get(Val, UnknownCounts, 0),
    
    % Are there any higher cards in Unknown?
    HigherExists = lists:any(fun(V) -> maps:get(V, UnknownCounts, 0) > 0 end, lists:seq(Val + 1, 17)),
    
    if 
        HigherExists -> none; % Someone has a bigger card
        MyCount > 0 -> {ok, Val}; % I have the biggest remaining card!
        true -> check_boss(Val - 1, MyCounts, UnknownCounts) % Nobody has this, check next lower
    end.

play_standard_structure(#{values := Values, cards := Cards, counts := Counts}) ->
    % Priority: Straight -> Triple -> Pair -> Single
    case find_straight(Values) of
        {true, StraightVals} -> 
            get_cards_by_values(Cards, StraightVals);
        false ->
            case find_n(Counts, 3) of
                [MinTriple | _] -> 
                    % Try carry single
                    TripleCards = get_n_cards(Cards, MinTriple, 3),
                    case find_single_to_carry(Counts, [MinTriple]) of
                        {ok, SingleVal} -> TripleCards ++ get_n_cards(Cards, SingleVal, 1);
                        none -> TripleCards
                    end;
                [] ->
                    case find_n(Counts, 2) of
                        [MinPair | _] -> get_n_cards(Cards, MinPair, 2);
                        [] ->
                            [MinVal | _] = prefer_non_control_singles(lists:reverse(Values)),
                            get_n_cards(Cards, MinVal, 1)
                    end
            end
    end.

prefer_non_control_singles(Values) ->
    NoJokerOrTwo = [V || V <- Values, V =< 14],
    case NoJokerOrTwo of
        [] ->
            NoJoker = [V || V <- Values, V =< 15],
            case NoJoker of
                [] -> Values;
                _ -> NoJoker
            end;
        _ ->
            NoJokerOrTwo
    end.

best_response(Moves, LastPlay, Role, Context, Analysis) ->
    SortedMoves = sort_moves_by_value(Moves),
    case can_finish_with_move(Analysis, SortedMoves) of
        {true, Finisher} ->
            Finisher;
        false ->
            case should_force_control(Role, Context) of
                true -> choose_pressure_response(SortedMoves);
                false -> choose_role_response(SortedMoves, LastPlay, Role, Context, Analysis)
            end
    end.

can_finish_with_move(#{cards := Cards}, Moves) ->
    HandSize = length(Cards),
    case lists:filter(fun(M) -> length(M) == HandSize end, Moves) of
        [Finisher | _] -> {true, Finisher};
        [] -> false
    end.

choose_role_response(SortedMoves, LastPlay, Role, Context, Analysis) ->
    case Role of
        landlord ->
            evaluate_landlord_response(SortedMoves, LastPlay, Context, Analysis);
        peasant ->
            evaluate_peasant_response(SortedMoves, LastPlay, Context, Analysis)
    end.

evaluate_landlord_response(Moves, _LastPlay, Context, Analysis) ->
    case landlord_under_pressure(Context) of
        true -> choose_best_by_context(Moves, Context, Analysis, aggressive);
        false -> choose_best_by_context(Moves, Context, Analysis, conservative)
    end.

landlord_under_pressure(#{players_cards := PlayerCards, landlord_index := LandlordIdx}) ->
    maps:get(LandlordIdx, PlayerCards, 20) =< 2;
landlord_under_pressure(_) ->
    false.

evaluate_peasant_response(Moves, _LastPlay, Context, Analysis) ->
    LastPlayerIdx = maps:get(last_player_idx, Context, 0),
    MyIdx = maps:get(my_index, Context, 0),
    LandlordIdx = maps:get(landlord_index, Context, 0),
    PlayerCards = maps:get(players_cards, Context, #{}),
    LastPlayerCardsLeft = maps:get(LastPlayerIdx, PlayerCards, 17),
    IsTeammateLead = LastPlayerIdx =/= 0 andalso LastPlayerIdx =/= MyIdx andalso LastPlayerIdx =/= LandlordIdx,
    LandlordCardsLeft = maps:get(LandlordIdx, PlayerCards, 20),
    case {IsTeammateLead, LastPlayerCardsLeft =< 2} of
        {true, true} ->
            [];
        _ ->
            case LandlordCardsLeft =< 2 of
                true -> choose_best_by_context(Moves, Context, Analysis, aggressive);
                false -> choose_best_by_context(Moves, Context, Analysis, conservative)
            end
    end.

choose_best_by_context(Moves, Context, Analysis, Mode) ->
    [First | Rest] = Moves,
    lists:foldl(
        fun(Move, BestMove) ->
            MoveScore = contextual_move_score(Move, Context, Analysis, Mode),
            BestScore = contextual_move_score(BestMove, Context, Analysis, Mode),
            case MoveScore =< BestScore of
                true -> Move;
                false -> BestMove
            end
        end,
        First,
        Rest
    ).

contextual_move_score(Move, Context, Analysis, Mode) ->
    ShapeScore = move_shape_score(Move, Analysis, Context),
    Type = card_rules:get_card_type(Move),
    OppPressure = estimate_opponent_pressure(Context),
    AttackBonus = case {Mode, Type, OppPressure} of
        {aggressive, {single, V}, high} when V >= 14 -> -8;
        {aggressive, {pair, V}, high} when V >= 12 -> -6;
        {aggressive, {bomb, _}, high} -> -4;
        {conservative, {bomb, _}, _} -> 10;
        {conservative, {rocket, _}, _} -> 12;
        _ -> 0
    end,
    TeamProtectPenalty = defensive_penalty(Move, Context),
    ShapeScore + TeamProtectPenalty + AttackBonus.

choose_conservative_move(Moves, Context, Analysis) ->
    {NormalMoves, PowerMoves} = lists:partition(fun(M) -> not is_power_move(M) end, Moves),
    case NormalMoves of
        [_ | _] -> choose_best_by_shape(NormalMoves, Analysis, Context);
        [] ->
            case should_use_power_move(Context) of
                true -> hd(Moves);
                false ->
                    case PowerMoves of
                        [_ | _] -> choose_best_by_shape(PowerMoves, Analysis, Context);
                        [] -> hd(Moves)
                    end
            end
    end.

should_use_power_move(#{players_cards := PlayerCards, landlord_index := LandlordIdx}) ->
    maps:get(LandlordIdx, PlayerCards, 20) =< 2;
should_use_power_move(_) ->
    false.

is_power_move(Move) ->
    case card_rules:get_card_type(Move) of
        {bomb, _} -> true;
        {rocket, _} -> true;
        _ -> false
    end.

move_priority(Move) ->
    {Type, Val} = card_rules:get_card_type(Move),
    PowerWeight = case Type of
        rocket -> 1000;
        bomb -> 500;
        _ -> 0
    end,
    PowerWeight + Val * 10 + length(Move).

sort_moves_by_value(Moves) ->
    lists:sort(fun(A, B) ->
        move_priority(A) =< move_priority(B)
    end, Moves).

%% ====================================================================
%% Move Finder
%% ====================================================================

find_moves(#{cards := HandCards, counts := Counts}, LastPlay, {Type, Val}) ->
    % Basic type matching
    SameTypeMoves = find_same_type_moves(HandCards, Counts, Type, Val, length(LastPlay)),
    
    % Bombs and Rockets
    Bombs = find_bombs(HandCards, Counts),
    Rocket = find_rocket(HandCards, Counts),
    
    case Type of
        rocket -> [];
        bomb -> 
            BiggerBombs = lists:filter(fun(B) -> 
                {bomb, BVal} = card_rules:get_card_type(B),
                BVal > Val
            end, Bombs),
            BiggerBombs ++ Rocket;
        _ ->
            SameTypeMoves ++ Bombs ++ Rocket
    end.

find_same_type_moves(Cards, Counts, single, Val, _LastLen) ->
    Candidates = lists:filter(fun(V) -> V > Val end, maps:keys(Counts)),
    [get_n_cards(Cards, V, 1) || V <- lists:sort(Candidates)];

find_same_type_moves(Cards, Counts, pair, Val, _LastLen) ->
    Candidates = lists:filter(fun(V) -> maps:get(V, Counts) >= 2 andalso V > Val end, maps:keys(Counts)),
    [get_n_cards(Cards, V, 2) || V <- lists:sort(Candidates)];

find_same_type_moves(Cards, Counts, triple, Val, _LastLen) ->
    Candidates = lists:filter(fun(V) -> maps:get(V, Counts) >= 3 andalso V > Val end, maps:keys(Counts)),
    [get_n_cards(Cards, V, 3) || V <- lists:sort(Candidates)];

find_same_type_moves(Cards, Counts, three_one, Val, _LastLen) ->
    Triples = lists:filter(fun(V) -> maps:get(V, Counts) >= 3 andalso V > Val end, maps:keys(Counts)),
    lists:flatmap(fun(T) ->
        case find_single_to_carry(Counts, [T]) of
            {ok, S} -> [get_n_cards(Cards, T, 3) ++ get_n_cards(Cards, S, 1)];
            none -> []
        end
    end, lists:sort(Triples));

find_same_type_moves(Cards, Counts, three_two, Val, _LastLen) ->
    Triples = lists:filter(fun(V) -> maps:get(V, Counts) >= 3 andalso V > Val end, maps:keys(Counts)),
    lists:flatmap(fun(T) ->
        case find_pair_to_carry(Counts, [T]) of
            {ok, P} -> [get_n_cards(Cards, T, 3) ++ get_n_cards(Cards, P, 2)];
            none -> []
        end
    end, lists:sort(Triples));

find_same_type_moves(Cards, Counts, straight, Val, LastLen) ->
    Values = lists:sort([V || {V, C} <- maps:to_list(Counts), C >= 1, V < 15]),
    SeqVals = find_sequences_by_len(Values, LastLen),
    Bigger = lists:filter(fun(S) -> lists:max(S) > Val end, SeqVals),
    [get_cards_by_values(Cards, S) || S <- Bigger];

find_same_type_moves(Cards, Counts, straight_pair, Val, LastLen) ->
    Values = lists:sort([V || {V, C} <- maps:to_list(Counts), C >= 2, V < 15]),
    PairLen = LastLen div 2,
    SeqVals = find_sequences_by_len(Values, PairLen),
    Bigger = lists:filter(fun(S) -> lists:max(S) > Val end, SeqVals),
    [lists:flatten([get_n_cards(Cards, V, 2) || V <- S]) || S <- Bigger];

find_same_type_moves(_, _, _, _, _) -> [].

find_bombs(Cards, Counts) ->
    BombVals = lists:filter(fun(V) -> maps:get(V, Counts) == 4 end, maps:keys(Counts)),
    [get_n_cards(Cards, V, 4) || V <- lists:sort(BombVals)].

find_rocket(Cards, Counts) ->
    HasSmall = maps:get(16, Counts, 0) == 1,
    HasBig = maps:get(17, Counts, 0) == 1,
    if HasSmall andalso HasBig -> [get_cards_by_values(Cards, [16, 17])];
       true -> []
    end.

%% ====================================================================
%% Helpers
%% ====================================================================

find_single_to_carry(Counts, Exclude) ->
    Singles = [V || {V, C} <- maps:to_list(Counts), C == 1, not lists:member(V, Exclude)],
    case Singles of
        [_ | _] ->
            {ok, lists:min(Singles)};
        [] ->
            Pairs = [V || {V, C} <- maps:to_list(Counts), C == 2, not lists:member(V, Exclude)],
            case Pairs of
                [_ | _] -> {ok, lists:min(Pairs)};
                [] -> none
            end
    end.

find_pair_to_carry(Counts, Exclude) ->
    Candidates = [V || {V, C} <- maps:to_list(Counts), C >= 2, not lists:member(V, Exclude)],
    case Candidates of
        [] -> none;
        _ -> {ok, lists:min(Candidates)}
    end.

find_straight(Values) ->
    ValidVals = lists:sort(lists:usort([V || V <- Values, V < 15])),
    case find_longest_sequence(ValidVals) of
        Seq when length(Seq) >= 5 -> {true, Seq};
        _ -> false
    end.

find_longest_sequence([]) -> [];
find_longest_sequence([H | T]) ->
    find_longest_sequence(T, [H], [H]).

find_longest_sequence([], Current, Best) ->
    if
        length(Current) > length(Best) -> Current;
        true -> Best
    end;
find_longest_sequence([H | T], Current = [Last | _], Best) ->
    case H == Last + 1 of
        true ->
            NewCurrent = Current ++ [H],
            NewBest = if
                length(NewCurrent) > length(Best) -> NewCurrent;
                true -> Best
            end,
            find_longest_sequence(T, NewCurrent, NewBest);
        false ->
            find_longest_sequence(T, [H], Best)
    end.

find_sequences_by_len(_Values, Len) when Len =< 0 ->
    [];
find_sequences_by_len(Values, Len) ->
    find_sequences_by_len(Values, Len, [], [], 0).

find_sequences_by_len([], Len, Current, Acc, _) ->
    finalize_sequences(Len, Current, Acc);
find_sequences_by_len([V | Rest], Len, [], Acc, _) ->
    find_sequences_by_len(Rest, Len, [V], Acc, V);
find_sequences_by_len([V | Rest], Len, Current, Acc, Last) ->
    if
        V == Last + 1 ->
            find_sequences_by_len(Rest, Len, Current ++ [V], Acc, V);
        true ->
            NewAcc = finalize_sequences(Len, Current, Acc),
            find_sequences_by_len(Rest, Len, [V], NewAcc, V)
    end.

finalize_sequences(Len, Current, Acc) ->
    if
        length(Current) < Len -> Acc;
        true ->
            Acc ++ sliding_windows(Current, Len)
    end.

sliding_windows(List, Len) when length(List) < Len ->
    [];
sliding_windows(List, Len) ->
    [lists:sublist(List, Len) | sliding_windows(tl(List), Len)].

get_n_cards(Cards, Val, N) ->
    Matching = [C || C = {_, V} <- Cards, V == Val],
    lists:sublist(Matching, N).

get_cards_by_values(Cards, Values) ->
    {Result, _} = lists:foldl(fun(V, {Acc, RemCards}) ->
        case lists:keytake(V, 2, RemCards) of
            {value, Card, NewRem} -> {[Card|Acc], NewRem};
            false -> {Acc, RemCards}
        end
    end, {[], Cards}, Values),
    lists:reverse(Result).

bid_pressure(Bids) ->
    MaxBid = case Bids of
        [] -> 0;
        _ -> lists:max([S || {_, S} <- Bids])
    end,
    case {length(Bids), MaxBid} of
        {2, 0} -> 1;
        {_, 2} -> -2;
        {_, 3} -> -4;
        _ -> 0
    end.

bid_position_bonus(Context, Bids) ->
    MyIdx = maps:get(my_index, Context, 0),
    case {length(Bids), MyIdx} of
        {2, 3} -> 1;
        _ -> 0
    end.

should_lead_control_card(Context) ->
    PlayerCards = maps:get(players_cards, Context, #{}),
    MyIdx = maps:get(my_index, Context, 0),
    MyCount = maps:get(MyIdx, PlayerCards, 17),
    Others = [C || {Idx, C} <- maps:to_list(PlayerCards), Idx =/= MyIdx],
    OppMin = case Others of
        [] -> 17;
        _ -> lists:min(Others)
    end,
    MyCount =< 5 orelse OppMin =< 2.

choose_best_by_shape([First | Rest], Analysis, Context) ->
    lists:foldl(
        fun(Move, BestMove) ->
            case move_shape_score(Move, Analysis, Context) =< move_shape_score(BestMove, Analysis, Context) of
                true -> Move;
                false -> BestMove
            end
        end,
        First,
        Rest
    ).

move_shape_score(Move, #{counts := Counts, cards := Cards}, Context) ->
    Remaining = length(Cards) - length(Move),
    {_, MoveMain} = card_rules:get_card_type(Move),
    RemainingCards = remove_cards(Cards, Move),
    RemainingSteps = estimate_steps(RemainingCards),
    UsedCounts = count_values([V || {_, V} <- Move]),
    BreakPenalty = maps:fold(
        fun(V, Used, Acc) ->
            Total = maps:get(V, Counts, 0),
            PiecePenalty = case {Total, Used < Total} of
                {4, true} -> 14;
                {3, true} -> 9;
                {2, true} -> 4;
                _ -> 0
            end,
            Acc + PiecePenalty
        end,
        0,
        UsedCounts
    ),
    PowerPenalty = case is_power_move(Move) andalso not should_use_power_move(Context) of
        true -> 20;
        false -> 0
    end,
    FinishBonus = case can_clear_next_turn(RemainingCards) of
        true -> 16;
        false -> 0
    end,
    EndgameBonus = if Remaining =< 5 -> length(Move) * 2; true -> 0 end,
    BreakPenalty + PowerPenalty + MoveMain + RemainingSteps * 2 - EndgameBonus - FinishBonus.

endgame_bid_boost(#{bombs := Bombs, triples := Triples, singles := Singles}) ->
    case {length(Bombs), length(Triples), length(Singles)} of
        {B, T, S} when B >= 1, T >= 1, S =< 2 -> 2;
        {B, _, S} when B >= 2, S =< 3 -> 2;
        _ -> 0
    end.

should_force_control(landlord, Context) ->
    PlayerCards = maps:get(players_cards, Context, #{}),
    MyIdx = maps:get(my_index, Context, 0),
    Others = [C || {Idx, C} <- maps:to_list(PlayerCards), Idx =/= MyIdx],
    case Others of
        [] -> false;
        _ -> lists:min(Others) =< 2
    end;
should_force_control(peasant, Context) ->
    LandlordIdx = maps:get(landlord_index, Context, 0),
    PlayerCards = maps:get(players_cards, Context, #{}),
    maps:get(LandlordIdx, PlayerCards, 20) =< 2;
should_force_control(_, _) ->
    false.

choose_pressure_response(Moves) ->
    Normal = [M || M <- Moves, not is_power_move(M)],
    case Normal of
        [] -> lists:last(Moves);
        _ -> lists:last(Normal)
    end.

fallback_pressure_move(Analysis, landlord, Context) ->
    case estimate_opponent_pressure(Context) of
        high ->
            Bombs = find_bombs(maps:get(cards, Analysis), maps:get(counts, Analysis)),
            case Bombs of
                [Bomb | _] -> Bomb;
                [] -> []
            end;
        _ -> []
    end;
fallback_pressure_move(_, _, _) ->
    [].

estimate_opponent_pressure(#{players_cards := PlayerCards, my_index := MyIdx}) ->
    Others = [Cnt || {Idx, Cnt} <- maps:to_list(PlayerCards), Idx =/= MyIdx],
    MinCnt = case Others of
        [] -> 17;
        _ -> lists:min(Others)
    end,
    if
        MinCnt =< 2 -> high;
        MinCnt =< 4 -> medium;
        true -> low
    end;
estimate_opponent_pressure(_) ->
    low.

defensive_penalty(_Move, #{landlord_index := 0}) ->
    0;
defensive_penalty(Move, #{my_index := MyIdx, landlord_index := LandlordIdx, last_player_idx := LastPlayerIdx}) when MyIdx =/= LandlordIdx ->
    IsTeammateLead = LastPlayerIdx =/= 0 andalso LastPlayerIdx =/= MyIdx andalso LastPlayerIdx =/= LandlordIdx,
    IsPowerMove = is_power_move(Move),
    case {IsTeammateLead, IsPowerMove} of
        {true, true} -> 10;
        _ -> 0
    end;
defensive_penalty(_, _) ->
    0.

remove_cards(Cards, ToRemove) ->
    lists:foldl(fun(Card, Acc) -> lists:delete(Card, Acc) end, Cards, ToRemove).

can_clear_next_turn([]) ->
    true;
can_clear_next_turn(Cards) ->
    case card_rules:get_card_type(Cards) of
        {invalid, _} -> false;
        _ -> true
    end.

estimate_steps([]) ->
    0;
estimate_steps(Cards) ->
    case can_clear_next_turn(Cards) of
        true ->
            1;
        false ->
            Analysis = analyze_hand(Cards),
            Singles = maps:get(singles, Analysis, []),
            Pairs = maps:get(pairs, Analysis, []),
            Triples = maps:get(triples, Analysis, []),
            Bombs = maps:get(bombs, Analysis, []),
            max(1, length(Singles) + length(Pairs) + length(Triples) + length(Bombs))
    end.

bid_context_adjustment(Analysis, Context) ->
    Pressure = estimate_opponent_pressure(Context),
    Bombs = length(maps:get(bombs, Analysis, [])),
    Triples = length(maps:get(triples, Analysis, [])),
    Singles = length(maps:get(singles, Analysis, [])),
    case {Pressure, Bombs, Triples, Singles} of
        {high, B, T, _} when B >= 1, T >= 1 -> 2;
        {high, B, _, _} when B >= 2 -> 2;
        {low, 0, 0, S} when S >= 6 -> -2;
        _ -> 0
    end.
