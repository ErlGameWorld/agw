-ifndef(__game_h__).
-define(__game_h__, true).

%%% 游戏系统记录定义
%%% Created: 2025-02-21 05:01:23 UTC
%%% Author: SisMaker
%%% 斗地主牌型定义
%%% Created: 2023-05-15
%%% Author: AI Assistant

%% assets缓存
-define(assetsCache, assetsCache).

%% 牌型定义
-define(CARD_TYPE_SINGLE, single).       % 单牌
-define(CARD_TYPE_PAIR, pair).           % 对子
-define(CARD_TYPE_THREE, triple).       % 三张
-define(CARD_TYPE_THREE_ONE, three_one). % 三带一
-define(CARD_TYPE_THREE_TWO, three_two). % 三带二
-define(CARD_TYPE_STRAIGHT, straight).   % 顺子
-define(CARD_TYPE_STRAIGHT_PAIR, straight_pair). % 连对
-define(CARD_TYPE_PLANE, plane).         % 飞机
-define(CARD_TYPE_PLANE_ONE, plane_one). % 飞机带单
-define(CARD_TYPE_PLANE_TWO, plane_two). % 飞机带对
-define(CARD_TYPE_FOUR_TWO, four_two).   % 四带二
-define(CARD_TYPE_BOMB, bomb).           % 炸弹
-define(CARD_TYPE_ROCKET, rocket).       % 火箭

%% 斗地主AI状态记录
-record(state, {
	player_id,           % AI 玩家ID
	role,               % dizhu | nongmin (地主或农民)
	known_cards = [],   % 已知的牌
	hand_cards = [],    % 手牌
	played_cards = [],  % 已打出的牌
	other_players = [], % 其他玩家信息
	game_history = [],  % 游戏历史
	strategy_cache = #{} % 策略缓存
}).

%% 牌值定义
-define(CARD_VALUE_3, 3).
-define(CARD_VALUE_4, 4).
-define(CARD_VALUE_5, 5).
-define(CARD_VALUE_6, 6).
-define(CARD_VALUE_7, 7).
-define(CARD_VALUE_8, 8).
-define(CARD_VALUE_9, 9).
-define(CARD_VALUE_10, 10).
-define(CARD_VALUE_J, 11).
-define(CARD_VALUE_Q, 12).
-define(CARD_VALUE_K, 13).
-define(CARD_VALUE_A, 14).
-define(CARD_VALUE_2, 15).
-define(CARD_VALUE_SMALL_JOKER, 16).
-define(CARD_VALUE_BIG_JOKER, 17).


%% 游戏状态记录
-record(game_state, {
    players = [],          % [{Pid, Cards, Role}]
    current_player,        % Pid
    last_play = [],        % {Pid, Cards}
    played_cards = [],     % [{Pid, Cards}]
    stage = waiting,       % waiting | playing | finished
    landlord_cards = []    % 地主牌
}).

%% AI状态记录
-record(ai_state1, {
    strategy_model,        % 策略模型
    learning_model,        % 学习模型
    opponent_model,        % 对手模型
    personality,           % aggressive | conservative | balanced
    performance_stats = [] % 性能统计
}).

%% 学习系统状态记录
-record(learning_state, {
    neural_network,        % 深度神经网络模型
    experience_buffer,     % 经验回放缓冲
    model_version,         % 模型版本
    training_stats         % 训练统计
}).

%% 对手模型记录
-record(opponent_model, {
    play_patterns = #{},    % 出牌模式统计
    card_preferences = #{}, % 牌型偏好
    risk_profile = 0.5,    % 风险偏好
    skill_rating = 500,    % 技能评分
    play_history = []      % 历史出牌记录
}).

%% 策略状态记录
-record(strategy_state, {
    current_strategy,      % 当前策略
    performance_metrics,   % 性能指标
    adaptation_rate,       % 适应率
    optimization_history   % 优化历史
}).

%% 游戏管理器状态记录
-record(game_manager_state, {
    game_id,              % 游戏ID
    players,              % 玩家列表
    ai_players,           % AI玩家
    current_state,        % 当前游戏状态
    history,              % 游戏历史
    room_config = #{}     % 房间配置
}).

%% 牌型记录
-record(card_pattern, {
    type,                 % single | pair | triple | straight | bomb | rocket
    value,                % 主牌值
    length = 1,           % 顺子长度
    extra = []            % 附加牌
}).

-endif.