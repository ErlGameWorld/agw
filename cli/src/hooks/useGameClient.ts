import { useState, useEffect, useRef, useCallback } from 'react';
import { message } from 'antd';
import { WSClient } from '../network/WSClient';

export type AppStage = 'login' | 'lobby' | 'game';

export interface Player {
  index: number;
  name: string;
  cardCount: number;
  role: 'landlord' | 'peasant' | 'none';
  isTurn: boolean;
  ready: boolean;
}

export interface GameCard {
  suit: number;
  value: number;
}

export interface PlayerInfo {
  index: number;
  name: string;
  score: number;
  wins: number;
  losses: number;
  status: number;
}

type RuntimeGatewayConfig = {
  wsUrl?: string;
  wsHost?: string;
  wsPort?: string | number;
  wsProtocol?: string;
};

type RoomInfo = {
  roomId: string;
  name: string;
  playerCount: number;
  status: number;
};

type ServerMessage = {
  sc_login?: { result: number; player: PlayerInfo };
  sc_list_rooms?: { rooms?: RoomInfo[] };
  sc_room_update?: { roomId: string; status: number; players?: PlayerInfo[] };
  sc_ai_added?: { name: string };
  sc_game_start?: { cards?: GameCard[]; firstBidder?: number };
  sc_turn_to_bid?: { nextTurn?: number };
  sc_bid_made?: { playerIdx: number; score: number };
  sc_landlord_selected?: { landlordIdx?: number; landlordCards?: GameCard[] };
  sc_turn_to_play?: { nextTurn?: number; lastPlay?: GameCard[] };
  sc_player_played?: { playerIdx: number; cards?: GameCard[] };
  sc_player_passed?: { playerIdx: number };
  sc_play_hint?: { cards?: GameCard[] };
  sc_game_over?: { winnerIdx: number };
  sc_player_ready?: { playerIdx: number; ready?: number; allReady?: number };
  sc_error?: { msg?: string };
};

const suitVoiceMap: Record<number, string> = {
  1: '黑桃',
  2: '红桃',
  3: '梅花',
  4: '方块'
};

const valueVoiceMap: Record<number, string> = {
  3: '3',
  4: '4',
  5: '5',
  6: '6',
  7: '7',
  8: '8',
  9: '9',
  10: '10',
  11: 'J',
  12: 'Q',
  13: 'K',
  14: 'A',
  15: '2',
  16: '小王',
  17: '大王'
};

const isVoiceEnabled = (): boolean => {
  if (typeof window === 'undefined') {
    return false;
  }
  return window.localStorage.getItem('ddz_voice_enabled') !== '0';
};

const speakVoice = (text: string) => {
  if (typeof window === 'undefined' || !isVoiceEnabled() || !('speechSynthesis' in window)) {
    return;
  }
  window.speechSynthesis.cancel();
  const utterance = new SpeechSynthesisUtterance(text);
  utterance.lang = 'zh-CN';
  utterance.rate = 1.05;
  utterance.pitch = 1;
  window.speechSynthesis.speak(utterance);
};

