-module(roleHer).
-include("protoMsg.hrl").
-include("common.hrl").
-include("game.hrl").
-include("player.hrl").

-export([handleMsg/2]).

%% 创建房间
handleMsg(#cs_create_room{name = RoomName}, State = #playerState{name = Name}) ->
	case room_manager:createRoom(RoomName, self(), Name) of
		{ok, RoomId, GamePid, Index} ->
			{ok, State#playerState{game_pid = GamePid, room_id = RoomId, index = Index}};
		{error, Reason} ->
			{error, 1, atom_to_list(Reason), State}
	end;

%% 获取房间列表
handleMsg(#cs_list_rooms{}, State) ->
	{ok, RoomList} = room_manager:listRooms(),
	Rooms = lists:map(fun({Id, RoomName, Count, Status}) ->
		S = case Status of
			waiting -> 0;
			playing -> 1;
			ready -> 2;
			bidding -> 3;
			finished -> 4
		end,
		#roomInfo{roomId = Id, name = RoomName, playerCount = Count, status = S}
	end, RoomList),
	Reply = #sc_list_rooms{rooms = Rooms},
	{ok, Reply, State};

%% 加入房间
handleMsg(#cs_join_room{roomId = RoomId}, State = #playerState{name = Name}) ->
	case room_manager:joinRoom(RoomId, self(), Name) of
		{ok, GamePid, Index} ->
			{ok, State#playerState{game_pid = GamePid, room_id = RoomId, index = Index}};
		{error, Reason} ->
			{error, 2, atom_to_list(Reason), State}
	end;

%% 快速匹配
handleMsg(#cs_quick_match{}, State = #playerState{name = Name}) ->
	case room_manager:quickMatch(self(), Name) of
		{ok, RoomId, GamePid, Index} ->
			{ok, State#playerState{game_pid = GamePid, room_id = RoomId, index = Index}};
		{error, Reason} ->
			{error, 4, atom_to_list(Reason), State}
	end;

%% 添加AI
handleMsg(#cs_add_ai{}, State = #playerState{room_id = RoomId}) ->
	case RoomId of
		undefined ->
			?Warn("Received cs_add_ai but RoomId is undefined. State: ~p~n", [State]),
			{error, 5, "Not in a room", State};
		_ ->
			case room_manager:addAiPlayer(RoomId) of
				{ok, AiName, Index} ->
					Reply = #sc_ai_added{name = AiName, index = Index},
					{ok, Reply, State};
				{error, Reason} ->
					{error, 5, atom_to_list(Reason), State}
			end
	end;

%% 离开房间
handleMsg(#cs_leave_room{roomId = ReqRoomId}, State = #playerState{room_id = StateRoomId}) ->
	RoomId = normalize_leave_room_id(ReqRoomId, StateRoomId),
	ClearedState = State#playerState{game_pid = undefined, room_id = undefined, index = 0},
	case RoomId of
		undefined ->
			Reply = #sc_room_update{roomId = "", status = 1, players = []},
			{ok, Reply, ClearedState};
		_ ->
			case room_manager:leaveRoom(RoomId, self()) of
				ok ->
					Reply = #sc_room_update{roomId = RoomId, status = 1, players = []},
					{ok, Reply, ClearedState};
				{error, room_not_found} ->
					Reply = #sc_room_update{roomId = RoomId, status = 1, players = []},
					{ok, Reply, ClearedState};
				{error, player_not_in_room} ->
					Reply = #sc_room_update{roomId = RoomId, status = 1, players = []},
					{ok, Reply, ClearedState};
				{error, Reason} ->
					{error, 3, atom_to_list(Reason), State}
			end
	end;

%% 开始游戏
handleMsg(#cs_game_start{}, State) ->
	case room_manager:startGame(self()) of
		{ok, RoomId, GamePid, _FirstBidder} ->
			NewState = State#playerState{room_id = RoomId, game_pid = GamePid},
			{ok, NewState};
		{error, room_not_found} ->
			{error, 6, "Not in a room", State};
		{error, waiting_ready} ->
			{error, 6, "waiting_all_ready", State};
		{error, not_enough_players} ->
			{error, 6, "not_enough_players", State};
		{error, Reason} ->
			{error, 6, atom_to_list(Reason), State}
	end;

handleMsg(#cs_ready{ready = ReadyVal}, State) ->
	Ready = ReadyVal =/= 0,
	case room_manager:setReady(self(), Ready) of
		{ok, waiting_ready} ->
			{ok, State};
		{ok, auto_started, RoomId, GamePid, _FirstBidder} ->
			NewState = State#playerState{room_id = RoomId, game_pid = GamePid},
			{ok, NewState};
		{error, room_not_found} ->
			{error, 11, "Not in a room", State};
		{error, game_in_progress} ->
			{error, 11, "game_in_progress", State};
		{error, Reason} ->
			{error, 11, atom_to_list(Reason), State}
	end;

%% 叫分
handleMsg(#cs_bid{score = Score}, State = #playerState{game_pid = GamePid}) when GamePid =/= undefined ->
	case game_server:bid(GamePid, self(), Score) of
		{ok, _Status} -> {ok, State};
		{ok, _Status, _NextTurn} -> {ok, State};
		{error, Reason} ->
			{error, 7, atom_to_list(Reason), State}
	end;
handleMsg(#cs_bid{}, State) ->
	{error, 7, "not_in_game", State};

%% 出牌
handleMsg(#cs_play{cards = Cards}, State = #playerState{game_pid = GamePid}) when GamePid =/= undefined ->
	GameCards = convert_proto_cards(Cards),
	case game_server:playCards(GamePid, self(), GameCards) of
		{ok, _Status} -> {ok, State};
		{game_over, _, _, _} -> {ok, State};
		{error, Reason} ->
			{error, 8, atom_to_list(Reason), State}
	end;
handleMsg(#cs_play{}, State) ->
	{error, 8, "not_in_game", State};

%% 不出
handleMsg(#cs_pass{}, State = #playerState{game_pid = GamePid}) when GamePid =/= undefined ->
	case game_server:pass(GamePid, self()) of
		{ok, _Status} -> {ok, State};
		{error, Reason} ->
			{error, 9, atom_to_list(Reason), State}
	end;
handleMsg(#cs_pass{}, State) ->
	{error, 9, "not_in_game", State};

%% 提示
handleMsg(#cs_play_hint{}, State = #playerState{game_pid = GamePid}) when GamePid =/= undefined ->
	case game_server:playHint(GamePid, self()) of
		{ok, HintCards} ->
			Reply = #sc_play_hint{cards = convert_game_cards(HintCards)},
			{ok, Reply, State};
		{error, Reason} ->
			{error, 10, atom_to_list(Reason), State}
	end;
handleMsg(#cs_play_hint{}, State) ->
	{error, 10, "not_in_game", State};

handleMsg(_Msg, State) ->
	?Warn("Unknown message in roleHer: ~p~n", [_Msg]),
	{ok, State}.

normalize_leave_room_id(ReqRoomId, StateRoomId) ->
	case StateRoomId of
		undefined ->
			case ReqRoomId of
				undefined -> undefined;
				"" -> undefined;
				_ -> ReqRoomId
			end;
		_ -> StateRoomId
	end.

convert_proto_cards(Cards) ->
	[{Card#card.suit, Card#card.value} || Card <- Cards].

convert_game_cards(Cards) ->
	[#card{suit = Suit, value = Value} || {Suit, Value} <- Cards].
