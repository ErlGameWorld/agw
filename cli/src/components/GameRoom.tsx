import React, { useEffect, useRef, useState } from 'react';
import { Button, Tag, Space, message, Avatar } from 'antd';
import { UserOutlined } from '@ant-design/icons';

interface GameCard {
  suit: number;
  value: number;
}

interface Player {
  index: number;
  name: string;
  cardCount: number;
  role: 'landlord' | 'peasant' | 'none';
  isTurn: boolean;
  ready: boolean;
}

interface GameRoomProps {
  myCards: GameCard[];
  myIndex: number;
  players: Player[];
  currentTurn: number;
  landlordIdx: number;
  lastPlay: GameCard[];
  onPlay: (cards: GameCard[]) => void;
  onPass: () => void;
  onHint?: () => Promise<GameCard[]>;
  onBid: (score: number) => void;
  gameStatus: 'bidding' | 'playing' | 'waiting' | 'ready' | 'finished';
  onLeave: () => void;
  onToggleReady: (ready: boolean) => void;
  myReady: boolean;
  allReady: boolean;
  onAddAi?: () => void;
}

const suitMap: {[key: number]: string} = { 1: '♠', 2: '♥', 3: '♣', 4: '♦', 0: '' };
const valueMap: {[key: number]: string} = {
  3: '3', 4: '4', 5: '5', 6: '6', 7: '7', 8: '8', 9: '9', 10: '10',
  11: 'J', 12: 'Q', 13: 'K', 14: 'A', 15: '2', 16: '小王', 17: '大王'
};

const getRelativePosition = (myIdx: number, targetIdx: number) => {
    if (myIdx === 0 || targetIdx === 0) return 'unknown';
    // Indices are 1-based (1, 2, 3)
    const diff = (targetIdx - myIdx + 3) % 3;
    if (diff === 1) return 'right';
    if (diff === 2) return 'left';
    return 'unknown';
};

const renderCard = (card: GameCard, index: number, total: number, selected: boolean, onClick: () => void) => {
  const label = card.suit === 0 
    ? valueMap[card.value] || `${card.value}` 
    : `${suitMap[card.suit] || ''}${valueMap[card.value] || card.value}`;
  const color = (card.suit === 2 || card.suit === 4 || card.value === 17) ? '#d4380d' : '#1f1f1f';
  
  // Calculate dynamic spacing
  const maxVisibleWidth = 35; 
  const minVisibleWidth = 20;
  const availableWidth = Math.min(window.innerWidth - 40, 800);
  const cardWidth = 80;
  
  // Calculate overlap
  // total width = cardWidth + (total - 1) * offset
  // offset = (total width - cardWidth) / (total - 1)
  
  let offset = maxVisibleWidth;
  if (total > 1) {
      const requiredWidth = cardWidth + (total - 1) * maxVisibleWidth;
      if (requiredWidth > availableWidth) {
          offset = Math.max(minVisibleWidth, (availableWidth - cardWidth) / (total - 1));
      }
  }

  const centerOffset = ((total - 1) * offset) / 2;
  const left = `calc(50% + ${index * offset - centerOffset - cardWidth / 2}px)`;

  return (
    <div 
      key={`${card.suit}-${card.value}-${index}`}
      onClick={onClick}
      style={{
        border: '1px solid #d9d9d9',
        borderRadius: 6,
        width: cardWidth,
        height: 110,
        display: 'flex',
        justifyContent: 'center',
        alignItems: 'center',
        background: selected ? '#e6f7ff' : '#fff',
        color: color,
        cursor: 'pointer',
        fontSize: 22,
        fontWeight: 'bold',
        position: 'absolute',
        left: left,
        top: selected ? -20 : 0,
        transition: 'all 0.2s cubic-bezier(0.4, 0, 0.2, 1)',
        boxShadow: selected 
            ? '0 -4px 12px rgba(0,0,0,0.15)' 
            : '1px 1px 4px rgba(0,0,0,0.1)',
        zIndex: index,
        userSelect: 'none',
      }}
    >
      <div style={{ position: 'absolute', top: 4, left: 6, fontSize: 14 }}>{label}</div>
      <div>{label}</div>
    </div>
  );
};

