-module(room_manager).
-behaviour(gen_server).

-include("protoMsg.hrl").

-export([start_link/0, init/1, handle_call/3, handle_cast/2, handle_info/2, terminate/2, code_change/3]).
-export([createRoom/3, listRooms/0, joinRoom/2, joinRoom/3, leaveRoom/2, deleteRoom/1, quickMatch/1, quickMatch/2, addAiPlayer/1, setReady/2, startGame/1, updateRoomStatus/2]).

createRoom(RoomName, CreatorPid, CreatorName) ->
    gen_server:call(?MODULE, {eCreateRoom, RoomName, CreatorPid, CreatorName}).

listRooms() ->
    gen_server:call(?MODULE, eListRooms).

joinRoom(RoomId, PlayerPid) ->
    gen_server:call(?MODULE, {eJoinRoom, normalize_room_id(RoomId), PlayerPid, fallback_player_name(PlayerPid)}).

joinRoom(RoomId, PlayerPid, PlayerName) ->
    gen_server:call(?MODULE, {eJoinRoom, normalize_room_id(RoomId), PlayerPid, normalize_player_name(PlayerName)}).

leaveRoom(RoomId, PlayerPid) ->
    gen_server:call(?MODULE, {eLeaveRoom, RoomId, PlayerPid}).

deleteRoom(RoomId) ->
    gen_server:call(?MODULE, {eDeleteRoom, RoomId}).

quickMatch(PlayerPid) ->
    gen_server:call(?MODULE, {eQuickMatch, PlayerPid, fallback_player_name(PlayerPid)}).

quickMatch(PlayerPid, PlayerName) ->
    gen_server:call(?MODULE, {eQuickMatch, PlayerPid, normalize_player_name(PlayerName)}).

addAiPlayer(RoomId) ->
    gen_server:call(?MODULE, {eAddAiPlayer, RoomId}).

setReady(PlayerPid, Ready) ->
    gen_server:call(?MODULE, {eSetReady, PlayerPid, Ready}).

startGame(PlayerPid) ->
    gen_server:call(?MODULE, {eStartGame, PlayerPid}).

updateRoomStatus(RoomId, Status) ->
    gen_server:cast(?MODULE, {eUpdateRoomStatus, normalize_room_id(RoomId), Status}).

-record(state, {
    rooms = #{},
    waiting_queue = [],
    ai_counter = 0
}).

-record(room, {
    id,
    name,
    game_pid,
    players = [],
    status = waiting,
    ai_players = [],
    ready_players = []
}).

start_link() ->
    gen_server:start_link({local, ?MODULE}, ?MODULE, [], []).