const playGameOverEffect = (isWin: boolean) => {
  if (typeof window === 'undefined' || !isVoiceEnabled()) {
    return;
  }
  const Ctx = window.AudioContext || (window as Window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
  if (!Ctx) {
    return;
  }
  const ctx = new Ctx();
  if (ctx.state === 'suspended') {
    ctx.resume();
  }
  const notes = isWin ? [523, 659, 784, 988] : [392, 330, 262, 196];
  const duration = isWin ? 0.2 : 0.24;
  notes.forEach((frequency, index) => {
    const startAt = ctx.currentTime + index * (duration + 0.04);
    const oscillator = ctx.createOscillator();
    const gain = ctx.createGain();
    oscillator.type = isWin ? 'triangle' : 'sawtooth';
    oscillator.frequency.value = frequency;
    gain.gain.setValueAtTime(0.0001, startAt);
    gain.gain.exponentialRampToValueAtTime(isWin ? 0.06 : 0.05, startAt + 0.03);
    gain.gain.exponentialRampToValueAtTime(0.0001, startAt + duration);
    oscillator.connect(gain);
    gain.connect(ctx.destination);
    oscillator.start(startAt);
    oscillator.stop(startAt + duration);
  });
  const closeDelay = Math.max(600, notes.length * (duration + 0.04) * 1000 + 120);
  window.setTimeout(() => {
    ctx.close();
  }, closeDelay);
};

const cardToVoice = (card: GameCard): string => {
  const valueText = valueVoiceMap[card.value] ?? String(card.value);
  if (card.value >= 16 || card.suit === 0) {
    return valueText;
  }
  const suitText = suitVoiceMap[card.suit] ?? '';
  return `${suitText}${valueText}`;
};

const cardsToVoiceText = (cards: GameCard[]): string => {
  if (cards.length === 0) {
    return '空牌';
  }
  return cards.map(cardToVoice).join('，');
};

const getWsUrl = (): string => {
  if (typeof window === 'undefined') {
    return 'ws://127.0.0.1:9300/';
  }
  const runtimeConfig = (window as Window & { __AGW_CONFIG__?: RuntimeGatewayConfig }).__AGW_CONFIG__;
  if (runtimeConfig?.wsUrl && runtimeConfig.wsUrl.trim().length > 0) {
    return runtimeConfig.wsUrl;
  }
  const configuredUrl = import.meta.env.VITE_WS_URL as string | undefined;
  if (configuredUrl && configuredUrl.trim().length > 0) {
    return configuredUrl;
  }
  const protocol = runtimeConfig?.wsProtocol || (window.location.protocol === 'https:' ? 'wss' : 'ws');
  const host = runtimeConfig?.wsHost || window.location.hostname || '127.0.0.1';
  const port = runtimeConfig?.wsPort || (import.meta.env.VITE_WS_PORT as string | undefined) || '9300';
  return `${protocol}://${host}:${port}/`;
};

export const useGameClient = () => {
  const [stage, setStage] = useState<AppStage>('login');
  const [rooms, setRooms] = useState<RoomInfo[]>([]);
  const [myCards, setMyCards] = useState<GameCard[]>([]);
  const [myIndex, setMyIndex] = useState<number>(0);
  const [currentRoomId, setCurrentRoomId] = useState<string>('');
  const [playerInfo, setPlayerInfo] = useState<PlayerInfo | undefined>();

  const [gameStatus, setGameStatus] = useState<'waiting' | 'ready' | 'bidding' | 'playing' | 'finished'>('waiting');
  const [lastPlay, setLastPlay] = useState<GameCard[]>([]);
  const [currentTurn, setCurrentTurn] = useState<number>(0);
  const [landlordIdx, setLandlordIdx] = useState<number>(0);
  const [players, setPlayers] = useState<Player[]>([]);
  const [gameOverData, setGameOverData] = useState<{ isWin: boolean; winnerIdx: number } | null>(null);

  const wsRef = useRef<WSClient | null>(null);
  const playerInfoRef = useRef<PlayerInfo | undefined>(undefined);
  const myIndexRef = useRef<number>(0);
  const stageRef = useRef<AppStage>('login');
  const gameStatusRef = useRef<'waiting' | 'ready' | 'bidding' | 'playing' | 'finished'>('waiting');
  const playersCountRef = useRef<number>(0);
  const playHintResolverRef = useRef<((cards: GameCard[]) => void) | null>(null);
  const playHintRejectRef = useRef<((reason?: unknown) => void) | null>(null);
  const playHintTimerRef = useRef<number | null>(null);

  const setTurn = useCallback((turn: number) => {
    setCurrentTurn(turn);
    setPlayers(prev => prev.map(p => ({
      ...p,
      isTurn: p.index === turn
    })));
  }, []);

  const sortCards = useCallback((cards: GameCard[]) => {
    return [...cards].sort((a, b) => {
      if (b.value !== a.value) return b.value - a.value;
      return b.suit - a.suit;
    });
  }, []);

  const handleMessage = useCallback((rawMsg: Record<string, unknown>) => {
    const msg = rawMsg as ServerMessage;
    console.log("App received msg:", msg);

    if (msg.sc_login) {
      if (msg.sc_login.result === 0) {
        setPlayerInfo(msg.sc_login.player);
        playerInfoRef.current = msg.sc_login.player;
        setStage('lobby');
        wsRef.current?.send({cs_list_rooms: {}});
        localStorage.setItem('last_username', msg.sc_login.player.name);
      } else {
        message.error("登录失败");
      }
    } else if (msg.sc_list_rooms) {
      setRooms(msg.sc_list_rooms.rooms || []);
    } else if (msg.sc_room_update) {
      const roomId = msg.sc_room_update.roomId;
      const status = msg.sc_room_update.status;
      const roomPlayers = msg.sc_room_update.players || [];

      if (stageRef.current === 'lobby') {
        wsRef.current?.send({cs_list_rooms: {}});
      }

      if (status === 0 || status === 2) {
        setCurrentRoomId(roomId);
        setStage('game');

        if (roomPlayers.length > 0) {
          setPlayers(prev => {
            const newPlayerList: Player[] = roomPlayers.map((p: PlayerInfo) => {
              const existing = prev.find(ep => ep.index === p.index);
              return {
                index: p.index,
                name: p.name,
                cardCount: existing ? existing.cardCount : 17,
                role: existing ? existing.role : 'none',
                isTurn: existing ? existing.isTurn : false,
                ready: existing ? existing.ready : false
              };
            });
            return newPlayerList;
          });
          playersCountRef.current = roomPlayers.length;
          if (roomPlayers.length < 3) {
            setGameStatus('waiting');
          } else if (gameStatusRef.current !== 'bidding' && gameStatusRef.current !== 'playing') {
            setGameStatus('ready');
          }

          const markedSelf = roomPlayers.find((p: PlayerInfo) => p.status === 2);
          const matchedByName = roomPlayers.find((p: PlayerInfo) => p.name === playerInfoRef.current?.name);
          const matchedByIndex = roomPlayers.find((p: PlayerInfo) => p.index === myIndexRef.current);
          const myPlayer = markedSelf || matchedByName || matchedByIndex;
          if (myPlayer) {
            setMyIndex(myPlayer.index);
            myIndexRef.current = myPlayer.index;
          }
        }
      } else if (status === 1) {
        if (roomPlayers.length === 0) {
          setCurrentRoomId('');
          setStage('lobby');
          setPlayers([]);
          setMyCards([]);
          setLastPlay([]);
          setCurrentTurn(0);
          setLandlordIdx(0);
          setGameStatus('waiting');
          setMyIndex(0);
          myIndexRef.current = 0;
          playersCountRef.current = 0;
          wsRef.current?.send({cs_list_rooms: {}});
        } else {
          setPlayers(prev => roomPlayers.map((p: PlayerInfo) => {
            const existing = prev.find(ep => ep.index === p.index);
            return {
              index: p.index,
              name: p.name,
              cardCount: existing ? existing.cardCount : 17,
              role: existing ? existing.role : 'none',
              isTurn: existing ? existing.isTurn : false,
              ready: existing ? existing.ready : false
            };
          }));
          playersCountRef.current = roomPlayers.length;
          setGameStatus(roomPlayers.length < 3 ? 'waiting' : 'ready');
          setTurn(0);
          setLandlordIdx(0);
          setLastPlay([]);
          setMyCards([]);
        }
      }
    } else if (msg.sc_ai_added) {
      message.success(`AI玩家 ${msg.sc_ai_added.name} 已加入`);
    } else if (msg.sc_game_start) {
      const cards = msg.sc_game_start.cards || [];
      setMyCards(sortCards(cards));
      const firstBidder = msg.sc_game_start.firstBidder || 1;
      setTurn(firstBidder);
      setGameStatus('bidding');
      setPlayers(prev => prev.map(p => ({
        ...p,
        cardCount: 17,
        role: 'none',
        isTurn: p.index === firstBidder,
        ready: false
      })));
      playersCountRef.current = 3;
      message.info("游戏开始，请叫分");
    } else if (msg.sc_player_ready) {
      const playerIdx = msg.sc_player_ready.playerIdx;
      const ready = msg.sc_player_ready.ready === 1;
      const allReady = msg.sc_player_ready.allReady === 1;
      setPlayers(prev => prev.map(p =>
        p.index === playerIdx ? { ...p, ready } : p
      ));
      if (gameStatusRef.current !== 'bidding' && gameStatusRef.current !== 'playing') {
        setGameStatus(allReady ? 'ready' : (playersCountRef.current >= 3 ? 'ready' : 'waiting'));
      }
      message.info(`玩家 ${playerIdx} ${ready ? '已准备' : '取消准备'}`);
    } else if (msg.sc_turn_to_bid) {
      setTurn(msg.sc_turn_to_bid.nextTurn || 0);
    } else if (msg.sc_bid_made) {
      const bidderIdx = msg.sc_bid_made.playerIdx;
      const score = msg.sc_bid_made.score;
      message.info(score === 0 ? `玩家 ${bidderIdx} 不叫` : `玩家 ${bidderIdx} 叫 ${score} 分`);
    } else if (msg.sc_landlord_selected) {
      const landlord = msg.sc_landlord_selected.landlordIdx || 0;
      setLandlordIdx(landlord);
      setTurn(landlord);
      setGameStatus('playing');

      if (msg.sc_landlord_selected.landlordCards && myIndexRef.current === landlord) {
        setMyCards(prev => sortCards([...prev, ...msg.sc_landlord_selected!.landlordCards!]));
      }

      setPlayers(prev => prev.map(p => ({
        ...p,
        role: p.index === landlord ? 'landlord' : 'peasant',
        cardCount: p.index === landlord ? 20 : 17,
        isTurn: p.index === landlord
      })));
      message.info(`玩家 ${landlord} 成为地主`);
    } else if (msg.sc_turn_to_play) {
      const nextTurn = msg.sc_turn_to_play.nextTurn || 0;
      setTurn(nextTurn);
      setLastPlay(msg.sc_turn_to_play.lastPlay || []);
    } else if (msg.sc_player_played) {
      const playerIdx = msg.sc_player_played.playerIdx;
      const cards = msg.sc_player_played.cards || [];

      setPlayers(prev => prev.map(p =>
        p.index === playerIdx ? { ...p, cardCount: Math.max(0, p.cardCount - cards.length) } : p
      ));

      if (playerIdx === myIndexRef.current) {
        const playedKeys = new Set(cards.map((c: GameCard) => `${c.suit}-${c.value}`));
        setMyCards(prev => prev.filter(c => !playedKeys.has(`${c.suit}-${c.value}`)));
      }
      speakVoice(`玩家${playerIdx}出牌，${cardsToVoiceText(cards)}`);
    } else if (msg.sc_player_passed) {
      const playerIdx = msg.sc_player_passed.playerIdx;
      message.info(`玩家 ${playerIdx} 不出`);
      speakVoice(`玩家${playerIdx}不出`);
    } else if (msg.sc_play_hint) {
      if (playHintTimerRef.current !== null) {
        window.clearTimeout(playHintTimerRef.current);
        playHintTimerRef.current = null;
      }
      playHintResolverRef.current?.(msg.sc_play_hint.cards || []);
      playHintResolverRef.current = null;
      playHintRejectRef.current = null;
    } else if (msg.sc_game_over) {
      const winnerIdx = msg.sc_game_over.winnerIdx;
      if (winnerIdx === 0) {
        message.warning("游戏由于玩家离开而终止");
        setGameStatus('waiting');
        setMyCards([]);
        setLastPlay([]);
        setPlayers(prev => prev.map(p => ({ ...p, cardCount: 17, role: 'none', ready: false })));
        return;
      }

      setGameStatus('finished');
      const isWin = winnerIdx === myIndexRef.current;
      playGameOverEffect(isWin);
      speakVoice(isWin ? '恭喜获胜' : '很遗憾，失败了');
      setGameOverData({ isWin, winnerIdx });

    } else if (msg.sc_error) {
      if (playHintTimerRef.current !== null) {
        window.clearTimeout(playHintTimerRef.current);
        playHintTimerRef.current = null;
      }
      playHintRejectRef.current?.(new Error(msg.sc_error.msg || '未知错误'));
      playHintResolverRef.current = null;
      playHintRejectRef.current = null;
      message.error(`错误: ${msg.sc_error.msg || '未知错误'}`);
    }
  }, [sortCards, setTurn]);

  useEffect(() => {
    wsRef.current = new WSClient(getWsUrl(), handleMessage);

    return () => {
      wsRef.current?.disconnect();
      wsRef.current = null;
    };
  }, [handleMessage]);

  useEffect(() => {
    stageRef.current = stage;
  }, [stage]);

  useEffect(() => {
    gameStatusRef.current = gameStatus;
  }, [gameStatus]);

  useEffect(() => {
    playersCountRef.current = players.length;
  }, [players.length]);

  const login = useCallback((name: string) => {
    const client = wsRef.current;
    if (!client) {
      message.error("客户端未初始化");
      return;
    }
    if (client.isConnected()) {
      client.send({cs_login: {name}});
    } else {
      client.connect().then(() => {
        message.success("服务器连接成功");
        client.send({cs_login: {name}});
      }).catch((err) => {
        console.error("Connect error:", err);
        message.error("无法连接到服务器");
      });
    }
  }, []);

  const createRoom = useCallback((name: string) => wsRef.current?.send({cs_create_room: {name}}), []);
  const joinRoom = useCallback((roomId: string) => wsRef.current?.send({cs_join_room: {roomId}}), []);
  const quickMatch = useCallback(() => wsRef.current?.send({cs_quick_match: {}}), []);
  const addAi = useCallback(() => wsRef.current?.send({cs_add_ai: {}}), []);
  const setReady = useCallback((ready: boolean) => wsRef.current?.send({cs_ready: {ready: ready ? 1 : 0}}), []);
  const playCards = useCallback((cards: GameCard[]) => wsRef.current?.send({cs_play: {cards}}), []);
  const passTurn = useCallback(() => wsRef.current?.send({cs_pass: {}}), []);

  const playHint = useCallback(() => {
    if (!wsRef.current?.send({cs_play_hint: {}})) {
      return Promise.reject(new Error('发送提示请求失败'));
    }
    if (playHintTimerRef.current !== null) {
      window.clearTimeout(playHintTimerRef.current);
      playHintTimerRef.current = null;
    }
    return new Promise<GameCard[]>((resolve, reject) => {
      playHintResolverRef.current = resolve;
      playHintRejectRef.current = reject;
      playHintTimerRef.current = window.setTimeout(() => {
        playHintRejectRef.current?.(new Error('提示超时'));
        playHintResolverRef.current = null;
        playHintRejectRef.current = null;
      }, 5000);
    });
  }, []);

  const bid = useCallback((score: number) => wsRef.current?.send({cs_bid: {score}}), []);

  const leaveRoom = useCallback(() => {
    setStage('lobby');
    setGameStatus('waiting');
    setMyCards([]);
    setLastPlay([]);
    setCurrentTurn(0);
    setLandlordIdx(0);
    setPlayers([]);
    setMyIndex(0);
    myIndexRef.current = 0;
    playersCountRef.current = 0;
    setCurrentRoomId('');
    wsRef.current?.send({cs_leave_room: {}});
  }, []);

  const startGame = useCallback(() => wsRef.current?.send({cs_start_game: {}}), []);

  const refreshRooms = useCallback(() => wsRef.current?.send({cs_list_rooms: {}}), []);

  const resetGame = useCallback(() => {
    setGameStatus('waiting');
    setMyCards([]);
    setLastPlay([]);
    setCurrentTurn(0);
    setLandlordIdx(0);
    setPlayers([]);
    setMyIndex(0);
    myIndexRef.current = 0;
    playersCountRef.current = 0;
    setGameOverData(null);
  }, []);

  const myReady = players.find(p => p.index === myIndex)?.ready || false;
  const allReady = players.length === 3 && players.every(p => p.ready);

  return {
    stage,
    playerInfo,
    rooms,
    currentRoomId,
    myCards,
    myIndex,
    players,
    gameStatus,
    currentTurn,
    landlordIdx,
    lastPlay,
    gameOverData,
    myReady,
    allReady,
    actions: {
      login,
      createRoom,
      joinRoom,
      quickMatch,
      addAi,
      setReady,
      playCards,
      passTurn,
      playHint,
      bid,
      leaveRoom,
      startGame,
      refreshRooms,
      resetGame
    }
  };
};