const TURN_COUNTDOWN_SECONDS = 30;
const COMMON_PHRASES = ['不要', '要不起', '过', '稳住', '炸他', '我出牌'];

type AvatarPalette = {
  bg1: string;
  bg2: string;
  hair: string;
  skin: string;
  shirt: string;
};

const avatarPalettes: AvatarPalette[] = [
  { bg1: '#1d4ed8', bg2: '#06b6d4', hair: '#111827', skin: '#f1c27d', shirt: '#6366f1' },
  { bg1: '#7c3aed', bg2: '#ec4899', hair: '#3f3f46', skin: '#e8b17a', shirt: '#a855f7' },
  { bg1: '#059669', bg2: '#14b8a6', hair: '#0f172a', skin: '#f0bf87', shirt: '#10b981' },
  { bg1: '#ea580c', bg2: '#ef4444', hair: '#1f2937', skin: '#e9b98a', shirt: '#f97316' },
  { bg1: '#0f766e', bg2: '#3b82f6', hair: '#18181b', skin: '#f2c38b', shirt: '#2563eb' }
];

const getAvatarSeed = (name: string) => [...name].reduce((acc, ch) => acc + ch.charCodeAt(0), 0);

const getAvatarPalette = (name: string, role: Player['role']): AvatarPalette => {
  if (role === 'landlord') {
    return { bg1: '#b45309', bg2: '#ef4444', hair: '#111827', skin: '#f1be86', shirt: '#f59e0b' };
  }
  const seed = getAvatarSeed(name);
  return avatarPalettes[seed % avatarPalettes.length];
};

const getAvatarStyle = (role: Player['role'], isTurn: boolean): React.CSSProperties => ({
  background: 'transparent',
  border: `2px solid ${role === 'landlord' ? 'rgba(251,191,36,0.95)' : 'rgba(255,255,255,0.9)'}`,
  boxShadow: isTurn ? '0 0 0 4px rgba(24, 144, 255, 0.28)' : '0 8px 20px rgba(15, 23, 42, 0.28)',
  overflow: 'hidden'
});

const renderAvatarSvg = (name: string, role: Player['role']) => {
  const seed = getAvatarSeed(name || '玩家');
  const palette = getAvatarPalette(name || '玩家', role);
  const eyeOffset = (seed % 3) - 1;
  const smilePath = seed % 2 === 0 ? 'M24 43 Q32 49 40 43' : 'M24 44 Q32 47 40 44';
  const hairHeight = 13 + (seed % 4);
  const gradId = `avatar-grad-${seed}-${role}`;

  return (
    <svg viewBox="0 0 64 64" width="100%" height="100%" xmlns="http://www.w3.org/2000/svg">
      <defs>
        <linearGradient id={gradId} x1="0" y1="0" x2="1" y2="1">
          <stop offset="0%" stopColor={palette.bg1} />
          <stop offset="100%" stopColor={palette.bg2} />
        </linearGradient>
      </defs>
      <rect width="64" height="64" rx="32" fill={`url(#${gradId})`} />
      <circle cx="32" cy="34" r="16" fill={palette.skin} />
      <path d={`M16 ${34 - hairHeight} Q32 ${8 - (seed % 3)} 48 ${34 - hairHeight} L48 31 Q32 23 16 31 Z`} fill={palette.hair} />
      <circle cx={26 + eyeOffset} cy="35" r="1.8" fill="#1f2937" />
      <circle cx={38 + eyeOffset} cy="35" r="1.8" fill="#1f2937" />
      <path d={smilePath} stroke="#7c2d12" strokeWidth="1.8" fill="none" strokeLinecap="round" />
      <path d="M14 62 Q32 46 50 62 Z" fill={palette.shirt} />
      {role === 'landlord' && (
        <path d="M20 16 L26 8 L32 15 L38 8 L44 16 L44 20 L20 20 Z" fill="#facc15" stroke="#fde68a" strokeWidth="1" />
      )}
    </svg>
  );
};

