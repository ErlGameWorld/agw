import React, { useState } from 'react';
import { Card, Button, Modal, Input, message, Badge, Typography, Space, Flex } from 'antd';
import { PlusOutlined, ReloadOutlined, ThunderboltOutlined, RobotOutlined } from '@ant-design/icons';

const { Title, Text } = Typography;

interface Room {
  roomId: string;
  name: string;
  playerCount: number;
  status: number;
}

interface RoomListProps {
  onJoinRoom: (roomId: string) => void;
  onCreateRoom: (name: string) => void;
  onRefresh: () => void;
  onQuickMatch: () => void;
  onAddAi: () => void;
  rooms: Room[];
  currentRoomId?: string;
  isInRoom: boolean;
}

export const RoomList: React.FC<RoomListProps> = ({ 
  onJoinRoom, onCreateRoom, onRefresh, onQuickMatch, onAddAi, 
  rooms, currentRoomId, isInRoom 
}) => {
  const [isModalVisible, setIsModalVisible] = useState(false);
  const [newRoomName, setNewRoomName] = useState('');

  const handleCreate = () => {
    if (!newRoomName.trim()) {
      message.error('请输入房间名');
      return;
    }
    onCreateRoom(newRoomName.trim());
    setIsModalVisible(false);
    setNewRoomName('');
  };

  const getStatusBadge = (status: number) => {
    switch (status) {
      case 0: return <Badge status="processing" text="等待中" />;
      case 1: return <Badge status="warning" text="游戏中" />;
      case 2: return <Badge status="success" text="准备中" />;
      case 3: return <Badge status="warning" text="叫分中" />;
      case 4: return <Badge status="default" text="已结束" />;
      default: return <Badge status="default" text="未知" />;
    }
  };

  return (
    <div style={{ 
      position: 'fixed',
      top: 0,
      left: 0,
      right: 0,
      bottom: 0,
      background: 'linear-gradient(135deg, #1a1a2e 0%, #16213e 50%, #0f3460 100%)',
      overflow: 'auto',
      padding: 24
    }}>
      <div style={{ maxWidth: 1200, margin: '0 auto' }}>
        <Card style={{ 
          borderRadius: 16, 
          marginBottom: 24,
          background: 'rgba(255,255,255,0.95)',
          boxShadow: '0 10px 40px rgba(0,0,0,0.3)'
        }}>
          <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
            <Title level={3} style={{ margin: 0, color: '#1a1a2e' }}>🃏 游戏大厅</Title>
            <Space>
              <Button 
                icon={<ReloadOutlined />} 
                onClick={onRefresh}
                size="large"
              >
                刷新
              </Button>
              <Button 
                type="primary" 
                icon={<PlusOutlined />} 
                onClick={() => setIsModalVisible(true)}
                disabled={isInRoom}
                size="large"
                style={{
                  background: 'linear-gradient(135deg, #667eea 0%, #764ba2 100%)',
                  border: 'none'
                }}
              >
                创建房间
              </Button>
            </Space>
          </div>
        </Card>

        <Card style={{ 
          borderRadius: 16, 
          marginBottom: 24,
          background: 'rgba(255,255,255,0.1)',
          border: '1px solid rgba(255,255,255,0.2)'
        }}>
          <div style={{ textAlign: 'center', padding: '30px 0' }}>
            <Title level={3} style={{ color: '#fff', marginBottom: 8 }}>快速开始</Title>
            <Text style={{ display: 'block', marginBottom: 24, color: 'rgba(255,255,255,0.7)' }}>
              自动匹配空闲房间或创建新房间
            </Text>
            <Space size="large">
              <Button 
                type="primary" 
                size="large"
                icon={<ThunderboltOutlined />}
                onClick={onQuickMatch}
                disabled={isInRoom}
                style={{ 
                  background: 'linear-gradient(135deg, #f093fb 0%, #f5576c 100%)',
                  border: 'none',
                  minWidth: 180,
                  height: 50,
                  fontSize: 16,
                  borderRadius: 8
                }}
              >
                快速匹配
              </Button>
              {isInRoom && (
                <Button 
                  size="large"
                  icon={<RobotOutlined />}
                  onClick={onAddAi}
                  style={{ 
                    minWidth: 180, 
                    height: 50, 
                    fontSize: 16,
                    borderRadius: 8
                  }}
                >
                  添加AI玩家
                </Button>
              )}
            </Space>
          </div>
        </Card>

        <div style={{ marginBottom: 16, marginTop: 32 }}>
          <Text strong style={{ fontSize: 18, color: '#fff' }}>房间列表</Text>
        </div>

        {rooms.length === 0 ? (
          <Card style={{ 
            borderRadius: 16, 
            textAlign: 'center', 
            padding: 60,
            background: 'rgba(255,255,255,0.1)',
            border: '1px solid rgba(255,255,255,0.2)'
          }}>
            <Text style={{ color: 'rgba(255,255,255,0.7)', fontSize: 16 }}>
              暂无房间，点击"创建房间"或"快速匹配"开始游戏
            </Text>
          </Card>
        ) : (
          <Flex gap={20} wrap="wrap">
            {rooms.map(item => (
              <Card 
                key={item.roomId}
                hoverable
                style={{ 
                  borderRadius: 12, 
                  width: 280,
                  background: 'rgba(255,255,255,0.95)',
                  boxShadow: '0 4px 20px rgba(0,0,0,0.2)'
                }}
                actions={[
                  currentRoomId === item.roomId ? (
                    <Text type="secondary">已加入</Text>
                  ) : (
                    <Button 
                      type="link" 
                      onClick={() => onJoinRoom(item.roomId)}
                      disabled={(item.status === 1 || item.status === 3) || item.playerCount >= 3 || isInRoom}
                    >
                      {(item.status === 1 || item.status === 3) ? '进行中' : (item.playerCount >= 3 ? '已满' : '加入')}
                    </Button>
                  )
                ]}
              >
                <Card.Meta
                  title={
                    <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'center' }}>
                      <Text ellipsis style={{ maxWidth: 180 }}>{item.name}</Text>
                      {currentRoomId === item.roomId && (
                        <Badge color="green" />
                      )}
                    </div>
                  }
                  description={
                    <div>
                      <div style={{ marginBottom: 12 }}>
                        {getStatusBadge(item.status)}
                      </div>
                      <div style={{ display: 'flex', justifyContent: 'space-between' }}>
                        <Text type="secondary">人数</Text>
                        <Text strong>{item.playerCount}/3</Text>
                      </div>
                    </div>
                  }
                />
              </Card>
            ))}
          </Flex>
        )}
      </div>

      <Modal 
        title="创建房间" 
        open={isModalVisible} 
        onOk={handleCreate} 
        onCancel={() => setIsModalVisible(false)}
        okText="创建"
        cancelText="取消"
        centered
      >
        <div style={{ marginBottom: 16 }}>
          <Text type="secondary">为你的房间取个名字吧</Text>
        </div>
        <Input 
          placeholder="请输入房间名" 
          value={newRoomName} 
          onChange={e => setNewRoomName(e.target.value)}
          maxLength={20}
          onPressEnter={handleCreate}
          size="large"
        />
      </Modal>
    </div>
  );
};