init([]) ->
    process_flag(trap_exit, true),
    {ok, #state{}}.

handle_call({eCreateRoom, RoomName, CreatorPid, CreatorName}, _From, State = #state{rooms = Rooms}) ->
    RoomId = generate_room_id(),
    {ok, GamePid} = game_server:start_link(RoomId),
    NormalizedCreatorName = normalize_player_name(CreatorName),
    {ok, Index} = game_server:joinGame(GamePid, CreatorPid, NormalizedCreatorName),
    player:setIndex(CreatorPid, Index),
    player:setRoom(CreatorPid, RoomId),
    player:setGamePid(CreatorPid, GamePid),
    NewRoom = #room{
        id = RoomId,
        name = RoomName,
        game_pid = GamePid,
        players = [{CreatorPid, NormalizedCreatorName, Index}],
        ready_players = []
    },
    NewRooms = maps:put(RoomId, NewRoom, Rooms),
    notify_room_players(NewRoom, RoomId, 2),
    {reply, {ok, RoomId, GamePid, Index}, State#state{rooms = NewRooms}};

handle_call(eListRooms, _From, State = #state{rooms = Rooms}) ->
    RoomList = maps:fold(
        fun(RoomId, Room, Acc) ->
            [{RoomId, Room#room.name, length(Room#room.players), Room#room.status} | Acc]
        end,
        [],
        Rooms
    ),
    {reply, {ok, RoomList}, State};

handle_call({eJoinRoom, RoomId, PlayerPid, PlayerName}, _From, State = #state{rooms = Rooms}) ->
    case maps:find(RoomId, Rooms) of
        {ok, Room = #room{players = Players, status = Status, game_pid = GamePid}} when Status =/= bidding, Status =/= playing ->
            case lists:keyfind(PlayerPid, 1, Players) of
                {PlayerPid, _Name, _Index} ->
                    {reply, {error, already_in_room}, State};
                false ->
                    case length(Players) < 3 of
                        true ->
                            {ok, Index} = game_server:joinGame(GamePid, PlayerPid, PlayerName),
                            player:setIndex(PlayerPid, Index),
                            player:setRoom(PlayerPid, RoomId),
                            player:setGamePid(PlayerPid, GamePid),
                            NewPlayers = Players ++ [{PlayerPid, PlayerName, Index}],
                            NewRoom = Room#room{players = NewPlayers, ready_players = [], status = derive_idle_room_status(NewPlayers)},
                            NewRooms = maps:put(RoomId, NewRoom, Rooms),
                            notify_room_players(NewRoom, RoomId, 0),
                            {reply, {ok, GamePid, Index}, State#state{rooms = NewRooms}};
                        false ->
                            {reply, {error, room_full}, State}
                    end
            end;
        {ok, #room{status = playing}} ->
            {reply, {error, game_in_progress}, State};
        error ->
            {reply, {error, room_not_found}, State}
    end;

handle_call({eLeaveRoom, RoomId, PlayerPid}, _From, State = #state{rooms = Rooms}) ->
    case maps:find(RoomId, Rooms) of
        {ok, Room = #room{players = Players, game_pid = GamePid}} ->
            case lists:keyfind(PlayerPid, 1, Players) of
                {PlayerPid, _Name, _Index} ->
                    % Call game_server to leave
                    case game_server:leaveGame(GamePid, PlayerPid) of
                        {ok, PlayerUpdates} ->
                            NewPlayers0 = lists:keydelete(PlayerPid, 1, Players),
                            
                            % Update remaining players index
                            NewPlayers = lists:map(fun({Pid, Name, Idx}) ->
                                case lists:keyfind(Pid, 1, PlayerUpdates) of
                                    {Pid, NewIdx} -> {Pid, Name, NewIdx};
                                    false -> {Pid, Name, Idx}
                                end
                            end, NewPlayers0),

                            OnlyAiLeft = NewPlayers =/= [] andalso (not has_human_players(NewPlayers, Room#room.ai_players)),

                            case {NewPlayers, OnlyAiLeft} of
                                {[], _} ->
                                     stop_ai_players(Room#room.ai_players),
                                     gen_server:stop(GamePid),
                                     NewRooms = maps:remove(RoomId, Rooms),
                                     {reply, ok, State#state{rooms = NewRooms}};
                                {_, true} ->
                                     stop_ai_players(Room#room.ai_players),
                                     gen_server:stop(GamePid),
                                     NewRooms = maps:remove(RoomId, Rooms),
                                     {reply, ok, State#state{rooms = NewRooms}};
                                {_, false} ->
                                    NewRoom = Room#room{players = NewPlayers, status = derive_idle_room_status(NewPlayers), ready_players = []},
                                    NewRooms = maps:put(RoomId, NewRoom, Rooms),
                                    notify_room_players(NewRoom, RoomId, 1),
                                    {reply, ok, State#state{rooms = NewRooms}}
                            end;
                        {error, Reason} ->
                             {reply, {error, Reason}, State}
                    end;
                false ->
                    {reply, {error, player_not_in_room}, State}
            end;
        error ->
            {reply, {error, room_not_found}, State}
    end;

handle_call({eDeleteRoom, RoomId}, _From, State = #state{rooms = Rooms}) ->
    case maps:find(RoomId, Rooms) of
        {ok, Room} ->
            gen_server:stop(Room#room.game_pid),
            NewRooms = maps:remove(RoomId, Rooms),
            {reply, ok, State#state{rooms = NewRooms}};
        error ->
            {reply, {error, room_not_found}, State}
    end;

handle_call({eQuickMatch, PlayerPid, PlayerName}, _From, State = #state{rooms = Rooms, waiting_queue = _Queue}) ->
    AlreadyInRoom = maps:fold(
        fun(_RoomId, #room{players = Players}, Acc) ->
            case lists:keyfind(PlayerPid, 1, Players) of
                {PlayerPid, _, _} -> true;
                false -> Acc
            end
        end,
        false,
        Rooms
    ),
    case AlreadyInRoom of
        true ->
            {reply, {error, already_in_room}, State};
        false ->
            case find_available_room(Rooms) of
                {ok, RoomId, Room} ->
                    {ok, Index} = game_server:joinGame(Room#room.game_pid, PlayerPid, PlayerName),
                    player:setIndex(PlayerPid, Index),
                    player:setRoom(PlayerPid, RoomId),
                    player:setGamePid(PlayerPid, Room#room.game_pid),
                    NewPlayers = Room#room.players ++ [{PlayerPid, PlayerName, Index}],
                    NewRoom = Room#room{players = NewPlayers, ready_players = [], status = derive_idle_room_status(NewPlayers)},
                    NewRooms = maps:put(RoomId, NewRoom, Rooms),
                    notify_room_players(NewRoom, RoomId, 0),
                    {reply, {ok, RoomId, Room#room.game_pid, Index}, State#state{rooms = NewRooms}};
                none ->
                    RoomId = generate_room_id(),
                    {ok, GamePid} = game_server:start_link(RoomId),
                    {ok, Index} = game_server:joinGame(GamePid, PlayerPid, PlayerName),
                    player:setIndex(PlayerPid, Index),
                    player:setRoom(PlayerPid, RoomId),
                    player:setGamePid(PlayerPid, GamePid),
                    NewRoom = #room{
                        id = RoomId,
                        name = PlayerName ++ "的房间",
                        game_pid = GamePid,
                        players = [{PlayerPid, PlayerName, Index}],
                        ready_players = []
                    },
                    NewRooms = maps:put(RoomId, NewRoom, Rooms),
                    notify_room_players(NewRoom, RoomId, 2),
                    {reply, {ok, RoomId, GamePid, Index}, State#state{rooms = NewRooms}}
            end
    end;

handle_call({eAddAiPlayer, RoomId}, _From, State = #state{rooms = Rooms, ai_counter = AiCounter}) ->
    case maps:find(RoomId, Rooms) of
        {ok, Room = #room{players = Players, status = Status, game_pid = GamePid, ai_players = AiPlayers, ready_players = ReadyPlayers}} when Status =/= bidding, Status =/= playing ->
            case length(Players) < 3 of
                true ->
                    NewAiCounter = AiCounter + 1,
                    AiName = "AI_" ++ integer_to_list(NewAiCounter),
                    {ok, AiPid} = ai_agent:start_link(AiName),
                    {ok, Index} = game_server:joinGame(GamePid, AiPid, AiName),
                    ai_agent:setGameInfo(AiPid, GamePid, Index),
                    NewPlayers = Players ++ [{AiPid, AiName, Index}],
                    NewAiPlayers = AiPlayers ++ [AiPid],
                    NewReadyPlayers = lists:usort([AiPid | ReadyPlayers]),
                    NewRoom = Room#room{players = NewPlayers, ai_players = NewAiPlayers, ready_players = NewReadyPlayers, status = derive_idle_room_status(NewPlayers)},
                    NewRooms = maps:put(RoomId, NewRoom, Rooms),
                    notify_room_players(NewRoom, RoomId, 0),
                    notify_player_ready(NewRoom#room.players, Index, true, is_all_ready(NewRoom#room.players, NewReadyPlayers)),
                    {reply, {ok, AiName, Index}, State#state{rooms = NewRooms, ai_counter = NewAiCounter}};
                false ->
                    {reply, {error, room_full}, State}
            end;
        {ok, #room{status = playing}} ->
            {reply, {error, game_in_progress}, State};
        error ->
            {reply, {error, room_not_found}, State}
    end;

handle_call({eSetReady, PlayerPid, Ready}, _From, State = #state{rooms = Rooms}) ->
    case find_room_by_player(Rooms, PlayerPid) of
        {ok, RoomId, Room = #room{status = Status, players = Players, ready_players = ReadyPlayers0, ai_players = AiPlayers, game_pid = GamePid}} when Status =/= bidding, Status =/= playing ->
            ReadyPlayers1 = case Ready of
                true -> lists:usort([PlayerPid | ReadyPlayers0 ++ AiPlayers]);
                false -> lists:delete(PlayerPid, ReadyPlayers0)
            end,
            {_, _Name, PlayerIndex} = lists:keyfind(PlayerPid, 1, Players),
            AllReady = is_all_ready(Players, ReadyPlayers1),
            BaseRoom = Room#room{
                ready_players = ReadyPlayers1,
                status = derive_idle_room_status(Players)
            },
            notify_player_ready(Players, PlayerIndex, Ready, AllReady),
            case {length(Players), AllReady} of
                {3, true} ->
                    case game_server:startGame(GamePid) of
                        {ok, bidding, FirstBidder} ->
                            StartedRoom = BaseRoom#room{status = bidding, ready_players = []},
                            NewRooms = maps:put(RoomId, StartedRoom, Rooms),
                            {reply, {ok, auto_started, RoomId, GamePid, FirstBidder}, State#state{rooms = NewRooms}};
                        {error, Reason} ->
                            NewRooms = maps:put(RoomId, BaseRoom, Rooms),
                            {reply, {error, Reason}, State#state{rooms = NewRooms}}
                    end;
                _ ->
                    NewRooms = maps:put(RoomId, BaseRoom, Rooms),
                    {reply, {ok, waiting_ready}, State#state{rooms = NewRooms}}
            end;
        {ok, _RoomId, _Room} ->
            {reply, {error, game_in_progress}, State};
        error ->
            {reply, {error, room_not_found}, State}
    end;

handle_call({eStartGame, PlayerPid}, _From, State = #state{rooms = Rooms}) ->
    case find_room_by_player(Rooms, PlayerPid) of
        {ok, RoomId, Room = #room{status = Status, game_pid = GamePid, players = Players, ready_players = ReadyPlayers, ai_players = AiPlayers}} when Status =/= bidding, Status =/= playing ->
            ReadyPlayers1 = lists:usort([PlayerPid | ReadyPlayers ++ AiPlayers]),
            AllReady = lists:all(fun({Pid, _Name, _Index}) -> lists:member(Pid, ReadyPlayers1) end, Players),
            case {length(Players), AllReady} of
                {3, true} ->
                    case game_server:startGame(GamePid) of
                        {ok, bidding, FirstBidder} ->
                            NewRoom = Room#room{status = bidding, ready_players = []},
                            NewRooms = maps:put(RoomId, NewRoom, Rooms),
                            {reply, {ok, RoomId, GamePid, FirstBidder}, State#state{rooms = NewRooms}};
                        {error, Reason} ->
                            {reply, {error, Reason}, State}
                    end;
                {3, false} ->
                    NewRoom = Room#room{ready_players = ReadyPlayers1},
                    NewRooms = maps:put(RoomId, NewRoom, Rooms),
                    notify_room_players(NewRoom, RoomId, 0),
                    {reply, {error, waiting_ready}, State#state{rooms = NewRooms}};
                _ ->
                    {reply, {error, not_enough_players}, State}
            end;
        {ok, _RoomId, #room{status = playing}} ->
            {reply, {error, game_not_waiting}, State};
        error ->
            {reply, {error, room_not_found}, State}
    end;

handle_call(_Request, _From, State) ->
    {reply, {error, unknown_request}, State}.

handle_cast({eUpdateRoomStatus, RoomId, Status}, State = #state{rooms = Rooms}) ->
    case maps:find(RoomId, Rooms) of
        {ok, Room} ->
            NewStatus = next_room_status(Room#room.status, Status),
            NewReadyPlayers = case NewStatus of
                waiting -> [];
                _ -> Room#room.ready_players
            end,
            NewRoom = Room#room{status = NewStatus, ready_players = NewReadyPlayers},
            NewRooms = maps:put(RoomId, NewRoom, Rooms),
            {noreply, State#state{rooms = NewRooms}};
        error ->
            {noreply, State}
    end;

handle_cast(_Msg, State) ->
    {noreply, State}.

handle_info({'EXIT', Pid, Reason}, State = #state{rooms = Rooms}) ->
    % Find room by GamePid
    Result = maps:fold(fun(Id, R, Acc) -> 
        if R#room.game_pid == Pid -> {Id, R}; 
           true -> Acc 
        end 
    end, undefined, Rooms),
    
    case Result of
        {RoomId, Room} ->
             io:format("Game server ~p exited with ~p~n", [Pid, Reason]),
             % Notify players game ended abruptly
             lists:foreach(fun({PlayerPid, _, _}) ->
                 PlayerPid ! {eGameOver, 0, []}
             end, Room#room.players),
             NewRooms = maps:remove(RoomId, Rooms),
             {noreply, State#state{rooms = NewRooms}};
        undefined ->
             {noreply, State}
    end;

handle_info(_Info, State) ->
    {noreply, State}.

terminate(_Reason, _State) ->
    ok.

code_change(_OldVsn, State, _Extra) ->
    {ok, State}.

generate_room_id() ->
    "r" ++ integer_to_list(erlang:unique_integer([monotonic, positive])).

normalize_room_id(undefined) ->
    undefined;
normalize_room_id(RoomId) when is_binary(RoomId) ->
    string:trim(binary_to_list(RoomId));
normalize_room_id(RoomId) when is_list(RoomId) ->
    string:trim(RoomId);
normalize_room_id(RoomId) ->
    RoomId.

normalize_player_name(Name) when is_binary(Name) ->
    binary_to_list(Name);
normalize_player_name(Name) when is_list(Name) ->
    Name;
normalize_player_name(Name) ->
    io_lib:format("~p", [Name]).

fallback_player_name(PlayerPid) ->
    "Player_" ++ integer_to_list(erlang:phash2(PlayerPid, 1000000)).

has_human_players(Players, AiPlayers) ->
    lists:any(fun({Pid, _Name, _Index}) ->
        not lists:member(Pid, AiPlayers)
    end, Players).

stop_ai_players(AiPlayers) ->
    lists:foreach(fun(Pid) ->
        case is_pid(Pid) andalso erlang:is_process_alive(Pid) of
            true -> exit(Pid, shutdown);
            false -> ok
        end
    end, AiPlayers).

find_available_room(Rooms) ->
    Available = maps:fold(
        fun(RoomId, Room = #room{players = Players, status = Status}, Acc) ->
            case Status =/= bidding andalso Status =/= playing andalso length(Players) < 3 of
                true -> [{RoomId, Room, length(Players)} | Acc];
                false -> Acc
            end
        end,
        [],
        Rooms
    ),
    case Available of
        [] -> none;
        List ->
            Sorted = lists:sort(fun({_, _, C1}, {_, _, C2}) -> C1 >= C2 end, List),
            {RoomId, Room, _} = hd(Sorted),
            {ok, RoomId, Room}
    end.

derive_idle_room_status(Players) ->
    case length(Players) of
        N when N < 3 -> waiting;
        _ -> ready
    end.

is_all_ready(Players, ReadyPlayers) ->
    lists:all(fun({Pid, _Name, _Index}) -> lists:member(Pid, ReadyPlayers) end, Players).

next_room_status(Current, Target) ->
    case {Current, Target} of
        {waiting, ready} -> ready;
        {waiting, bidding} -> bidding;
        {ready, waiting} -> waiting;
        {ready, bidding} -> bidding;
        {bidding, playing} -> playing;
        {bidding, finished} -> finished;
        {bidding, waiting} -> waiting;
        {playing, finished} -> finished;
        {playing, waiting} -> waiting;
        {finished, waiting} -> waiting;
        {finished, ready} -> ready;
        {finished, bidding} -> bidding;
        {_, _} -> Target
    end.

find_room_by_player(Rooms, PlayerPid) ->
    maps:fold(
        fun(RoomId, Room = #room{players = Players}, Acc) ->
            case Acc of
                {ok, _, _} ->
                    Acc;
                error ->
                    case lists:keyfind(PlayerPid, 1, Players) of
                        false -> error;
                        _ -> {ok, RoomId, Room}
                    end
            end
        end,
        error,
        Rooms
    ).

notify_room_players(Room, RoomId, Status) ->
    lists:foreach(
        fun({Pid, _Name, _Index}) ->
            PlayerInfos = lists:map(
                fun({InnerPid, Name, Index}) ->
                    PlayerStatus = case InnerPid =:= Pid of
                        true -> 2;
                        false -> 1
                    end,
                    #playerInfo{index = Index, name = Name, status = PlayerStatus}
                end,
                Room#room.players
            ),
            Msg = #sc_room_update{roomId = RoomId, status = Status, players = PlayerInfos},
            Pid ! {eSendClient, Msg}
        end,
        Room#room.players
    ).

notify_player_ready(Players, PlayerIdx, Ready, AllReady) ->
    ReadyVal = case Ready of true -> 1; false -> 0 end,
    AllReadyVal = case AllReady of true -> 1; false -> 0 end,
    lists:foreach(
        fun({Pid, _Name, _Index}) ->
            Msg = #sc_player_ready{playerIdx = PlayerIdx, ready = ReadyVal, allReady = AllReadyVal},
            Pid ! {eSendClient, Msg}
        end,
        Players
    ).
