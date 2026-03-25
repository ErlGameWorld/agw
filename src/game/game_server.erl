-module(game_server).
-behaviour(gen_server).

-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([joinGame/3, startGame/1, resetGame/1, leaveGame/2, playCards/3, pass/2, bid/3, playHint/2, getState/1, subtractCards/2]).

-record(player, {
    pid,
    name,
    cards = [],
    role = none, % none, landlord, peasant
    index,       % 1, 2, 3
    is_trusteeship = false
}).

-record(state, {
    room_id,              % Room ID
    players = [],         % [player record]
    current_turn = 0,     % 1, 2, 3
    landlord_idx = 0,
    landlord_cards = [],
    last_play_idx = 0,    % Who played the last valid cards
    last_play_cards = [], % The cards played
    pass_count = 0,       % How many passed in a row
    game_status = waiting, % waiting, bidding, playing, finished
    base_score = 0,       % 1, 2, 3
    bids = [],            % [{Idx, Score}]
    multiplier = 1,       % Game multiplier
    timer_ref = undefined, % Store the timer reference
    timeout_duration = 30000, % 30 seconds
    played_history = []   % All cards played in this game
}).

%% API
start_link(RoomId) ->
    gen_server:start_link(?MODULE, [RoomId], []).

joinGame(GamePid, PlayerPid, PlayerName) ->
    gen_server:call(GamePid, {eJoinGame, PlayerPid, PlayerName}).

startGame(GamePid) ->
    gen_server:call(GamePid, eStartGame).

leaveGame(GamePid, PlayerPid) ->
    gen_server:call(GamePid, {eLeaveGame, PlayerPid}).

resetGame(GamePid) ->
    gen_server:call(GamePid, eResetGame).

playCards(GamePid, PlayerPid, Cards) ->
    gen_server:call(GamePid, {ePlayCards, PlayerPid, Cards}).

pass(GamePid, PlayerPid) ->
    gen_server:call(GamePid, {ePass, PlayerPid}).

bid(GamePid, PlayerPid, Score) ->
    gen_server:call(GamePid, {eBid, PlayerPid, Score}).

playHint(GamePid, PlayerPid) ->
    gen_server:call(GamePid, {ePlayHint, PlayerPid}).

getState(GamePid) ->
    gen_server:call(GamePid, eGetState).

