-ifndef(gateway_hrl__).
-define(gateway_hrl__, true).

-define(GwPacket, 4).
-define(GwActive, 256).

%% 握手相关 算法 前端随机32位整数Num 然后 Num bxor EncryptMagic1 + EncryptMagic2 ==> Num2 简单防止被恶意连接攻击
-define(EncryptMagic1, 16#9E3779B9).	 %% 握手魔数1
-define(EncryptMagic2, 16#3C6EF372).
-define(HandshakeTime, 3500).            %% 握手超时时间 3.5秒 过短可能导致网络波动时握手失败过长可能被攻击者利用进行资源占用攻击
-define(pdHandshakeTimer, pdHandshakeTimer).

-define(GatewayMaxSize, 1 * 1024 * 1024).

-define(CheckInterval, 10000).           %% 统一检查间隔 10秒
-define(pdCheckTimer, pdCheckTimer).     %% 统一检查定时器
-define(pdHeartbeatLastTime, pdHeartbeatLastTime). %% 上次收到消息的时间戳
-define(pdPacketCnt, pdPacketCnt).        %% 收到的包计数
-define(pdPacketFastCnt, pdPacketFastCnt). %% 连续快速发包次数

-define(PacketNormalLimit, 250).         %% 正常每秒收包数量
-define(PacketWarningLimit, 375).        %% 警告阈值 (1.5倍)
-define(PacketKickLimit, 500).           %% 踢人阈值 (2倍)
-define(PacketFastMaxCnt, 5).            %% 连续快速收包最大次数
-define(HeartbeatTimeout, 180000).       %% 心跳超时 3分钟

-define(LTcpOpts, [
   binary
   , {packet, raw}
   , {packet_size, ?GatewayMaxSize}% 1M 限制通过 gen_tcp 接收的数据包最大长度‌，以提升安全性并防止资源耗尽攻击
   , {reuseaddr, true}
   , {backlog, 4096}
   , {active, false}
   , {buffer, 128 * 1024}              % 接收缓冲区
   , {recbuf, 128 * 1024}              % 内核接收缓冲区 通常接受的数据比较小
   , {sndbuf, 512 * 1024}              % 内核发送缓冲区
   , {high_watermark, 128 * 1024}      % Erlang内部Socket实现的数据队列  当队列数据量达到此阈值时，Socket标记为**繁忙（busy）**，发送进程会被挂起。
   , {low_watermark, 16 * 1024}        % 当队列数据量降低到此阈值时，Socket恢复**非繁忙状态**，允许继续发送。
   , {high_msgq_watermark, 64 * 1024}  % Erlang进程消息队列**的繁忙状态 消息队列数据量达到此值时，队列标记为繁忙，阻止新消息进入
   , {low_msgq_watermark, 32 * 1024}   % 消息队列数据量低于此值时，恢复非繁忙状态
]).

-define(CTcpOpts, [
	binary
	, {packet, ?GwPacket}
   , {packet_size, ?GatewayMaxSize}    % 1M 限制通过 gen_tcp 接收的数据包最大长度‌，以提升安全性并防止资源耗尽攻击
	, {active, ?GwActive}
	, {nodelay, true}                   % 禁用Nagle 可以减少延迟(对于需要低延迟的游戏)
	, {delay_send, true}                % 提升吞吐量 尤其在高并发场景下，减少调度器争用 增加约10-50μs的延迟（取决于队列深度和调度频率）
	, {send_timeout, 30000}             % 发送超时时间
	, {send_timeout_close, true}        % 发送超时自动关闭连接（防止半开连接）
	, {keepalive, true}                 % 检测死连接（默认间隔2小时，需系统级调整）
	, {exit_on_close, true}             % 当socket被关闭时，与其关联的控制进程（controlling process） 会收到{'EXIT', Port, Reason}信号 强制清理异常连接
	, {buffer, 128 * 1024}              % 接收缓冲区1MB
	, {recbuf, 128 * 1024}              % 内核接收缓冲区 通常接受的数据比较小
	, {sndbuf, 512 * 1024}              % 内核发送缓冲区
	, {high_watermark, 128 * 1024}      % Erlang内部Socket实现的数据队列  当队列数据量达到此阈值时，Socket标记为**繁忙（busy）**，发送进程会被挂起。
   , {low_watermark, 16 * 1024}        % 当队列数据量降低到此阈值时，Socket恢复**非繁忙状态**，允许继续发送。
	, {high_msgq_watermark, 64 * 1024}  % Erlang进程消息队列**的繁忙状态 消息队列数据量达到此值时，队列标记为繁忙，阻止新消息进入
	, {low_msgq_watermark, 32 * 1024}   % 消息队列数据量低于此值时，恢复非繁忙状态
]).


-define(GWVerify, 0).  	%% 等待握手
-define(GWPass, 1).   	%% 握手通过等待登录
-define(GWLogin, 2).   	%% 登录完成

-record(gatewayState, {
	socket = undefined,
	playerPid = undefined,
	player_id = 0,
	
	ip :: inet:ip_address(),
	port :: inet:port_number(),
	gwStatus = ?GWVerify :: non_neg_integer(),
	role = undefined :: undefined | term(),
	recv1 = 0 :: non_neg_integer(),
	recv2 = 0 :: non_neg_integer(),
	error = 0 :: non_neg_integer(),
	fast = 0 :: non_neg_integer(),
	heart = undefined :: undefined | reference()
	
}).

-endif.