const PlayerCard: React.FC<{ player: Player; turnCountdown?: number }> = ({ player, turnCountdown }) => {
  const roleColor = player.role === 'landlord' ? 'red' : player.role === 'peasant' ? 'blue' : 'default';
  const roleText = player.role === 'landlord' ? '地主' : player.role === 'peasant' ? '农民' : '';
  
  return (
    <div style={{ 
        display: 'flex', 
        flexDirection: 'column', 
        alignItems: 'center',
        padding: 16,
        background: player.isTurn ? 'rgba(24,144,255,0.1)' : 'rgba(255,255,255,0.8)',
        borderRadius: 12,
        border: player.isTurn ? '2px solid #1890ff' : '1px solid transparent',
        transition: 'all 0.3s',
        backdropFilter: 'blur(10px)',
        width: 140
    }}>
      <Avatar size={64} style={getAvatarStyle(player.role, player.isTurn)}>
        {renderAvatarSvg(player.name, player.role)}
      </Avatar>
      <div style={{ fontWeight: 'bold', marginTop: 8, fontSize: 16 }}>{player.name}</div>
      {roleText && <Tag color={roleColor} style={{ marginTop: 4 }}>{roleText}</Tag>}
      {!roleText && player.ready && <Tag color="green" style={{ marginTop: 4 }}>已准备</Tag>}
      <div style={{ marginTop: 8, fontSize: 14 }}>
        <span role="img" aria-label="cards">🎴</span> 剩余 {player.cardCount} 张
      </div>
      {player.isTurn && (
          <div style={{ 
              marginTop: 8, 
              color: '#1890ff', 
              fontWeight: 'bold',
              animation: 'pulse 1.5s infinite' 
          }}>
              思考中...
          </div>
      )}
      {typeof turnCountdown === 'number' && (
          <Tag color="orange" style={{ marginTop: 8, fontWeight: 'bold' }}>
              {turnCountdown}s
          </Tag>
      )}
    </div>
  );
};