%% Callbacks
init([RoomId]) ->
    process_flag(trap_exit, true),
    {ok, #state{room_id = RoomId}}.

handle_call({eJoinGame, PlayerPid, PlayerName}, _From, State = #state{players = Players, game_status = Status}) ->
    % If game is playing, check if we can reconnect (replace ghost)
    case Status of
        waiting ->
            if length(Players) >= 3 ->
                {reply, {error, game_full}, State};
            true ->
                NewIndex = length(Players) + 1,
                erlang:monitor(process, PlayerPid),
                NewPlayer = #player{pid = PlayerPid, name = PlayerName, index = NewIndex, is_trusteeship = false},
                NewPlayers = Players ++ [NewPlayer],
                {reply, {ok, NewIndex}, State#state{players = NewPlayers}}
            end;
        _ ->
            % Try to find a trusteeship player with same name to reconnect
            case lists:keyfind(PlayerName, #player.name, Players) of
                #player{is_trusteeship = true, index = Idx} = P ->
                    erlang:monitor(process, PlayerPid),
                    NewPlayer = P#player{pid = PlayerPid, is_trusteeship = false},
                    NewPlayers = lists:keyreplace(Idx, #player.index, Players, NewPlayer),
                    
                    % Send sync info (cards, state)
                    % TODO: Send full state sync
                    
                    {reply, {ok, Idx}, State#state{players = NewPlayers}};
                _ ->
                    {reply, {error, game_already_started}, State}
            end
    end;

handle_call({eLeaveGame, PlayerPid}, _From, State = #state{room_id = RoomId}) ->
    {Result, NewState} = do_leave_game(PlayerPid, State),
    
    % If game aborted (status became waiting and players removed), notify room manager
    % But do_leave_game handles waiting/playing differently.
    % If playing -> trusteeship -> no updates -> room manager should NOT set to waiting.
    % If waiting -> removed -> updates -> room manager updates list.
    
    % Wait, if everyone leaves (all trusteeship), we should probably abort?
    % Let's check if all players are trusteeship
    #state{players = CurrentPlayers} = NewState,
    AllTrusteeship = lists:all(fun(P) -> P#player.is_trusteeship end, CurrentPlayers),
    
    FinalState = if AllTrusteeship andalso length(CurrentPlayers) > 0 ->
        % Abort game
        notify_game_abort(CurrentPlayers),
        room_manager:updateRoomStatus(RoomId, finished),
        NewState#state{
            players = [],
            game_status = waiting,
            bids = [],
            played_history = [],
            current_turn = 0
        };
    true ->
        NewState
    end,

    {reply, Result, FinalState};

handle_call(eResetGame, _From, State = #state{players = Players}) ->
    % Reset players cards and roles
    ResetPlayers = reset_players(Players),
    notify_restart(ResetPlayers),
    {reply, ok, State#state{
        players = ResetPlayers,
        game_status = waiting,
        bids = [],
        multiplier = 1,
        current_turn = 0,
        landlord_idx = 0,
        landlord_cards = [],
        last_play_idx = 0,
        last_play_cards = [],
        pass_count = 0
    }};

handle_call(eStartGame, _From, State = #state{players = Players, game_status = waiting}) ->
    case length(Players) of
        3 ->
            % Initialize Deck
            Cards = cards:shuffle_cards(cards:init_cards()),
            {P1Cards, P2Cards, P3Cards, LandlordCards} = cards:deal_cards(Cards),
            
            % Update Players with Cards
            [P1, P2, P3] = Players,
            NewPlayers = [
                P1#player{cards = P1Cards, is_trusteeship = false},
                P2#player{cards = P2Cards, is_trusteeship = false},
                P3#player{cards = P3Cards, is_trusteeship = false}
            ],
            
            % Notify players of their cards
            FirstBidder = rand:uniform(3),
            notify_game_start(NewPlayers, FirstBidder),
            
            notify_turn_to_bid(NewPlayers, FirstBidder, []),

            StateWithTimer = start_timer(State#state{
                players = NewPlayers,
                landlord_cards = LandlordCards,
                game_status = bidding,
                current_turn = FirstBidder,
                bids = [],
                played_history = []
            }, eBidTimeout),

            StateWithAuto = check_auto_play(StateWithTimer),

            {reply, {ok, bidding, FirstBidder}, StateWithAuto};
        _ ->
            {reply, {error, not_enough_players}, State}
    end;

handle_call(eStartGame, _From, State) ->
    {reply, {error, game_not_waiting}, State};

handle_call({eBid, PlayerPid, Score}, _From, State = #state{game_status = bidding, current_turn = Turn, players = Players, bids = Bids}) ->
    Player = get_player_by_pid(Players, PlayerPid),
    case Player of
        #player{index = Turn} ->
            MaxBid = get_max_bid(Bids),
            IsValidScore = is_integer(Score) andalso Score >= 0 andalso Score =< 3,
            ValidBid = IsValidScore andalso (Score == 0 orelse Score > MaxBid),
            
            case ValidBid of
                true ->
                    State0 = cancel_timer(State),
                    NewBids = [{Turn, Score} | Bids],
                    NextTurn = (Turn rem 3) + 1,
                    
                    notify_bid_made(Players, Turn, Score),

                    IsBiddingDone = length(NewBids) == 3 orelse Score == 3,
                    
                    case IsBiddingDone of
                        true ->
                            HighestBid = get_highest_bidder(NewBids),
                            case HighestBid of
                                {LandlordIdx, WinningScore} when WinningScore > 0 ->
                                    NewState = start_playing(State0#state{bids = NewBids}, LandlordIdx, WinningScore),
                                    StateWithAuto = check_auto_play(NewState),
                                    {reply, {ok, playing}, StateWithAuto};
                                _ -> 
                                    notify_restart(Players),
                                    RestartState = State0#state{
                                        players = reset_players(Players),
                                        game_status = waiting,
                                        bids = [],
                                        current_turn = 0,
                                        landlord_idx = 0,
                                        landlord_cards = [],
                                        last_play_idx = 0,
                                        last_play_cards = [],
                                        pass_count = 0,
                                        played_history = []
                                    },
                                    {reply, {error, not_enough_players}, RestartState}
                            end;
                        false ->
                             notify_turn_to_bid(Players, NextTurn, NewBids),
                             StateWithTimer = start_timer(State0#state{current_turn = NextTurn, bids = NewBids}, eBidTimeout),
                             StateWithAuto = check_auto_play(StateWithTimer),
                             {reply, {ok, next_bidder, NextTurn}, StateWithAuto}
                    end;
                false ->
                    {reply, {error, invalid_bid}, State}
            end;
        _ ->
            {reply, {error, not_your_turn}, State}
    end;

handle_call({ePlayCards, PlayerPid, Cards}, _From, State = #state{game_status = playing, current_turn = Turn, players = Players, last_play_cards = LastCards, last_play_idx = LastIdx, multiplier = Mult, played_history = History, room_id = RoomId}) ->
    State0 = cancel_timer(State),
    Player = get_player_by_pid(Players, PlayerPid),
    case Player of
        #player{index = Turn} ->
            % Validate Play
            IsNewRound = (LastIdx == Turn) orelse (LastIdx == 0),
            RefCards = if IsNewRound -> []; true -> LastCards end,
            
            case card_rules:validate_play(Cards, RefCards) of
                true ->
                    % Update Multiplier
                    NewMult = case card_rules:get_card_type(Cards) of
                        {bomb, _} -> Mult * 2;
                        {rocket, _} -> Mult * 2;
                        _ -> Mult
                    end,

                    % Remove cards
                    CurrentCards = Player#player.cards,
                    case subtractCards(CurrentCards, Cards) of
                        {ok, NewHand} ->
                            NewPlayer = Player#player{cards = NewHand},
                            NewPlayers = lists:keyreplace(Player#player.pid, #player.pid, Players, NewPlayer),
                            
                            notify_player_played(Players, Turn, Cards),
                            
                            NewHistory = History ++ Cards,

                            % Check Win
                            case length(NewHand) == 0 of
                                true ->
                                    Scores = calculate_scores(NewPlayers, Player#player.index, State0#state.base_score, NewMult),
                                    notify_game_over(NewPlayers, Player#player.index, Scores),
                                    update_system_scores(NewPlayers, Scores),
                                    
                                    % Remove trusteeship players and reset for next game
                                    FinalPlayers = lists:filter(fun(P) -> not P#player.is_trusteeship end, NewPlayers),
                                    
                                    % Notify Room Manager
                                    room_manager:updateRoomStatus(RoomId, finished),
                                    
                                    {reply, {game_over, winner, Player#player.index, Scores}, State0#state{
                                        players = reset_players(FinalPlayers), 
                                        game_status = waiting,
                                        multiplier = 1,
                                        played_history = [],
                                        bids = [],
                                        current_turn = 0,
                                        landlord_idx = 0,
                                        landlord_cards = [],
                                        last_play_idx = 0,
                                        last_play_cards = [],
                                        pass_count = 0
                                    }};
                                false ->
                                    NextTurn = (Turn rem 3) + 1,
                                    notify_turn_to_play(Players, NextTurn, Cards),
                                    
                                    StateWithTimer = start_timer(State0#state{
                                        players = NewPlayers,
                                        current_turn = NextTurn,
                                        last_play_idx = Turn,
                                        last_play_cards = Cards,
                                        pass_count = 0,
                                        multiplier = NewMult,
                                        played_history = NewHistory
                                    }, turn_timeout),
                                    
                                    StateWithAuto = check_auto_play(StateWithTimer),
                                    
                                    {reply, {ok, played}, StateWithAuto}
                            end;
                        error ->
                            {reply, {error, cards_not_in_hand}, State}
                    end;
                false ->
                    {reply, {error, invalid_play_rules}, State}
            end;
        _ ->
            {reply, {error, not_your_turn}, State}
    end;

handle_call({ePass, PlayerPid}, _From, State = #state{game_status = playing, current_turn = Turn, players = Players, last_play_idx = LastIdx}) ->
    State0 = cancel_timer(State),
    Player = get_player_by_pid(Players, PlayerPid),
    case Player of
        #player{index = Turn} ->
            % Cannot pass if it's new round (you must play)
            IsNewRound = (LastIdx == Turn) orelse (LastIdx == 0),
            case IsNewRound of
                true ->
                    {reply, {error, cannot_pass_new_round}, State};
                false ->
                    NextTurn = (Turn rem 3) + 1,
                    PassCount = State0#state.pass_count + 1,
                    
                    notify_player_passed(Players, Turn),

                    % If 2 passes, next player starts new round
                    {NewLastIdx, NewLastCards, NewPassCount} = if
                        PassCount >= 2 -> {NextTurn, [], 0}; % Next player starts fresh
                        true -> {LastIdx, State0#state.last_play_cards, PassCount}
                    end,
                    
                    notify_turn_to_play(Players, NextTurn, NewLastCards),

                    StateWithTimer = start_timer(State#state{
                        current_turn = NextTurn,
                        last_play_idx = NewLastIdx,
                        last_play_cards = NewLastCards,
                        pass_count = NewPassCount
                    }, eTurnTimeout),
                    
                    StateWithAuto = check_auto_play(StateWithTimer),

                    {reply, {ok, passed}, StateWithAuto}
            end;
        _ ->
             {reply, {error, not_your_turn}, State}
    end;

handle_call({ePlayHint, PlayerPid}, _From, State = #state{game_status = playing, current_turn = Turn, players = Players, last_play_idx = LastIdx, landlord_idx = LandlordIdx, last_play_cards = LastPlayCards, played_history = History}) ->
    Player = get_player_by_pid(Players, PlayerPid),
    case Player of
        #player{index = Turn} ->
            IsNewRound = (LastIdx == Turn) orelse (LastIdx == 0),
            LastPlay = if IsNewRound -> []; true -> LastPlayCards end,
            Context = #{
                my_index => Turn,
                landlord_index => LandlordIdx,
                last_player_idx => LastIdx,
                players_cards => maps:from_list([{P#player.index, length(P#player.cards)} || P <- Players]),
                played_history => History
            },
            HintCards0 = ai_logic:choose_play(Player#player.cards, LastPlay, Player#player.role, Context),
            HintCards = case {IsNewRound, HintCards0} of
                {true, []} -> pick_timeout_opening(Player#player.cards);
                _ -> HintCards0
            end,
            {reply, {ok, HintCards}, State};
        _ ->
            {reply, {error, not_your_turn}, State}
    end;

handle_call(eGetState, _From, State) ->
    {reply, State, State};

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'DOWN', _Ref, process, Pid, _Reason}, State) ->
    {_, NewState} = do_leave_game(Pid, State),
    {noreply, NewState};

handle_info({timeout, _Ref, eTurnTimeout}, State = #state{game_status = playing, current_turn = Turn, players = Players, last_play_idx = LastIdx, landlord_idx = LandlordIdx, last_play_cards = LastPlayCards, played_history = History}) ->
    Player = get_player_by_index(Players, Turn),
    
    % Use AI Logic for auto-play
    Context = #{
        my_index => Turn,
        landlord_index => LandlordIdx,
        last_player_idx => LastIdx,
        players_cards => maps:from_list([{P#player.index, length(P#player.cards)} || P <- Players]),
        played_history => History
    },
    
    IsNewRound = (LastIdx == Turn) orelse (LastIdx == 0),
    LastPlay = if IsNewRound -> []; true -> LastPlayCards end,
    
    CardsToPlay0 = ai_logic:choose_play(Player#player.cards, LastPlay, Player#player.role, Context),
    CardsToPlay = case {IsNewRound, CardsToPlay0} of
        {true, []} -> pick_timeout_opening(Player#player.cards);
        _ -> CardsToPlay0
    end,
    
    case CardsToPlay of
        [] ->
            io:format("Player ~p timeout/auto, passing~n", [Turn]),
            convert_call_result(handle_call({ePass, Player#player.pid}, self(), State), State);
        _ ->
            io:format("Player ~p timeout/auto, playing ~p~n", [Turn, length(CardsToPlay)]),
            convert_call_result(handle_call({ePlayCards, Player#player.pid, CardsToPlay}, self(), State), State)
    end;

handle_info({timeout, _Ref, eBidTimeout}, State = #state{game_status = bidding, current_turn = Turn, players = Players, bids = Bids, landlord_idx = LandlordIdx, last_play_idx = LastIdx, played_history = History}) ->
    Player = get_player_by_index(Players, Turn),
    
    % Use AI Logic for auto-bid
    Context = #{
        my_index => Turn,
        landlord_index => LandlordIdx, % May be 0 during bidding
        last_player_idx => LastIdx,
        players_cards => maps:from_list([{P#player.index, length(P#player.cards)} || P <- Players]),
        played_history => History
    },
    
    MaxBid = get_max_bid(Bids),
    Score = ai_logic:choose_bid(Player#player.cards, Bids, MaxBid, Context),
    
    io:format("Player ~p timeout/auto, bidding ~p~n", [Turn, Score]),
    convert_call_result(handle_call({eBid, Player#player.pid, Score}, self(), State), State);

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% Helpers
convert_call_result({reply, _Reply, NewState}, _FallbackState) ->
    {noreply, NewState};
convert_call_result({noreply, NewState}, _FallbackState) ->
    {noreply, NewState};
convert_call_result({stop, Reason, _Reply, NewState}, _FallbackState) ->
    {stop, Reason, NewState};
convert_call_result({stop, Reason, NewState}, _FallbackState) ->
    {stop, Reason, NewState};
convert_call_result(_, FallbackState) ->
    {noreply, FallbackState}.

pick_timeout_opening([]) ->
    [];
pick_timeout_opening(Cards) ->
    [lists:last(Cards)].

get_player_by_pid([], _) -> undefined;
get_player_by_pid([P|Rest], Pid) ->
    if P#player.pid == Pid -> P;
       true -> get_player_by_pid(Rest, Pid)
    end.

get_player_by_index([], _) -> undefined;
get_player_by_index([P|Rest], Idx) ->
    if P#player.index == Idx -> P;
       true -> get_player_by_index(Rest, Idx)
    end.

get_max_bid([]) -> 0;
get_max_bid(Bids) -> lists:max([Score || {_, Score} <- Bids]).

get_highest_bidder(Bids) ->
    lists:foldl(fun({Idx, Score}, {BestIdx, BestScore}) ->
        if Score > BestScore -> {Idx, Score};
           true -> {BestIdx, BestScore}
        end
    end, {0, 0}, Bids).

reset_players(Players) ->
    [P#player{cards = []} || P <- Players].

start_playing(State, LandlordIdx, BaseScore) ->
    #state{players = Players, landlord_cards = LC, room_id = RoomId} = State,
    
    % Add landlord cards to landlord
    NewPlayers = lists:map(fun(P) ->
        if P#player.index == LandlordIdx ->
            P#player{cards = cards:sort_cards(P#player.cards ++ LC), role = landlord};
           true ->
            P#player{role = peasant}
        end
    end, Players),
    
    notify_landlord_selected(NewPlayers, LandlordIdx, LC, BaseScore),
    notify_turn_to_play(NewPlayers, LandlordIdx, []),
    room_manager:updateRoomStatus(RoomId, playing),

    State#state{
        players = NewPlayers,
        game_status = playing,
        current_turn = LandlordIdx,
        base_score = BaseScore,
        landlord_idx = LandlordIdx,
        last_play_idx = LandlordIdx, % Landlord starts free
        last_play_cards = [],
        pass_count = 0
    }.

do_leave_game(PlayerPid, State = #state{players = Players, game_status = Status}) ->
    case lists:keyfind(PlayerPid, #player.pid, Players) of
        #player{} = P ->
            case Status of
                waiting ->
                    % Remove player completely
                    NewPlayers0 = lists:keydelete(PlayerPid, #player.pid, Players),
                    
                    % Re-index remaining players
                    {NewPlayers, PlayerUpdates} = reindex_players(NewPlayers0),
                    
                    % Notify index changes if needed
                    lists:foreach(fun({Pid, Idx}) ->
                        player:setIndex(Pid, Idx)
                    end, PlayerUpdates),

                    NewState = State#state{players = NewPlayers},
                    FinalState = cancel_timer(NewState),
                    {{ok, PlayerUpdates}, FinalState};
                _ ->
                    % Mark as trusteeship
                    NewPlayer = P#player{pid = undefined, is_trusteeship = true},
                    NewPlayers = lists:keyreplace(PlayerPid, #player.pid, Players, NewPlayer),
                    
                    % We do not cancel timer here, game continues
                    NewState = State#state{players = NewPlayers},
                    
                    % Check if it's this player's turn right now
                    FinalState = check_auto_play(NewState),
                    
                    {{ok, []}, FinalState}
            end;
        false ->
            {{error, not_in_game}, State}
    end.

reindex_players(Players) ->
    {NewPlayers, _} = lists:mapfoldl(fun(P, Idx) ->
        {P#player{index = Idx}, Idx + 1}
    end, 1, Players),
    Updates = [{P#player.pid, P#player.index} || P <- NewPlayers],
    {NewPlayers, Updates}.

subtractCards(Hand, ToRemove) ->
    try
        NewHand = lists:foldl(fun(Card, Acc) ->
            case lists:member(Card, Acc) of
                true -> lists:delete(Card, Acc);
                false -> throw(not_found)
            end
        end, Hand, ToRemove),
        {ok, NewHand}
    catch
        throw:not_found -> error
    end.

calculate_scores(Players, WinnerIdx, BaseScore, Multiplier) ->
    Winner = lists:keyfind(WinnerIdx, #player.index, Players),
    IsLandlordWin = (Winner#player.role == landlord),
    
    Landlord = lists:keyfind(landlord, #player.role, Players),
    Peasants = [P || P <- Players, P#player.role == peasant],
    
    Score = BaseScore * Multiplier,
    
    if 
        IsLandlordWin ->
            % Landlord wins: +2 * Score
            % Peasants lose: -Score
            [
                {Landlord#player.index, Landlord#player.name, 2 * Score, win} | 
                [{P#player.index, P#player.name, -Score, loss} || P <- Peasants]
            ];
        true ->
            % Landlord loses: -2 * Score
            % Peasants win: +Score
            [
                {Landlord#player.index, Landlord#player.name, -2 * Score, loss} | 
                [{P#player.index, P#player.name, Score, win} || P <- Peasants]
            ]
    end.

update_system_scores(_Players, Scores) ->
    lists:foreach(fun({_, Name, Points, Result}) ->
        score_system:updateScore(Name, Result, abs(Points))
    end, Scores).

check_auto_play(State = #state{game_status = Status, current_turn = Turn, players = Players}) ->
    Player = get_player_by_index(Players, Turn),
    case Player of
        #player{is_trusteeship = true} ->
            % Trigger AI action quickly
            start_timer(State, if Status == bidding -> eBidTimeout; true -> eTurnTimeout end, 1000); % 1s delay for AI
        _ ->
            State
    end.

start_timer(State, Msg) ->
    start_timer(State, Msg, State#state.timeout_duration).

start_timer(State, Msg, Duration) ->
    cancel_timer(State),
    Ref = erlang:start_timer(Duration, self(), Msg),
    State#state{timer_ref = Ref}.

cancel_timer(State) ->
    case State#state.timer_ref of
        undefined -> ok;
        Ref -> erlang:cancel_timer(Ref)
    end,
    State#state{timer_ref = undefined}.

%% Notifications
notify_game_start(Players, FirstBidder) ->
    lists:foreach(fun(P) ->
        case P#player.pid of
            undefined -> ok;
            Pid -> Pid ! {eGameStart, P#player.cards, FirstBidder}
        end
    end, Players).

notify_turn_to_bid(Players, NextTurn, Bids) ->
    lists:foreach(fun(P) ->
        case P#player.pid of
            undefined -> ok;
            Pid -> Pid ! {eTurnToBid, NextTurn, Bids}
        end
    end, Players).

notify_bid_made(Players, BidderIdx, Score) ->
    lists:foreach(fun(P) ->
        case P#player.pid of
            undefined -> ok;
            Pid -> Pid ! {eBidMade, BidderIdx, Score}
        end
    end, Players).

notify_game_abort(Players) ->
    lists:foreach(fun(P) ->
        case P#player.pid of
            undefined -> ok;
            Pid -> Pid ! {eGameOver, 0, []}
        end
    end, Players).

notify_restart(Players) ->
    lists:foreach(fun(P) ->
        case P#player.pid of
            undefined -> ok;
            Pid -> Pid ! {eGameRestart}
        end
    end, Players).

notify_turn_to_play(Players, NextTurn, LastPlay) ->
    lists:foreach(fun(P) ->
        case P#player.pid of
            undefined -> ok;
            Pid -> Pid ! {eTurnToPlay, NextTurn, LastPlay}
        end
    end, Players).

notify_player_played(Players, PlayerIdx, Cards) ->
    lists:foreach(fun(P) ->
        case P#player.pid of
            undefined -> ok;
            Pid -> Pid ! {ePlayerPlayed, PlayerIdx, Cards}
        end
    end, Players).

notify_player_passed(Players, PlayerIdx) ->
    lists:foreach(fun(P) ->
        case P#player.pid of
            undefined -> ok;
            Pid -> Pid ! {ePlayerPassed, PlayerIdx}
        end
    end, Players).

notify_game_over(Players, WinnerIdx, Scores) ->
    lists:foreach(fun(P) ->
        case P#player.pid of
            undefined -> ok;
            Pid -> Pid ! {eGameOver, WinnerIdx, Scores}
        end
    end, Players).

notify_landlord_selected(Players, LandlordIdx, LandlordCards, BaseScore) ->
    lists:foreach(fun(P) ->
        case P#player.pid of
            undefined -> ok;
            Pid -> Pid ! {eLandlordSelected, LandlordIdx, LandlordCards, BaseScore}
        end
    end, Players).
