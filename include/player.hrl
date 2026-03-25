-ifndef(__player_h__).
-define(__player_h__, true).

-define(ReconnectTimeout, 5 * 60 * 1000). %% 5 minute reconnect window
-define(pdReconnectTimer, pdReconnectTimer).  %% 超时定时器引用字典

-define(etsPlayerRegistry, etsPlayerRegistry).

-record(playerState, {
	name,
	player_pid = undefined,
	game_pid = undefined,
	gatewayPid = undefined,
	cards = [],
	score = 0,
	wins = 0,
	losses = 0,
	index = 0,
	role = none,
	room_id = undefined
}).

-endif.