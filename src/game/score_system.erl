-module(score_system).
-behaviour(gen_server).

-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([getScore/1, updateScore/3, getLeaderboard/0]).

-record(state, {
    scores = #{}, % Map: PlayerName -> {Score, Wins, Losses}
    leaderboard = []
}).

%% API
start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

getScore(PlayerName) ->
    gen_server:call(?MODULE, {eGetScore, PlayerName}).

updateScore(PlayerName, GameResult, Points) ->
    gen_server:call(?MODULE, {eUpdateScore, PlayerName, GameResult, Points}).

getLeaderboard() ->
    gen_server:call(?MODULE, eGetLeaderboard).

%% Callbacks
init([]) ->
    {ok, #state{scores = #{}}}.

handle_call({eGetScore, PlayerName}, _From, State = #state{scores = Scores}) ->
    case maps:find(PlayerName, Scores) of
        {ok, ScoreData} ->
            {reply, {ok, ScoreData}, State};
        error ->
            {reply, {ok, {0, 0, 0}}, State}
    end;

handle_call({eUpdateScore, PlayerName, GameResult, Points}, _From, State = #state{scores = Scores}) ->
    {Score, Wins, Losses} = case maps:find(PlayerName, Scores) of
        {ok, {OldScore, OldWins, OldLosses}} ->
            {OldScore, OldWins, OldLosses};
        error ->
            {0, 0, 0}
    end,
    
    {NewScore, NewWins, NewLosses} = case GameResult of
        win -> {Score + Points, Wins + 1, Losses};
        loss -> {Score - Points, Wins, Losses + 1};
        draw -> {Score, Wins, Losses}
    end,
    
    NewScores = maps:put(PlayerName, {NewScore, NewWins, NewLosses}, Scores),
    NewLeaderboard = update_leaderboard(NewScores),
    
    {reply, {ok, {NewScore, NewWins, NewLosses}}, State#state{scores = NewScores, leaderboard = NewLeaderboard}};

handle_call(eGetLeaderboard, _From, State = #state{leaderboard = Leaderboard}) ->
    {reply, {ok, Leaderboard}, State};

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_call}, State}.

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

%% 内部函数

% 更新排行榜
update_leaderboard(Scores) ->
    % 将分数映射转换为列表并按分数排序
    ScoresList = maps:to_list(Scores),
    SortedScores = lists:sort(
        fun({_, {Score1, _, _}}, {_, {Score2, _, _}}) -> Score1 > Score2 end,
        ScoresList
    ),
    % 只保留前10名
    lists:sublist(SortedScores, 10).