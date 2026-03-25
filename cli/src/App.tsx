import React from 'react';
import { useGameClient } from './hooks/useGameClient';
import { Login } from './components/Login';
import { RoomList } from './components/RoomList';
import { GameRoom } from './components/GameRoom';
import { GameOverModal } from './components/GameOverModal';

const App: React.FC = () => {
  const {
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
    actions
  } = useGameClient();

  return (
    <div className="App">
      {stage === 'login' && <Login onLogin={actions.login} playerInfo={playerInfo} />}
      {stage === 'lobby' && (
        <RoomList 
          rooms={rooms} 
          onJoinRoom={actions.joinRoom} 
          onCreateRoom={actions.createRoom}
          onRefresh={actions.refreshRooms}
          onQuickMatch={actions.quickMatch}
          onAddAi={actions.addAi}
          currentRoomId={currentRoomId}
          isInRoom={!!currentRoomId}
        />
      )}
      {stage === 'game' && (
        <GameRoom 
          myCards={myCards}
          myIndex={myIndex}
          players={players}
          currentTurn={currentTurn}
          landlordIdx={landlordIdx}
          lastPlay={lastPlay}
          onPlay={actions.playCards}
          onPass={actions.passTurn}
          onHint={actions.playHint}
          onBid={actions.bid}
          gameStatus={gameStatus}
          onLeave={actions.leaveRoom}
          onToggleReady={actions.setReady}
          myReady={myReady}
          allReady={allReady}
          onAddAi={actions.addAi}
        />
      )}
      
      {gameOverData && (
        <GameOverModal 
          visible={!!gameOverData}
          isWin={gameOverData.isWin}
          winnerIdx={gameOverData.winnerIdx}
          onClose={actions.resetGame}
        />
      )}
    </div>
  );
};

export default App;
