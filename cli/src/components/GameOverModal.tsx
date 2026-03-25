import React, { useEffect, useRef, useState } from 'react';
import { Modal, Button, Result } from 'antd';
import { TrophyOutlined, FrownOutlined } from '@ant-design/icons';

interface GameOverModalProps {
  visible: boolean;
  isWin: boolean;
  winnerIdx: number;
  onClose: () => void;
}

export const GameOverModal: React.FC<GameOverModalProps> = ({ visible, isWin, winnerIdx, onClose }) => {
  const [countdown, setCountdown] = useState(3);
  const closedRef = useRef(false);

  useEffect(() => {
    if (visible) {
      const resetTimer = setTimeout(() => {
        closedRef.current = false;
        setCountdown(3);
      }, 0);
      const timer = setInterval(() => {
        setCountdown((prev) => {
          if (prev <= 1) {
            if (!closedRef.current) {
              closedRef.current = true;
              onClose();
            }
            clearInterval(timer);
            return 0;
          }
          return prev - 1;
        });
      }, 1000);
      return () => {
        clearTimeout(resetTimer);
        clearInterval(timer);
      };
    }
    closedRef.current = false;
    return;
  }, [visible, onClose]);

  return (
    <Modal
      open={visible}
      footer={null}
      closable={false}
      centered
      maskClosable={false}
      bodyStyle={{ textAlign: 'center', padding: '20px 0' }}
    >
      <Result
        icon={isWin ? <TrophyOutlined style={{ color: '#faad14' }} /> : <FrownOutlined style={{ color: '#ff4d4f' }} />}
        title={isWin ? '恭喜获胜！' : '很遗憾，下次加油！'}
        subTitle={
          <div style={{ fontSize: 16 }}>
            <div style={{ marginBottom: 8 }}>玩家 {winnerIdx} 获胜</div>
            <div style={{ color: '#999' }}>{countdown} 秒后返回大厅...</div>
          </div>
        }
        extra={[
          <Button type="primary" key="back" onClick={onClose}>
            立即返回
          </Button>,
        ]}
      />
    </Modal>
  );
};