export const GameRoom: React.FC<GameRoomProps> = ({ 
  myCards, myIndex, players, currentTurn, lastPlay, 
  onPlay, onPass, onHint, onBid, gameStatus, onLeave, onToggleReady, myReady, allReady, onAddAi
}) => {
  const [selectedIndices, setSelectedIndices] = useState<number[]>([]);
  const [hintLoading, setHintLoading] = useState<boolean>(false);
  const [turnCountdown, setTurnCountdown] = useState<number>(TURN_COUNTDOWN_SECONDS);
  const [bgmEnabled, setBgmEnabled] = useState<boolean>(false);
  const [voiceEnabled, setVoiceEnabled] = useState<boolean>(() => {
    if (typeof window === 'undefined') {
      return true;
    }
    return window.localStorage.getItem('ddz_voice_enabled') !== '0';
  });
  const audioCtxRef = useRef<AudioContext | null>(null);
  const bgmTimerRef = useRef<number | null>(null);

  const speakPhrase = (text: string) => {
    if (!voiceEnabled || !('speechSynthesis' in window)) return;
    window.speechSynthesis.cancel();
    const utterance = new SpeechSynthesisUtterance(text);
    utterance.lang = 'zh-CN';
    utterance.rate = 1.05;
    utterance.pitch = 1.02;
    window.speechSynthesis.speak(utterance);
  };

  useEffect(() => {
    const resetTimer = window.setTimeout(() => {
      setTurnCountdown(TURN_COUNTDOWN_SECONDS);
    }, 0);

    if (gameStatus !== 'playing' || currentTurn === 0) {
      return () => window.clearTimeout(resetTimer);
    }

    const timer = window.setInterval(() => {
      setTurnCountdown(prev => (prev > 0 ? prev - 1 : 0));
    }, 1000);

    return () => {
      window.clearTimeout(resetTimer);
      window.clearInterval(timer);
    };
  }, [currentTurn, gameStatus]);

  useEffect(() => {
    if (!bgmEnabled) {
      if (bgmTimerRef.current !== null) {
        window.clearInterval(bgmTimerRef.current);
        bgmTimerRef.current = null;
      }
      return;
    }
    const ensureAudioContext = () => {
      if (!audioCtxRef.current) {
        const Ctx = window.AudioContext || (window as Window & { webkitAudioContext?: typeof AudioContext }).webkitAudioContext;
        if (!Ctx) return null;
        audioCtxRef.current = new Ctx();
      }
      return audioCtxRef.current;
    };
    const playTone = (frequency: number, duration = 0.24) => {
      const ctx = ensureAudioContext();
      if (!ctx) return;
      if (ctx.state === 'suspended') {
        ctx.resume();
      }
      const oscillator = ctx.createOscillator();
      const gain = ctx.createGain();
      oscillator.type = 'triangle';
      oscillator.frequency.value = frequency;
      gain.gain.value = 0.03;
      oscillator.connect(gain);
      gain.connect(ctx.destination);
      oscillator.start();
      gain.gain.exponentialRampToValueAtTime(0.0001, ctx.currentTime + duration);
      oscillator.stop(ctx.currentTime + duration);
    };
    const melody = [392, 523, 659, 523, 440, 587, 698, 587];
    let index = 0;
    playTone(melody[index], 0.26);
    bgmTimerRef.current = window.setInterval(() => {
      index = (index + 1) % melody.length;
      playTone(melody[index], 0.26);
    }, 520);
    return () => {
      if (bgmTimerRef.current !== null) {
        window.clearInterval(bgmTimerRef.current);
        bgmTimerRef.current = null;
      }
    };
  }, [bgmEnabled]);

  useEffect(() => {
    return () => {
      if (bgmTimerRef.current !== null) {
        window.clearInterval(bgmTimerRef.current);
      }
      if ('speechSynthesis' in window) {
        window.speechSynthesis.cancel();
      }
    };
  }, []);

  const toggleCard = (index: number) => {
    if (selectedIndices.includes(index)) {
      setSelectedIndices(selectedIndices.filter(i => i !== index));
    } else {
      setSelectedIndices([...selectedIndices, index]);
    }
  };

  const handlePlay = () => {
    if (selectedIndices.length === 0) {
      message.warning('请选择要出的牌');
      return;
    }
    const sortedIndices = [...selectedIndices].sort((a, b) => a - b);
    const cards = sortedIndices.map(i => myCards[i]).filter(Boolean);
    if (cards.length === 0) {
      setSelectedIndices([]);
      return;
    }
    onPlay(cards);
    setSelectedIndices([]);
  };

  const handlePass = () => {
    speakPhrase('不要');
    onPass();
  };

  const handleBid = (score: number) => {
    if (score === 0) {
      speakPhrase('不叫');
    } else {
      speakPhrase(`叫${score}分`);
    }
    onBid(score);
  };

  const handleHint = async () => {
    if (!onHint) {
      return;
    }
    setHintLoading(true);
    try {
      const hintCards = await onHint();
      if (hintCards.length === 0) {
        setSelectedIndices([]);
        message.info('当前没有可出的牌');
        return;
      }
      const needMap = new Map<string, number>();
      hintCards.forEach(card => {
        const key = `${card.suit}-${card.value}`;
        needMap.set(key, (needMap.get(key) || 0) + 1);
      });
      const nextSelected: number[] = [];
      myCards.forEach((card, index) => {
        const key = `${card.suit}-${card.value}`;
        const rest = needMap.get(key) || 0;
        if (rest > 0) {
          nextSelected.push(index);
          needMap.set(key, rest - 1);
        }
      });
      if (nextSelected.length === 0) {
        message.warning('未找到可高亮的提示牌');
        return;
      }
      setSelectedIndices(nextSelected.sort((a, b) => a - b));
    } catch (error) {
      console.error('hint failed:', error);
      message.error('获取提示失败');
    } finally {
      setHintLoading(false);
    }
  };

  const isMyTurn = currentTurn === myIndex;
  
  const myPlayer = players.find(p => p.index === myIndex) || { 
    index: myIndex, 
    name: '我', 
    cardCount: myCards.length, 
    role: 'none' as const, 
    isTurn: isMyTurn 
  };
  
  const rightPlayer = players.find(p => getRelativePosition(myIndex, p.index) === 'right');
  const leftPlayer = players.find(p => getRelativePosition(myIndex, p.index) === 'left');

  return (
    <div style={{ 
      position: 'fixed',
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      display: 'flex', 
      flexDirection: 'column', 
      background: 'linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%)',
      overflow: 'hidden'
    }}>
      {/* Top Bar - Room Info / Exit */}
      <div style={{ padding: '16px 24px', display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
          <div style={{ color: 'white', fontSize: 18, fontWeight: 'bold' }}>
              斗地主 <Tag color={gameStatus === 'playing' ? 'green' : (gameStatus === 'bidding' ? 'gold' : 'blue')}>{gameStatus === 'playing' ? '游戏中' : (gameStatus === 'bidding' ? '叫分中' : '准备中')}</Tag>
          </div>
          <Space>
            <Button ghost onClick={() => setBgmEnabled(prev => !prev)}>
              {bgmEnabled ? '音乐:开' : '音乐:关'}
            </Button>
            <Button ghost onClick={() => setVoiceEnabled(prev => {
              const next = !prev;
              if (typeof window !== 'undefined') {
                window.localStorage.setItem('ddz_voice_enabled', next ? '1' : '0');
              }
              return next;
            })}>
              {voiceEnabled ? '语音:开' : '语音:关'}
            </Button>
            <Button danger ghost onClick={onLeave}>离开房间</Button>
          </Space>
      </div>

      {/* Main Game Area */}
      <div style={{ 
        flex: 1, 
        display: 'flex', 
        justifyContent: 'space-between', 
        alignItems: 'center',
        padding: '0 40px',
        position: 'relative'
      }}>
        {/* Left Player */}
        <div style={{ width: 160, display: 'flex', justifyContent: 'center' }}>
          {leftPlayer ? (
              <PlayerCard player={leftPlayer} turnCountdown={leftPlayer.isTurn && gameStatus === 'playing' ? turnCountdown : undefined} />
          ) : (
              <div style={{ 
                  width: 140, height: 180, 
                  border: '2px dashed rgba(255,255,255,0.3)', 
                  borderRadius: 12,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  color: 'rgba(255,255,255,0.5)'
              }}>等待加入...</div>
          )}
        </div>
        
        {/* Center - Table / Last Play */}
        <div style={{ 
          flex: 1, 
          display: 'flex', 
          justifyContent: 'center', 
          alignItems: 'center', 
          flexDirection: 'column',
          height: '100%'
        }}>
          <div style={{ 
              background: 'rgba(0,0,0,0.2)', 
              borderRadius: 20, 
              padding: '40px 60px',
              minWidth: 300,
              minHeight: 200,
              display: 'flex',
              justifyContent: 'center',
              alignItems: 'center',
              backdropFilter: 'blur(5px)',
              boxShadow: 'inset 0 0 20px rgba(0,0,0,0.2)'
          }}>
            {lastPlay.length > 0 ? (
              <div style={{ position: 'relative', height: 110, width: 80 + (lastPlay.length - 1) * 30 }}>
                {lastPlay.map((c, i) => renderCard(c, i, lastPlay.length, false, () => {}))}
              </div>
            ) : (
              <div style={{ color: 'rgba(255,255,255,0.4)', fontSize: 16 }}>
                  {gameStatus === 'playing' ? '等待出牌...' : '等待游戏开始...'}
              </div>
            )}
          </div>
        </div>
        
        {/* Right Player */}
        <div style={{ width: 160, display: 'flex', justifyContent: 'center' }}>
          {rightPlayer ? (
              <PlayerCard player={rightPlayer} turnCountdown={rightPlayer.isTurn && gameStatus === 'playing' ? turnCountdown : undefined} />
          ) : (
              <div style={{ 
                  width: 140, height: 180, 
                  border: '2px dashed rgba(255,255,255,0.3)', 
                  borderRadius: 12,
                  display: 'flex', alignItems: 'center', justifyContent: 'center',
                  color: 'rgba(255,255,255,0.5)'
              }}>等待加入...</div>
          )}
        </div>
      </div>

      {/* Bottom - My Area */}
      <div style={{ 
        flex: '0 0 300px', 
        display: 'flex', 
        flexDirection: 'column', 
        alignItems: 'center',
        background: 'linear-gradient(to top, rgba(0,0,0,0.8), transparent)',
        paddingTop: 20
      }}>
        {/* Action Buttons */}
        <div style={{ marginBottom: 30, height: 40 }}>
          {gameStatus === 'bidding' && isMyTurn && (
            <Space size="large">
              <Button size="large" onClick={() => handleBid(0)}>不叫</Button>
              <Button type="primary" size="large" onClick={() => handleBid(1)}>1分</Button>
              <Button type="primary" size="large" onClick={() => handleBid(2)}>2分</Button>
              <Button type="primary" size="large" onClick={() => handleBid(3)}>3分</Button>
            </Space>
          )}
          
          {gameStatus === 'playing' && isMyTurn && (
            <Space size="large">
              <Button size="large" onClick={handlePass} disabled={lastPlay.length === 0}>不出</Button>
              <Button size="large" onClick={handleHint} loading={hintLoading}>提示</Button>
              <Button type="primary" size="large" onClick={handlePlay} disabled={selectedIndices.length === 0}>
                  出牌
              </Button>
            </Space>
          )}

          {(gameStatus === 'waiting' || gameStatus === 'ready') && (
            <Space size="large">
              <Button 
                type="primary" 
                size="large" 
                onClick={() => onToggleReady(!myReady)} 
                style={{ width: 150, height: 50, fontSize: 18 }}
              >
                  {myReady ? '取消准备' : '准备'}
              </Button>
              {players.length >= 3 && (
                <Tag color={allReady ? 'green' : 'blue'} style={{ fontSize: 16, padding: '8px 16px' }}>
                  {allReady ? '全部已准备，等待开局' : '等待全员准备'}
                </Tag>
              )}
              {onAddAi && players.length < 3 && (
                <Button size="large" onClick={onAddAi} icon={<UserOutlined />}>
                    添加AI玩家
                </Button>
              )}
            </Space>
          )}
          
          {!isMyTurn && gameStatus !== 'waiting' && gameStatus !== 'finished' && (
             <Tag color="default" style={{ fontSize: 16, padding: '8px 16px' }}>等待其他玩家...</Tag>
          )}
        </div>

        {(gameStatus === 'bidding' || gameStatus === 'playing') && (
          <div style={{ marginBottom: 14 }}>
            <Space size="small" wrap>
              {COMMON_PHRASES.map((phrase) => (
                <Button key={phrase} size="small" onClick={() => speakPhrase(phrase)}>
                  {phrase}
                </Button>
              ))}
            </Space>
          </div>
        )}

        {/* My Info */}
        <div style={{ marginBottom: 20, color: 'white', display: 'flex', gap: 16, alignItems: 'center' }}>
            {isMyTurn && gameStatus === 'playing' && (
                <Tag color="orange" style={{ fontSize: 16, padding: '4px 10px', fontWeight: 'bold' }}>
                    {turnCountdown}s
                </Tag>
            )}
            <Avatar size="small" style={getAvatarStyle(myPlayer.role, isMyTurn)}>
              {renderAvatarSvg(myPlayer.name, myPlayer.role)}
            </Avatar>
            <span style={{ fontSize: 18, fontWeight: 'bold' }}>{myPlayer.name}</span>
            {myPlayer.role !== 'none' && (
                <Tag color={myPlayer.role === 'landlord' ? 'red' : 'blue'}>
                    {myPlayer.role === 'landlord' ? '地主' : '农民'}
                </Tag>
            )}
        </div>

        {/* My Cards */}
        <div style={{ 
            position: 'relative', 
            height: 130, 
            width: Math.min(800, window.innerWidth - 40),
            display: 'flex',
            justifyContent: 'center'
        }}>
          {myCards.map((c, i) => renderCard(c, i, myCards.length, selectedIndices.includes(i), () => toggleCard(i)))}
        </div>
      </div>
      
      <style>{`
          @keyframes pulse {
              0% { opacity: 1; transform: scale(1); }
              50% { opacity: 0.7; transform: scale(1.05); }
              100% { opacity: 1; transform: scale(1); }
          }
      `}</style>
    </div>
  );
};
