-module(ai_agent).
-behaviour(gen_server).

-export([start_link/1, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([joinGame/2, setGameInfo/3]).

joinGame(GamePid, Name) ->
    gen_server:cast(GamePid, {eJoinGame, Name}).

setGameInfo(AiPid, GamePid, Index) ->
    gen_server:cast(AiPid, {eSetGameInfo, GamePid, Index}).

-record(state, {
    name,
    game_pid,
    cards = [],
    role = none, % landlord | peasant
    index = 0,
    last_game_play = [], % Track last play for logic
    last_player_idx = 0,
    landlord_idx = 0,    % Track landlord index
    players_cards = #{}, % Track card counts for all players
    played_history = []  % Track all played cards
}).

start_link(Name) ->
    gen_server:start_link(?MODULE, [Name], []).

join_game(AiPid, GamePid) ->
    gen_server:cast(AiPid, {join_game, GamePid}).

init([Name]) ->
    rand:seed(exsplus, os:timestamp()),
    {ok, #state{name = Name}}.

handle_cast({eSetGameInfo, GamePid, Index}, State) ->
    {noreply, State#state{game_pid = GamePid, index = Index}};

handle_cast({eJoinGame, GamePid}, State) ->
    case game_server:joinGame(GamePid, self(), State#state.name) of
        {ok, Index} ->
            {noreply, State#state{game_pid = GamePid, index = Index}};
        {error, Reason} ->
            log(State, "failed to join: ~p", [Reason]),
            {noreply, State}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({eGameStart, Cards, _FirstBidder}, State) ->
    log(State, "got cards", []),
    % Initialize players cards count (assuming 3 players)
    % 17 cards each initially
    InitCounts = #{1 => 17, 2 => 17, 3 => 17},
    {noreply, State#state{
        cards = Cards, 
        role = none, 
        last_game_play = [],
        last_player_idx = 0,
        players_cards = InitCounts,
        played_history = []
    }};

handle_info({eTurnToBid, NextTurn, Bids}, State = #state{index = Index, game_pid = GamePid, cards = Cards}) ->
    if NextTurn == Index ->
        % Think for a bit
        delay(),
        
        % Build Context
        Context = #{
            my_index => Index,
            landlord_index => State#state.landlord_idx,
            last_player_idx => State#state.last_player_idx,
            players_cards => State#state.players_cards,
            played_history => State#state.played_history
        },

        MaxBid = if Bids == [] -> 0; true -> lists:max([S || {_, S} <- Bids]) end,
        Score = ai_logic:choose_bid(Cards, Bids, MaxBid, Context),
        log(State, "bids ~p (Max: ~p)", [Score, MaxBid]),
        game_server:bid(GamePid, self(), Score);
       true -> ok
    end,
    {noreply, State};

handle_info({eBidMade, _Idx, _Score}, State) ->
    {noreply, State};

handle_info({eLandlordSelected, LandlordIdx, LandlordCards, _BaseScore}, State) ->
    NewRole = if State#state.index == LandlordIdx -> landlord; true -> peasant end,
    NewCards = if NewRole == landlord -> cards:sort_cards(State#state.cards ++ LandlordCards); true -> State#state.cards end,
    
    % Update landlord card count (17 + 3 = 20)
    Counts = State#state.players_cards,
    NewCounts = maps:put(LandlordIdx, 20, Counts),
    
    log(State, "is ~p", [NewRole]),
    {noreply, State#state{
        role = NewRole, 
        cards = NewCards, 
        landlord_idx = LandlordIdx,
        players_cards = NewCounts
    }};

handle_info({eTurnToPlay, NextTurn, LastPlay}, State = #state{index = Index, game_pid = GamePid, cards = Cards, role = Role}) ->
    if NextTurn == Index ->
        delay(),
        
        % Build Context
        Context = #{
            my_index => Index,
            landlord_index => State#state.landlord_idx,
            last_player_idx => State#state.last_player_idx,
            players_cards => State#state.players_cards,
            played_history => State#state.played_history
        },
        
        Play0 = ai_logic:choose_play(Cards, LastPlay, Role, Context),
        Play = case {LastPlay, Play0} of
            {[], []} when Cards =/= [] -> [lists:last(Cards)];
            _ -> Play0
        end,
        case Play of
            [] -> 
                log(State, "passes", []),
                game_server:pass(GamePid, self());
            _ ->
                log(State, "plays ~p", [length(Play)]),
                game_server:playCards(GamePid, self(), Play)
        end;
       true -> ok
    end,
    {noreply, State#state{last_game_play = LastPlay}};

handle_info({ePlayerPlayed, PlayerIdx, CardsPlayed}, State) ->
    % Update played history
    NewHistory = State#state.played_history ++ CardsPlayed,
    
    % Update player card count
    Counts = State#state.players_cards,
    CurrentCount = maps:get(PlayerIdx, Counts, 0),
    NewCounts = maps:put(PlayerIdx, max(0, CurrentCount - length(CardsPlayed)), Counts),
    
    NewState = State#state{
        played_history = NewHistory,
        players_cards = NewCounts,
        last_player_idx = PlayerIdx
    },

    if PlayerIdx == State#state.index ->
        % Update my cards
        {ok, NewHand} = game_server:subtractCards(State#state.cards, CardsPlayed),
        {noreply, NewState#state{cards = NewHand}};
       true ->
        {noreply, NewState}
    end;

handle_info({ePlayerPassed, _Idx}, State) ->
    {noreply, State};

handle_info({eGameOver, WinnerIdx, Scores}, State) ->
    Result = if WinnerIdx == State#state.index -> "Wins"; true -> "Loses" end,
    log(State, "~s! Scores: ~p", [Result, Scores]),
    {noreply, State};

handle_info({eGameRestart}, State) ->
    log(State, "restarting...", []),
    {noreply, State#state{cards = [], role = none, last_player_idx = 0}};

handle_info(_Info, State) ->
    {noreply, State}.

%% Helpers
delay() ->
    Delay = application:get_env(agw, ai_delay, 500),
    if Delay > 0 -> timer:sleep(Delay); true -> ok end.

log(State, Fmt, Args) ->
    case application:get_env(agw, ai_verbose, true) of
        true -> io:format("AI ~p " ++ Fmt ++ "~n", [State#state.name | Args]);
        false -> ok
    end.

handle_call(eGetName, _From, State) ->
    {reply, {ok, State#state.name}, State};

handle_call(_Request, _From, State) ->
    {reply, ok, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.
